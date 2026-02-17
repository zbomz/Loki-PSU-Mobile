# Apple Developer Setup for iOS Testing

To install your Flutter app on iPhone, you need proper code signing. Here's the complete setup process:

## 1. Apple Developer Account

**Cost**: $99/year (Individual) or $299/year (Organization)

1. Go to [developer.apple.com](https://developer.apple.com)
2. Click "Account" → Sign in with Apple ID
3. Enroll in Apple Developer Program
4. Verify your identity and payment

## 2. Create App ID

1. In Apple Developer Console → "Certificates, IDs & Profiles"
2. Click "Identifiers" → "+" button
3. Select "App IDs" → Continue
4. Choose "App" → Continue
5. Fill in:
   - **Bundle ID**: `com.zbomz.loki-psu`
   - **Description**: `Loki PSU Mobile App`
6. Enable services as needed (probably just default capabilities)
7. Click "Continue" → "Register"

## 3. Register Your iPhone

1. In Apple Developer Console → "Devices"
2. Click "+" button
3. Enter your iPhone's **UDID** (Unique Device Identifier)
4. Give it a name (e.g., "Test iPhone")

**How to get your iPhone UDID:**
- Connect iPhone to computer
- Open iTunes/Finder → Click on your iPhone
- Click the serial number until UDID appears
- Copy the long alphanumeric string

## 4. Create Development Certificate

1. In Apple Developer Console → "Certificates" → "+" button
2. Select "Apple Development" → Continue
3. Create or select CSR (Certificate Signing Request)
4. Download the `.cer` file

**To create CSR on Windows:**
```bash
# Use PowerShell or Command Prompt
# Generate private key and CSR
openssl req -new -newkey rsa:2048 -nodes -keyout private.key -out certificate.csr
```

## 5. Create Provisioning Profile

1. In Apple Developer Console → "Profiles" → "+" button
2. Select "iOS App Development" → Continue
3. Select your App ID → Continue
4. Select your Development Certificate → Continue
5. Select your registered iPhone → Continue
6. Give it a name (e.g., "Loki PSU Development Profile") → Generate
7. Download the `.mobileprovision` file

## 6. Convert Certificate to .p12 (for GitHub Actions)

```bash
# Convert .cer to .p12 using OpenSSL
openssl x509 -in development.cer -inform DER -out development.pem -outform PEM
openssl pkcs12 -export -inkey private.key -in development.pem -out certificate.p12
```

## 7. Add Secrets to GitHub

Go to your GitHub repository → Settings → Secrets and variables → Actions

Add these secrets:

1. **IOS_CERTIFICATE**: Base64 encode your `certificate.p12` file
   ```bash
   # On Windows PowerShell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("certificate.p12"))
   ```

2. **IOS_CERTIFICATE_PASSWORD**: The password you used when creating the .p12 file

3. **IOS_PROVISIONING_PROFILE**: Base64 encode your `.mobileprovision` file
   ```bash
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("build_pp.mobileprovision"))
   ```

## 8. Update iOS Bundle ID

Edit `ios/Runner.xcodeproj/project.pbxproj` or use Xcode to set the bundle identifier to match your App ID.

## Alternative: Free Testing Methods

If you don't want to pay for Apple Developer Program yet:

### Option 1: Appetize.io (Limited)
- Upload unsigned IPA
- Test in web browser (no BLE support)
- Get install links for registered devices

### Option 2: Local Development Server
- Run `flutter run -d web-server`
- Access from iPhone browser
- **Note**: BLE features won't work

## Next Steps After Setup

1. Push code changes to trigger new build
2. GitHub Actions will create properly signed IPA
3. Download from Actions artifacts
4. Install directly on your iPhone (no Diawi needed)

## Troubleshooting

- **"Untrusted Developer"**: Go to Settings → General → VPN & Device Management → Trust your developer account
- **Installation failed**: Check that your UDID is registered and provisioning profile includes your device
- **Code signing issues**: Verify certificate and profile are correctly encoded in GitHub secrets