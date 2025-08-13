-- Release Console PoC Database Schema
-- This schema defines the database structure for tracking release approvals and workflows

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create enum types
CREATE TYPE release_status AS ENUM (
    'pending',
    'approved', 
    'rejected',
    'deployed',
    'failed',
    'cancelled'
);

CREATE TYPE approval_status AS ENUM (
    'pending',
    'approved',
    'rejected',
    'changes_requested'
);

-- Releases table
CREATE TABLE releases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    version VARCHAR(50) NOT NULL UNIQUE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    release_notes TEXT,
    status release_status DEFAULT 'pending' NOT NULL,
    repository VARCHAR(255) NOT NULL,
    branch VARCHAR(100) DEFAULT 'main' NOT NULL,
    commit_sha VARCHAR(40) NOT NULL,
    created_by VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    deployed_at TIMESTAMP WITH TIME ZONE,
    slack_message_ts VARCHAR(50), -- Slack message timestamp for updates
    slack_channel VARCHAR(100),   -- Channel where approval was requested
    github_run_id VARCHAR(50),    -- GitHub Actions run ID
    metadata JSONB DEFAULT '{}' NOT NULL -- Additional metadata
);

-- Approvals table
CREATE TABLE approvals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    release_id UUID NOT NULL REFERENCES releases(id) ON DELETE CASCADE,
    user_id VARCHAR(255) NOT NULL,     -- Slack user ID
    user_name VARCHAR(255) NOT NULL,   -- Slack username
    user_email VARCHAR(255),           -- User email if available
    status approval_status DEFAULT 'pending' NOT NULL,
    comment TEXT,
    approved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    slack_action_id VARCHAR(50),       -- Slack action that triggered this
    ip_address INET,                   -- IP address of approval action
    user_agent TEXT                    -- User agent for audit trail
);

-- Release environments table (for multi-stage deployments)
CREATE TABLE release_environments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    release_id UUID NOT NULL REFERENCES releases(id) ON DELETE CASCADE,
    environment VARCHAR(50) NOT NULL,  -- staging, production, etc.
    status release_status DEFAULT 'pending' NOT NULL,
    deployed_at TIMESTAMP WITH TIME ZONE,
    deployed_by VARCHAR(255),
    rollback_version VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(release_id, environment)
);

-- Audit log for all actions
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    release_id UUID REFERENCES releases(id) ON DELETE SET NULL,
    approval_id UUID REFERENCES approvals(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,      -- created, approved, rejected, deployed, etc.
    actor VARCHAR(255) NOT NULL,       -- Who performed the action
    details JSONB DEFAULT '{}' NOT NULL, -- Action details
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    ip_address INET,
    user_agent TEXT
);

