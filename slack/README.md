# Slack Integration for Release Console PoC

This directory contains the Slack application configuration and documentation for the release approval workflow.

## Overview

The Release Console PoC integrates with Slack to provide a chat-based approval system for software releases. Team members can review, approve, or reject releases directly from Slack using interactive buttons and slash commands.

## Files

### `manifest.json`
Slack app manifest that defines:
- Bot permissions and capabilities
- Slash commands (`/release-status`, `/release-approve`, `/release-reject`)
- Interactive components (buttons for approve/reject/request changes)
- OAuth scopes and event subscriptions

## Setup Instructions

### 1. Create Slack App
1. Go to [Slack API](https://api.slack.com/apps)
2. Click "Create New App"
3. Choose "From an app manifest"
4. Select your workspace
5. Copy and paste the contents of `manifest.json`
6. Review and create the app

### 2. Install App to Workspace
1. In your app's settings, go to "Install App"
2. Click "Install to Workspace"
3. Authorize the app
4. Copy the "Bot User OAuth Token"

### 3. Configure Environment Variables
Add these to your CI/CD environment:
```bash
SLACK_BOT_TOKEN=xoxb-your-bot-token-here
SLACK_CHANNEL=#releases  # or your preferred channel
```

### 4. Update Webhook URLs
In the manifest.json, replace `https://your-app.com/` with your actual application URL:
- Slash command URLs
- Interactivity request URL
- Events request URL

## Slash Commands

### `/release-status [version]`
Check the status of pending releases
```
/release-status v1.2.0
```

### `/release-approve [version] [reason]`
Approve a release for deployment
```
/release-approve v1.2.0 LGTM, all tests passing
```

### `/release-reject [version] [reason]`
Reject a release request
```
/release-reject v1.2.0 Found critical bug in payment flow
```

## Interactive Components

When a release request is posted to Slack, it includes interactive buttons:
- ✅ **Approve** - Approve the release
- ❌ **Reject** - Reject the release
- 🤔 **Request Changes** - Request modifications before approval

## Permissions Required

The app requires these OAuth scopes:
- `channels:read` - Read channel information
- `chat:write` - Post messages to channels
- `commands` - Add slash commands
- `users:read` - Read user information
- `users:read.email` - Read user email addresses
- `im:write` - Send direct messages
- `mpim:write` - Send group direct messages

## Event Subscriptions

The app listens for these events:
- `app_mention` - When the bot is mentioned
- `message.channels` - Messages in channels
- `message.groups` - Messages in private channels
- `message.im` - Direct messages
- `message.mpim` - Group direct messages

## Security Notes

- Keep your bot token secure and never commit it to version control
- Use environment variables for sensitive configuration
- Regularly rotate tokens following your security policies
- Consider using Slack's token rotation feature

## Troubleshooting

### Common Issues

1. **Bot not responding to commands**
   - Verify the bot token is correct
   - Check that the app is installed in the workspace
   - Ensure the bot has been invited to the channel

2. **Interactive buttons not working**
   - Verify the request URL is accessible
   - Check that HTTPS is properly configured
   - Review webhook endpoint implementation

3. **Commands not showing up**
   - Re-install the app to workspace
   - Check slash command configuration
   - Verify app permissions

## Development

For local development:
1. Use ngrok or similar tool to expose local server
2. Update manifest URLs to point to your tunnel
3. Test with a development Slack workspace
4. Monitor webhook requests for debugging

## Support

For issues related to Slack integration:
1. Check Slack API documentation
2. Review app event logs in Slack console
3. Test webhook endpoints manually
4. Verify OAuth scopes match requirements
