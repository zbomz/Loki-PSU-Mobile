# Testing Loki PSU App on iPhone (Windows Development)

Since you're developing on Windows but want to test on iPhone, here are your options:

## Option 1: GitHub Actions CI/CD (Recommended)

### Setup Steps:

1. **Create a GitHub repository** and push your code
2. **Configure Apple Developer Account:**
   - Create an Apple Developer account if you don't have one
   - Create an app ID for your app (com.example.loki-psu)
   - Create provisioning profiles for development and distribution

3. **Install IPA on iPhone:**
   - After pushing code, GitHub Actions will build the IPA
   - Download the IPA from the Actions artifacts
   - Use one of these services to install on your iPhone:
     - **Diawi**: Upload IPA and get install link (free for limited use)
     - **Appetize.io**: Test apps in browser or get install links
     - **TestFlight**: For production-ready builds

### Using the Workflows:

- **build_ios_simple.yml**: Builds debug and release IPAs that you can download and install
- **build_ios.yml**: Also deploys to TestFlight (requires more setup)

## Option 2: Codemagic CI/CD

1. Sign up at [codemagic.io](https://codemagic.io)
2. Connect your GitHub repository
3. Configure iOS build settings
4. Get install links for testing on your iPhone

## Option 3: Appcircle

1. Sign up at [appcircle.io](https://appcircle.io)
2. Similar to Codemagic - automated iOS builds
3. Direct install links for iPhone testing

## Option 4: Flutter Web (Limited Testing)

For basic UI testing (won't work with BLE features):

```bash
flutter run -d web-server
# Access from iPhone browser at the provided URL
```

## Installation Methods:

### Using Diawi (Requires Apple Developer Account):
1. Go to [diawi.com](https://www.diawi.com)
2. Upload your IPA file (must be properly signed)
3. Get QR code/install link
4. Open on your iPhone to install

**Note**: Diawi requires properly signed IPAs, so you'll need an Apple Developer account for this to work.

### Using Appetize.io:
1. Go to [appetize.io](https://appetize.io)
2. Upload IPA file
3. Test in browser or get install link

## Important Notes:

- **BLE Functionality**: Your app uses Bluetooth Low Energy, so web testing won't work for BLE features
- **Provisioning Profiles**: You'll need proper iOS development certificates and provisioning profiles
- **Device Registration**: Your iPhone must be registered in your Apple Developer account for development builds

## Quick Start (Simplest):

1. Push your code to GitHub
2. The `build_ios_simple.yml` workflow will automatically build IPAs
3. Download the IPA from GitHub Actions
4. Use Diawi to install on your iPhone
5. Test your BLE functionality!

## Troubleshooting:

- If builds fail, check the GitHub Actions logs
- Ensure your Apple Developer account is properly configured
- For BLE issues, make sure your iPhone has Bluetooth enabled and necessary permissions