-- Slack workspace configuration
CREATE TABLE slack_workspaces (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id VARCHAR(50) NOT NULL UNIQUE,
    workspace_name VARCHAR(255) NOT NULL,
    bot_token_encrypted TEXT NOT NULL, -- Encrypted bot token
    default_channel VARCHAR(100),
    approver_roles JSONB DEFAULT '[]' NOT NULL, -- Roles that can approve
    required_approvals INTEGER DEFAULT 1 NOT NULL,
    auto_deploy BOOLEAN DEFAULT false NOT NULL,
    active BOOLEAN DEFAULT true NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Indexes for performance
CREATE INDEX idx_releases_status ON releases(status);
CREATE INDEX idx_releases_created_at ON releases(created_at DESC);
CREATE INDEX idx_releases_version ON releases(version);
CREATE INDEX idx_releases_repository ON releases(repository);

CREATE INDEX idx_approvals_release_id ON approvals(release_id);
CREATE INDEX idx_approvals_user_id ON approvals(user_id);
CREATE INDEX idx_approvals_status ON approvals(status);
CREATE INDEX idx_approvals_created_at ON approvals(created_at DESC);

CREATE INDEX idx_audit_log_release_id ON audit_log(release_id);
CREATE INDEX idx_audit_log_timestamp ON audit_log(timestamp DESC);
CREATE INDEX idx_audit_log_action ON audit_log(action);

CREATE INDEX idx_release_environments_release_id ON release_environments(release_id);
CREATE INDEX idx_release_environments_environment ON release_environments(environment);

-- Updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at triggers
CREATE TRIGGER update_releases_updated_at BEFORE UPDATE ON releases
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_approvals_updated_at BEFORE UPDATE ON approvals
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_release_environments_updated_at BEFORE UPDATE ON release_environments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_slack_workspaces_updated_at BEFORE UPDATE ON slack_workspaces
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Row Level Security (RLS) policies
ALTER TABLE releases ENABLE ROW LEVEL SECURITY;
ALTER TABLE approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE release_environments ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE slack_workspaces ENABLE ROW LEVEL SECURITY;

-- Basic policies (customize based on your auth requirements)
-- Allow all operations for authenticated users (modify as needed)
CREATE POLICY "Allow all for authenticated users" ON releases
    FOR ALL USING (auth.role() = 'authenticated');

CREATE POLICY "Allow all for authenticated users" ON approvals
    FOR ALL USING (auth.role() = 'authenticated');

CREATE POLICY "Allow all for authenticated users" ON release_environments
    FOR ALL USING (auth.role() = 'authenticated');

CREATE POLICY "Allow all for authenticated users" ON audit_log
    FOR ALL USING (auth.role() = 'authenticated');

CREATE POLICY "Allow all for authenticated users" ON slack_workspaces
    FOR ALL USING (auth.role() = 'authenticated');

-- Views for common queries
CREATE VIEW release_summary AS
SELECT 
    r.id,
    r.version,
    r.title,
    r.status,
    r.repository,
    r.created_by,
    r.created_at,
    r.deployed_at,
    COUNT(a.id) as total_approvals,
    COUNT(CASE WHEN a.status = 'approved' THEN 1 END) as approved_count,
    COUNT(CASE WHEN a.status = 'rejected' THEN 1 END) as rejected_count,
    COUNT(CASE WHEN a.status = 'pending' THEN 1 END) as pending_count
FROM releases r
LEFT JOIN approvals a ON r.id = a.release_id
GROUP BY r.id, r.version, r.title, r.status, r.repository, r.created_by, r.created_at, r.deployed_at;

-- Function to automatically create audit log entries
CREATE OR REPLACE FUNCTION create_audit_entry()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (release_id, action, actor, details)
        VALUES (
            NEW.id,
            CASE 
                WHEN TG_TABLE_NAME = 'releases' THEN 'release_created'
                WHEN TG_TABLE_NAME = 'approvals' THEN 'approval_created'
                ELSE TG_OP::text
            END,
            COALESCE(NEW.created_by, NEW.user_id, 'system'),
            to_jsonb(NEW)
        );
        RETURN NEW;
    END IF;
    
    IF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (release_id, action, actor, details)
        VALUES (
            NEW.id,
            CASE 
                WHEN TG_TABLE_NAME = 'releases' THEN 'release_updated'
                WHEN TG_TABLE_NAME = 'approvals' THEN 'approval_updated'
                ELSE TG_OP::text
            END,
            COALESCE(NEW.created_by, NEW.user_id, 'system'),
            jsonb_build_object(
                'old', to_jsonb(OLD),
                'new', to_jsonb(NEW)
            )
        );
        RETURN NEW;
    END IF;
    
    RETURN NULL;
END;
$$ language 'plpgsql';

-- Apply audit triggers
CREATE TRIGGER releases_audit_trigger
    AFTER INSERT OR UPDATE ON releases
    FOR EACH ROW EXECUTE FUNCTION create_audit_entry();

CREATE TRIGGER approvals_audit_trigger
    AFTER INSERT OR UPDATE ON approvals
    FOR EACH ROW EXECUTE FUNCTION create_audit_entry();

-- Sample data for testing (optional)
-- INSERT INTO slack_workspaces (workspace_id, workspace_name, bot_token_encrypted, default_channel)
-- VALUES ('T1234567890', 'Test Workspace', 'encrypted_token_here', '#releases');

-- Grant necessary permissions (adjust based on your setup)
-- GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
-- GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
