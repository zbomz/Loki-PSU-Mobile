# PowerShell script to automatically bump version in pubspec.yaml
# This script increments the build number while keeping the version number the same
# Format: version: MAJOR.MINOR.PATCH+BUILD_NUMBER (e.g., 1.0.0+1)

$ErrorActionPreference = "Stop"

$PUBSPEC_FILE = "pubspec.yaml"

if (-not (Test-Path $PUBSPEC_FILE)) {
    Write-Error "Error: pubspec.yaml not found!"
    exit 1
}

# Read the file content
$content = Get-Content $PUBSPEC_FILE -Raw

# Extract current version line
$versionLineMatch = [regex]::Match($content, "version:\s*(\d+\.\d+\.\d+)\+(\d+)")

if (-not $versionLineMatch.Success) {
    Write-Error "Could not parse version from pubspec.yaml"
    exit 1
}

$versionNumber = $versionLineMatch.Groups[1].Value
$buildNumber = [int]$versionLineMatch.Groups[2].Value

Write-Host "Current version: $versionNumber"
Write-Host "Current build number: $buildNumber"

# Increment build number
$newBuildNumber = $buildNumber + 1
$newVersion = "$versionNumber+$newBuildNumber"

Write-Host "New version: $newVersion"

# Update pubspec.yaml
$currentVersion = "$versionNumber+$buildNumber"
$content = $content -replace "version:\s*$currentVersion", "version: $newVersion"
Set-Content -Path $PUBSPEC_FILE -Value $content -NoNewline

Write-Host "✅ Version bumped from $currentVersion to $newVersion"

# Output for GitHub Actions
if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "NEW_VERSION=$newVersion"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "BUILD_NUMBER=$newBuildNumber"
}

# Create a job summary for GitHub Actions UI
if ($env:GITHUB_STEP_SUMMARY) {
    $summary = @"
## 📦 Version Bump

| Property | Value |
|----------|-------|
| **Previous Version** | ``$currentVersion`` |
| **New Version** | ``$newVersion`` |
| **Build Number** | ``$newBuildNumber`` |

The version has been automatically incremented and will be committed to the repository.
"@
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $summary
}
