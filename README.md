# Loki PSU Mobile App

A Flutter application for controlling the Loki PSU (APW3 V1 Power Supply Unit) via Bluetooth Low Energy (BLE).

## Features

- BLE interface for APW3 V1 power supply
- Real-time monitoring and control
- Cross-platform support (iOS, Android)

## Getting Started

### Prerequisites

- Flutter SDK 3.24.0 or higher
- For iOS: Xcode 15+ and valid Apple Developer account
- For Android: Android Studio with SDK 21+

### Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

## Version Management

This project uses **automatic version bumping** on every push to `main` or `develop` branches. The build number automatically increments, ensuring each build has a unique identifier.

For more details, see [VERSION_MANAGEMENT.md](VERSION_MANAGEMENT.md).

## Building for Release

### iOS (Signed)
The GitHub Actions workflow automatically builds signed iOS IPAs when you push to main or develop branches.

For manual builds or local development, see [APPLE_SETUP_README.md](APPLE_SETUP_README.md) and [INSTALLING_IPA.md](INSTALLING_IPA.md).

### Android
The GitHub Actions workflow automatically builds APK and App Bundle files when you push to main or develop branches.

## Documentation

- [Apple Setup & Code Signing](APPLE_SETUP_README.md)
- [Installing IPA Files](INSTALLING_IPA.md)
- [Version Management](VERSION_MANAGEMENT.md)
- [BLE Interface Specification](LOKI_BLE_INTERFACE_SPECIFICATION.md)
- [Testing Guide](TESTING_README.md)
- [Pre-Push Checklist](PRE_PUSH_CHECKLIST.md)

## Development

### Testing
```bash
flutter test
```

### Code Analysis
```bash
flutter analyze
```

## Project Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Flutter Samples](https://docs.flutter.dev/cookbook)
- [Flutter API Reference](https://api.flutter.dev/)

## License

See LICENSE file for details.

