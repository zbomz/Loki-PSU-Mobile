# Version Bumping Implementation - Summary

## Overview
Your Flutter app now automatically increments the build number every time you push to GitHub's `main` or `develop` branches.

## Files Created

### Scripts
1. **`.github/scripts/bump_version.sh`**
   - Bash script for Linux/macOS environments (used in GitHub Actions)
   - Automatically increments build number in `pubspec.yaml`
   - Outputs version info for GitHub Actions

2. **`.github/scripts/bump_version.ps1`**
   - PowerShell script for Windows (local development)
   - Same functionality as bash version
   - Can be run locally to test version bumping

### Workflows
3. **`.github/workflows/build_android.yml`** (NEW)
   - Complete Android build pipeline
   - Auto-bumps version before building
   - Builds both APK and App Bundle
   - Uploads artifacts with version numbers

4. **`.github/workflows/version_bump.yml`** (NEW)
   - Reusable workflow for version bumping
   - Can be called by other workflows in the future
   - Includes skip logic for `[skip ci]` commits

### Documentation
5. **`VERSION_MANAGEMENT.md`**
   - Comprehensive guide to version management
   - Explains how auto-bumping works
   - Troubleshooting section
   - Manual version bump instructions

6. **`QUICKSTART_VERSION.md`**
   - Quick reference guide
   - Testing instructions
   - Common use cases

## Files Modified

### Workflows
1. **`.github/workflows/build_ios_signed.yml`**
   - Added version bump step before building
   - Added commit step to push version changes
   - Updated artifact name to include build number
   - Checkout now includes fetch-depth for git operations

### Documentation
2. **`README.md`**
   - Complete rewrite with proper project structure
   - Added version management section
   - Added links to all documentation
   - Better organization and clarity

3. **`PRE_PUSH_CHECKLIST.md`**
   - Added version management section
   - Explains when to manually update versions
   - Notes about auto-increment behavior

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  Developer pushes code to main/develop                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  GitHub Actions workflow starts                             │
│  (build_ios_signed.yml or build_android.yml)                │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Checkout code with full git history                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Run bump_version.sh script                                 │
│  • Read current version from pubspec.yaml                   │
│  • Increment build number (+1)                              │
│  • Update pubspec.yaml                                      │
│  • Output new version to GITHUB_OUTPUT                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Commit version change                                      │
│  • Configure git user as github-actions[bot]                │
│  • Commit with message: "chore: bump version to X [skip ci]"│
│  • Push back to repository                                  │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Continue with build process                                │
│  • Setup Flutter                                            │
│  • Run tests                                                │
│  • Build app                                                │
│  • Upload artifacts (named with build number)               │
└─────────────────────────────────────────────────────────────┘
```

## Version Format

```
version: MAJOR.MINOR.PATCH+BUILD_NUMBER
         └──────┬──────┘ └────┬────┘
                │             │
         Semantic version     │
         (manual update)      │
                              │
                     Auto-incremented
                     (on every push)
```

### Examples
- Initial: `1.0.0+1`
- After 1st push: `1.0.0+2`
- After 2nd push: `1.0.0+3`
- After manual version update: `1.1.0+3`
- After next push: `1.1.0+4`

## Key Features

### ✅ Automatic Build Numbering
- No manual intervention required
- Increments on every push to main/develop
- Unique build ID for every build

### ✅ CI/CD Integration
- Version committed back to repo automatically
- Uses `[skip ci]` to prevent infinite loops
- Build artifacts named with version numbers

### ✅ Cross-Platform Support
- Bash script for GitHub Actions (Linux/macOS)
- PowerShell script for local Windows testing
- Works for both iOS and Android builds

### ✅ Git-Friendly
- Version commits clearly labeled
- Easy to track in git history
- No merge conflicts (commits pushed immediately)

### ✅ Reusable Workflow
- Can be called by future workflows
- Centralized version management
- Consistent behavior across builds

## Testing Locally (Optional)

### On Windows
```powershell
cd C:\Users\zbomsta\Desktop\PivotalPleb\Loki-PSU-Mobile
.\.github\scripts\bump_version.ps1
```

### On Linux/macOS
```bash
cd /path/to/Loki-PSU-Mobile
chmod +x .github/scripts/bump_version.sh
./.github/scripts/bump_version.sh
```

## Next Steps

1. **Test the implementation**
   - Make a small change to your code
   - Push to develop branch
   - Check GitHub Actions to see version bump in action

2. **Verify artifacts**
   - After successful build, check the Actions artifacts
   - They should be named with version numbers (e.g., `loki-psu-ios-signed-2`)

3. **Monitor git history**
   - You'll see automatic commits from github-actions[bot]
   - These are the version bump commits

## Troubleshooting

If the version doesn't increment:
1. Check workflow permissions (Settings > Actions > General)
2. Ensure `GITHUB_TOKEN` has write permissions
3. Check workflow logs for errors in the bump step

For more details, see [VERSION_MANAGEMENT.md](VERSION_MANAGEMENT.md).

---

**Implementation Date**: February 17, 2026  
**Status**: ✅ Complete and Ready for Use
