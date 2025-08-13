#!/usr/bin/env node

/**
 * Post Release Notes to Slack
 * This script posts release notes to a Slack channel for approval
 */

const { WebClient } = require('@slack/web-api');
const fs = require('fs');
const path = require('path');

// Initialize Slack client
const slack = new WebClient(process.env.SLACK_BOT_TOKEN);

function formatSlackMessage(releaseNotes, version) {
  return {
    channel: process.env.SLACK_CHANNEL || '#releases',
    text: `Release Approval Request: ${version}`,
    blocks: [
      {
        type: 'header',
        text: {
          type: 'plain_text',
          text: `🚀 Release Approval Request: ${version}`,
          emoji: true
        }
      },
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: releaseNotes
        }
      },
      {
        type: 'divider'
      },
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: '*Please review and approve this release:*'
        }
      },
      {
        type: 'actions',
        elements: [
          {
            type: 'button',
            text: {
              type: 'plain_text',
              text: '✅ Approve',
              emoji: true
            },
            value: 'approve',
            action_id: 'release_approve',
            style: 'primary'
          },
          {
            type: 'button',
            text: {
              type: 'plain_text',
              text: '❌ Reject',
              emoji: true
            },
            value: 'reject',
            action_id: 'release_reject',
            style: 'danger'
          },
          {
            type: 'button',
            text: {
              type: 'plain_text',
              text: '🤔 Request Changes',
              emoji: true
            },
            value: 'changes',
            action_id: 'release_changes'
          }
        ]
      },
      {
        type: 'context',
        elements: [
          {
            type: 'mrkdwn',
            text: `Repository: ${process.env.GITHUB_REPOSITORY || 'N/A'} | Run: ${process.env.GITHUB_RUN_ID || 'N/A'}`
          }
        ]
      }
    ]
  };
}

async function postToSlack() {
  try {
    // Get release notes from environment or file
    let releaseNotes = process.env.RELEASE_NOTES;
    
    if (!releaseNotes) {
      const notesPath = path.join(process.cwd(), 'release-notes.md');
      if (fs.existsSync(notesPath)) {
        releaseNotes = fs.readFileSync(notesPath, 'utf8');
      } else {
        throw new Error('No release notes found in environment or file');
      }
    }
    
    const version = process.env.INPUT_VERSION || process.env.GITHUB_REF_NAME || 'Unknown Version';
    
    // Format message for Slack
    const message = formatSlackMessage(releaseNotes, version);
    
    // Post to Slack
    console.log(`Posting release approval request to Slack channel: ${message.channel}`);
    const result = await slack.chat.postMessage(message);
    
    console.log('Message posted successfully:', result.ts);
    console.log('Channel:', result.channel);
    
    // Save message info for potential follow-up actions
    const messageInfo = {
      channel: result.channel,
      timestamp: result.ts,
      version: version,
      posted_at: new Date().toISOString()
    };
    
    fs.writeFileSync(
      path.join(process.cwd(), 'slack-message-info.json'),
      JSON.stringify(messageInfo, null, 2)
    );
    
    console.log('Message info saved to slack-message-info.json');
    
  } catch (error) {
    console.error('Error posting to Slack:', error);
    process.exit(1);
  }
}

// Main execution
if (require.main === module) {
  postToSlack();
}

module.exports = { postToSlack, formatSlackMessage };
