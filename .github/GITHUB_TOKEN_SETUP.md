# GitHub Token Setup for Automated Build Monitoring

This guide helps you set up a GitHub Personal Access Token so AI agents can automatically check GitHub Actions build status.

## One-Time Setup

### 1. Create a GitHub Personal Access Token

1. Go to https://github.com/settings/tokens
2. Click "Generate new token" → "Generate new token (classic)"
3. Give it a name: `Loki PSU Build Monitoring`
4. Set expiration: 90 days (or "No expiration" if you prefer)
5. Select scopes:
   - ✅ `repo` (Full control of private repositories)
   - ✅ `workflow` (Update GitHub Action workflows)
6. Click "Generate token"
7. **COPY THE TOKEN** (you won't see it again!)

### 2. Set as Persistent Environment Variable (Windows)

**Option A: System Environment Variable (Recommended)**
```powershell
# Run PowerShell as Administrator
[System.Environment]::SetEnvironmentVariable('GITHUB_TOKEN', 'YOUR_TOKEN_HERE', [System.EnvironmentVariableTarget]::User)
```

**Option B: Manual Setup**
1. Press `Win + X` → System → Advanced system settings
2. Click "Environment Variables"
3. Under "User variables", click "New"
4. Variable name: `GITHUB_TOKEN`
5. Variable value: paste your token
6. Click OK

### 3. Verify Setup

Close and reopen PowerShell/Terminal, then run:
```powershell
echo $env:GITHUB_TOKEN
```

Should display your token (or part of it).

### 4. Test API Access

```powershell
$headers = @{
    "Authorization" = "Bearer $env:GITHUB_TOKEN"
    "Accept" = "application/vnd.github+json"
}
$response = Invoke-RestMethod -Uri "https://api.github.com/repos/zbomz/Loki-PSU-Mobile/actions/runs?per_page=1" -Headers $headers
$response.workflow_runs[0] | Select-Object name, status, conclusion
```

## Security Notes

- Never commit the token to git
- The token is already in `.gitignore` patterns
- Treat it like a password
- Regenerate if compromised

## For AI Agents

Once setup is complete, agents can check build status with:
```powershell
$headers = @{
    "Authorization" = "Bearer $env:GITHUB_TOKEN"
    "Accept" = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}
$response = Invoke-RestMethod -Uri "https://api.github.com/repos/zbomz/Loki-PSU-Mobile/actions/runs?per_page=1" -Headers $headers
$run = $response.workflow_runs[0]
Write-Output "Status: $($run.status) | Conclusion: $($run.conclusion) | $($run.html_url)"
```
