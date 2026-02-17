# Quick Start: Automatic Version Bumping

## Summary

Your app now **automatically gets a new build ID** every time you push to GitHub! 🎉

```yaml
# Before push: version: 1.0.0+1
# After push:  version: 1.0.0+2
# Next push:   version: 1.0.0+3
```

## What Changed

✅ **Created Scripts**:
- `.github/scripts/bump_version.sh` (Linux/macOS)
- `.github/scripts/bump_version.ps1` (Windows)

✅ **Updated Workflows**:
- `build_ios_signed.yml` - Auto-bumps version before building iOS
- Created `build_android.yml` - Auto-bumps version before building Android

✅ **Documentation**:
- `VERSION_MANAGEMENT.md` - Full details
- Updated `README.md` - Added version management section
- Updated `PRE_PUSH_CHECKLIST.md` - Added version notes

## How It Works

1. You push code to `main` or `develop`
2. GitHub Actions runs
3. Build number increments (e.g., `+1` → `+2`)
4. Change commits back with `[skip ci]` tag
5. Build proceeds with new version

## Test It Now

```powershell
# See current version
cd C:\Users\zbomsta\Desktop\PivotalPleb\Loki-PSU-Mobile
Get-Content pubspec.yaml | Select-String "version:"

# Test the bump script (optional - only if you want to bump locally)
.\.github\scripts\bump_version.ps1
```

## When You Push Next

Just push normally:
```bash
git add .
git commit -m "Add new feature"
git push
```

The version will automatically increment! Check the Actions tab on GitHub to see it happen.

## Changing Version Numbers

The build number (the part after `+`) increments automatically.

To change the **semantic version** (the part before `+`), edit `pubspec.yaml`:

```yaml
# From:
version: 1.0.0+42

# To (for a new minor release):
version: 1.1.0+42
```

The build number will continue incrementing from there.

## Artifact Names

Build artifacts now include the build number:
- iOS: `loki-psu-ios-signed-42`
- Android: `loki-psu-android-apk-42`, `loki-psu-android-bundle-42`

## Need Help?

See [VERSION_MANAGEMENT.md](VERSION_MANAGEMENT.md) for full documentation.
