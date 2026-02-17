# Automatic Version Bumping

This project is configured to automatically increment the build number every time code is pushed to the `main` or `develop` branches.

## How It Works

The version number in `pubspec.yaml` follows the format: `MAJOR.MINOR.PATCH+BUILD_NUMBER` (e.g., `1.0.0+42`)

When you push to GitHub:
1. The GitHub Actions workflow automatically increments the build number
2. The change is committed back to the repository with `[skip ci]` to prevent infinite loops
3. The builds use the new version number

## Version Scripts

Two scripts are available for version bumping:
- `.github/scripts/bump_version.sh` - For Linux/macOS (used in GitHub Actions)
- `.github/scripts/bump_version.ps1` - For Windows (local development)

## GitHub Actions Workflows

### iOS Build (Signed) - `build_ios_signed.yml`
- Triggers: Push to `main` or `develop` branches
- Auto-increments version before building
- Builds signed iOS IPA for distribution

### Android Build - `build_android.yml`
- Triggers: Push to `main` or `develop` branches
- Auto-increments version before building
- Builds both APK and App Bundle

### Other Workflows
The `build_ios.yml` and `build_ios_simple.yml` workflows do NOT auto-increment versions to avoid conflicts. Only the primary build workflows (`build_ios_signed.yml` and `build_android.yml`) increment versions.

## Manual Version Bumping

### On Windows
```powershell
.\.github\scripts\bump_version.ps1
```

### On Linux/macOS
```bash
chmod +x .github/scripts/bump_version.sh
./.github/scripts/bump_version.sh
```

## Changing the Version Number (Major.Minor.Patch)

To change the semantic version (e.g., from 1.0.0 to 1.1.0), manually edit `pubspec.yaml`:

```yaml
version: 1.1.0+1
```

The build number will continue to auto-increment from there.

## Important Notes

1. **[skip ci] Tag**: Version bump commits include `[skip ci]` to prevent triggering additional workflows
2. **GITHUB_TOKEN**: The workflow uses the automatic `GITHUB_TOKEN` which has permission to push changes
3. **Concurrent Builds**: If multiple workflows run simultaneously, they may try to increment and commit at the same time. The signed iOS workflow is the primary one that should increment versions.
4. **Pull Requests**: Version bumping only happens on direct pushes to `main` or `develop`, not on PRs

## Troubleshooting

### Version didn't increment
- Check the GitHub Actions log to see if the bump step succeeded
- Verify the workflow has permission to push (Settings > Actions > General > Workflow permissions)

### Merge conflicts
- If you're working on a branch while versions are being bumped on main, you may need to rebase or merge
- Consider pulling the latest changes before pushing

### Multiple version bumps
- If you push multiple commits at once, the version will only increment once per workflow run
- Each platform (iOS/Android) may increment independently if both workflows run
