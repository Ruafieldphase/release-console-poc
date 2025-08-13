#!/usr/bin/env node

/**
 * Generate Release Candidate Markdown
 * This script generates markdown content for release candidate notifications
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function getLatestTag() {
  try {
    return execSync('git describe --tags --abbrev=0', { encoding: 'utf8' }).trim();
  } catch (error) {
    return 'v0.0.0';
  }
}

function getCommitsSinceTag(tag) {
  try {
    const commits = execSync(`git log ${tag}..HEAD --oneline`, { encoding: 'utf8' });
    return commits.trim().split('\n').filter(line => line.length > 0);
  } catch (error) {
    return [];
  }
}

function generateReleaseNotes() {
  const latestTag = getLatestTag();
  const commits = getCommitsSinceTag(latestTag);
  const currentVersion = process.env.INPUT_VERSION || 'v1.0.0';
  
  let markdown = `# Release Candidate: ${currentVersion}\n\n`;
  markdown += `## Changes since ${latestTag}\n\n`;
  
  if (commits.length === 0) {
    markdown += '- No new commits since last release\n';
  } else {
    commits.forEach(commit => {
      const [hash, ...messageParts] = commit.split(' ');
      const message = messageParts.join(' ');
      markdown += `- ${message} (${hash})\n`;
    });
  }
  
  markdown += '\n## Release Checklist\n';
  markdown += '- [ ] Code review completed\n';
  markdown += '- [ ] Tests passing\n';
  markdown += '- [ ] Documentation updated\n';
  markdown += '- [ ] Ready for deployment\n';
  
  return markdown;
}

function main() {
  try {
    const releaseNotes = generateReleaseNotes();
    console.log('Generated release notes:');
    console.log(releaseNotes);
    
    // Output for GitHub Actions
    console.log(`::set-output name=notes::${releaseNotes}`);
    
    // Save to file
    const outputPath = path.join(process.cwd(), 'release-notes.md');
    fs.writeFileSync(outputPath, releaseNotes);
    console.log(`Release notes saved to: ${outputPath}`);
    
  } catch (error) {
    console.error('Error generating release notes:', error);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}

module.exports = { generateReleaseNotes };
