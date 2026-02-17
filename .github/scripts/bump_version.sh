#!/bin/bash

# Script to automatically bump version in pubspec.yaml
# This script increments the build number while keeping the version number the same
# Format: version: MAJOR.MINOR.PATCH+BUILD_NUMBER (e.g., 1.0.0+1)

set -e

PUBSPEC_FILE="pubspec.yaml"

if [ ! -f "$PUBSPEC_FILE" ]; then
    echo "Error: pubspec.yaml not found!"
    exit 1
fi

# Extract current version line
CURRENT_VERSION_LINE=$(grep "^version:" $PUBSPEC_FILE)
echo "Current version line: $CURRENT_VERSION_LINE"

# Extract version number and build number
CURRENT_VERSION=$(echo $CURRENT_VERSION_LINE | sed 's/version: //' | sed 's/ //g')
VERSION_NUMBER=$(echo $CURRENT_VERSION | cut -d'+' -f1)
BUILD_NUMBER=$(echo $CURRENT_VERSION | cut -d'+' -f2)

echo "Current version: $VERSION_NUMBER"
echo "Current build number: $BUILD_NUMBER"

# Increment build number
NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
NEW_VERSION="${VERSION_NUMBER}+${NEW_BUILD_NUMBER}"

echo "New version: $NEW_VERSION"

# Update pubspec.yaml
sed -i "s/version: ${CURRENT_VERSION}/version: ${NEW_VERSION}/" $PUBSPEC_FILE

echo "✅ Version bumped from $CURRENT_VERSION to $NEW_VERSION"

# Output for GitHub Actions
echo "NEW_VERSION=$NEW_VERSION" >> $GITHUB_OUTPUT
echo "BUILD_NUMBER=$NEW_BUILD_NUMBER" >> $GITHUB_OUTPUT

# Create a job summary for GitHub Actions UI
if [ -n "$GITHUB_STEP_SUMMARY" ]; then
  cat >> $GITHUB_STEP_SUMMARY << EOF
## 📦 Version Bump

| Property | Value |
|----------|-------|
| **Previous Version** | \`$CURRENT_VERSION\` |
| **New Version** | \`$NEW_VERSION\` |
| **Build Number** | \`$NEW_BUILD_NUMBER\` |

The version has been automatically incremented and will be committed to the repository.
EOF
fi
