# Pre-Push Checklist for Loki PSU Mobile

Run these checks locally on Windows **before pushing to GitHub** to avoid CI failures.

## Quick Commands

```powershell
cd C:\Users\zbomsta\Desktop\PivotalPleb\Loki-PSU-Mobile
flutter analyze
flutter test
```

Both must pass with zero errors before pushing.

## Version Management

**Important**: The app version and build number are **automatically incremented** when you push to `main` or `develop` branches. You don't need to manually update the version in `pubspec.yaml` for regular commits.

- The build number (e.g., `1.0.0+42` → `1.0.0+43`) increments automatically
- The version bump is committed back with `[skip ci]` to avoid infinite loops
- See [VERSION_MANAGEMENT.md](VERSION_MANAGEMENT.md) for full details

### When to Manually Update Version

Only update the semantic version (MAJOR.MINOR.PATCH) in `pubspec.yaml` when releasing:
- **Major** version: Breaking changes
- **Minor** version: New features (backward compatible)
- **Patch** version: Bug fixes

The build number will continue auto-incrementing from your new version base.

## What Each Check Catches

| Check | Catches | Example Failures |
|---|---|---|
| `flutter analyze` | Type errors, undefined methods, missing imports, lint issues | `withValues` not defined on `MaterialColor` (use `withOpacity` instead) |
| `flutter test` | Broken widget tests, logic regressions | Widget render failures |

## CI Environment Details

The GitHub Actions workflows run on **macOS** with these specs:

- **Flutter version**: `3.24.0` (stable channel)
- **Xcode**: Latest available on `macos-latest` runner
- **Dart SDK**: `3.5.x` (bundled with Flutter 3.24)

### ⚠️ Critical Compatibility Notes

1. **Flutter 3.24 API only** — Do NOT use APIs introduced in Flutter 3.27+. Known incompatible APIs:
   - `FlutterImplicitEngineDelegate` (3.27+)
   - `FlutterImplicitEngineBridge` (3.27+)
   - `FlutterSceneDelegate` (3.27+)
   - `Color.withValues()` (3.27+) — use `Color.withOpacity()` instead

2. **iOS Swift files** must use standard Flutter 3.24 patterns:
   - `AppDelegate.swift`: Extend `FlutterAppDelegate` only, register plugins with `GeneratedPluginRegistrant.register(with: self)`
   - `SceneDelegate.swift`: Extend `UIResponder, UIWindowSceneDelegate` (not `FlutterSceneDelegate`)

3. **Dart SDK constraint** in `pubspec.yaml` is `^3.5.0` — do not use Dart 3.6+ features.

## iOS Code Signing (CI Only)

iOS signing is handled in CI via the `build_ios_signed.yml` workflow. It cannot be tested locally on Windows.

### How It Works

1. Certificate and provisioning profile are stored as **GitHub repository secrets**
2. The workflow installs them into a temporary macOS keychain
3. Flutter builds an **unsigned** app (`--no-codesign`)
4. The app is then **manually signed** using `codesign` with the installed certificate
5. Signed IPA is uploaded as a GitHub Actions artifact

### GitHub Secret Names

| Secret | Contents |
|---|---|
| `IOS_CERT` | Base64-encoded `.p12` certificate |
| `IOS_CERT_PASSWORD` | Password for the `.p12` file |
| `IOS_PROVISIONING_PROFILE` | Base64-encoded `.mobileprovision` file |

### Apple Developer Details

- **Team ID**: `Z8LDNNQZ5T`
- **Bundle ID**: `com.zbomz.loki-psu`
- **Signing Identity**: `Apple Development: Zack Bomsta (LUJ7J2N4J7)`

### If Signing Breaks

1. Verify secrets exist: `gh secret list` (requires GitHub CLI authenticated)
2. Ensure the provisioning profile hasn't expired (check Apple Developer Console)
3. The workflow uses `codesign` directly — it does NOT rely on Xcode's automatic or manual signing for the final app. The `project.pbxproj` has `CODE_SIGN_STYLE = Automatic` and `DEVELOPMENT_TEAM` set, but these are only used by the `--no-codesign` build step (which ignores them).

## Workflow Files

| File | Purpose |
|---|---|
| `.github/workflows/build_ios_signed.yml` | **Primary** — Builds signed IPA with code signing |
| `.github/workflows/build_ios_simple.yml` | Builds unsigned debug/release IPAs |
| `.github/workflows/build_ios.yml` | Legacy build + TestFlight deploy (not fully configured) |

## Sensitive Files (Never Commit)

These are excluded via `.gitignore`:

```
*.key, *.p12, *.pem, *.cer, *.csr, *.mobileprovision
certificate_p12_base64.txt, mobileprovision_base64.txt
```

If any of these appear in `git status` as untracked, do NOT stage them.

## OpenSSL on Windows

OpenSSL is not installed system-wide. Use the copy bundled with Git:

```powershell
& "C:\Program Files\Git\mingw64\bin\openssl.exe" <command>
```

## Troubleshooting Past CI Failures

| Symptom | Cause | Fix |
|---|---|---|
| `undefined_method` in analyze | Using API not in Flutter 3.24 | Check Flutter 3.24 API docs |
| Secret shows blank in CI logs | Secret name mismatch | Run `gh secret list` and compare with workflow `${{ secrets.NAME }}` |
| `No profiles for team` | Xcode can't find provisioning profile | Workflow uses `--no-codesign` + manual `codesign` to avoid this |
| `No Development Team` | Missing `DEVELOPMENT_TEAM` in pbxproj | Already set to `Z8LDNNQZ5T` in all build configs |
| `cannot find type FlutterSceneDelegate` | Swift files use 3.27+ APIs | Revert to standard Flutter 3.24 Swift patterns |
