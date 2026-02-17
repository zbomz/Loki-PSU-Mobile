# CI Checklist for Loki PSU Mobile

This checklist covers local validation, pushing, and **post-push CI monitoring**.
Follow every section in order. Do not stop until all CI workflows pass.

---

## Phase 1 — Local Validation

Run these checks locally **before pushing**:

```powershell
cd C:\Users\zbomsta\Desktop\PivotalPleb\Loki-PSU-Mobile
flutter analyze
flutter test
```

Both must pass with **zero errors** before proceeding.

---

## Phase 2 — Push

```powershell
git add -A
git commit -m "<message>"
git push origin main
```

If the push is rejected (e.g. remote has new commits from a CI version bump),
pull and retry:

```powershell
git pull --rebase origin main
git push origin main
```

---

## Phase 3 — CI Monitoring (Automated)

After pushing, **poll GitHub Actions every 30 seconds** until all workflows
reach a terminal state (success or failure). Use the `gh` CLI:

```powershell
gh run list --limit 5
```

### If any workflow fails:

1. Fetch the failed run's logs:
   ```powershell
   gh run view <RUN_ID> --log-failed
   ```
2. Diagnose the root cause from the log output.
3. Fix the issue locally.
4. **Return to Phase 1** and repeat the full cycle.

### Terminal states:

| Status | Action |
|---|---|
| All workflows `completed` + `success` | Done — checklist complete. |
| Any workflow `completed` + `failure` | Diagnose, fix, re-push (back to Phase 1). |
| Any workflow `in_progress` | Wait 30 seconds and poll again. |

**Do not stop or ask the user for help** unless the failure requires
information you cannot determine from the logs (e.g. missing secrets that
need to be added in the GitHub UI).

---

## Reference

### Workflow Summary

| File | Runner | Version Bump? | Purpose |
|---|---|---|---|
| `build_android.yml` | `ubuntu-latest` | Yes | Build APK + AAB, bump version |
| `build_ios_signed.yml` | `macos-latest` | No (reads version) | Build signed IPA |
| `build_ios_simple.yml` | `macos-latest` | No | Build unsigned debug + release IPAs |
| `build_ios.yml` | `macos-latest` | No | Legacy build + TestFlight (needs secrets) |
| `version_bump.yml` | `ubuntu-latest` | Yes | Reusable workflow (called by others) |

> **Only `build_android.yml` pushes a version bump commit.** The iOS workflows
> read the current version from `pubspec.yaml` without modifying it. This
> avoids race conditions when multiple workflows run concurrently.

### Flutter / Dart Constraints

- **Flutter**: `3.24.0` (stable) — do NOT use 3.27+ APIs
- **Dart SDK**: `^3.5.0` — do NOT use Dart 3.6+ features
- Incompatible APIs: `Color.withValues()`, `FlutterSceneDelegate`,
  `FlutterImplicitEngineDelegate`, `FlutterImplicitEngineBridge`

### iOS Code Signing

Handled by `build_ios_signed.yml` via GitHub Secrets:

| Secret | Contents |
|---|---|
| `IOS_CERT` | Base64-encoded `.p12` certificate |
| `IOS_CERT_PASSWORD` | Password for the `.p12` file |
| `IOS_PROVISIONING_PROFILE` | Base64-encoded `.mobileprovision` file |

Apple Developer details: Team `Z8LDNNQZ5T`, Bundle `com.zbomz.loki-psu`.

### Sensitive Files (Never Commit)

`*.key`, `*.p12`, `*.pem`, `*.cer`, `*.csr`, `*.mobileprovision`,
`certificate_p12_base64.txt`, `mobileprovision_base64.txt`

### Common CI Failure Patterns

| Log message | Cause | Fix |
|---|---|---|
| `Write access to repository not granted` | Missing `permissions: contents: write` | Add to workflow YAML |
| `non-fast-forward` on `git push` | Race between workflows bumping version | Only one workflow should bump |
| `mkdir: Payload: File exists` | Payload dir from prior build step | Use `rm -rf Payload && mkdir Payload` |
| `sed: extra characters at the end of p command` | BSD sed (macOS) vs GNU sed (Linux) | Use `sed -i.bak` + `rm *.bak` |
| `undefined_method` in analyze | Using API not in Flutter 3.24 | Check Flutter 3.24 API docs |
| Secrets show blank in CI logs | Secret name mismatch or not configured | `gh secret list` |
