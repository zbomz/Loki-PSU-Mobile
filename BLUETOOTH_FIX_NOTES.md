# Bluetooth Scan Fix - iOS CBManagerStateUnknown Error

## Problem
When tapping the Scan button on iOS, the app was throwing a `PlatformException` with error:
```
PlatformException(startScan, bluetooth must be turned on. (CBManagerStateUnknown), null, null)
```

This occurred even when Bluetooth was turned on and permissions were granted, because the iOS Bluetooth manager (`CBManager`) was in an "unknown" state - meaning it hadn't finished initializing yet.

## Root Cause
The app was attempting to start a BLE scan before the iOS Bluetooth manager had time to initialize and determine its actual state. This is a common timing issue on iOS where `CBManager` goes through an initialization phase before reporting its actual state (powered on, powered off, unauthorized, etc.).

## Solution Implemented

### 1. Wait for Bluetooth Manager Initialization (`lib/ble/ble_service.dart`)
Updated the `startScan()` method to:
- Wait for the Bluetooth adapter state to move from `unknown` to a known state
- Use `firstWhere()` to wait for a non-unknown state (with a 3-second timeout)
- Only proceed with scanning when Bluetooth is confirmed to be in the `on` state
- Provide clear error messages for different states

### 2. Early Bluetooth Initialization (`lib/main.dart`)
- Added `FlutterBluePlus.setLogLevel()` call in `main()` to initialize the plugin early
- This gives the iOS Bluetooth manager time to initialize before the user interacts with the app

### 3. Real-time Bluetooth State Monitoring (`lib/screens/scan_screen.dart`)
- Changed `ScanScreen` from `StatelessWidget` to `StatefulWidget`
- Added listener for Bluetooth adapter state changes
- Display an orange warning banner when Bluetooth is not in the `on` state
- Shows different messages for different states (off, unauthorized, unknown, etc.)

### 4. Improved Error Handling
- Added `clearError()` method to `BleProvider` to allow dismissing error messages
- Made error banner dismissable
- Added user-friendly error message formatting that translates technical errors into actionable instructions

## Files Modified
1. `lib/ble/ble_service.dart` - Core BLE scanning logic with state checking
2. `lib/main.dart` - Early Bluetooth initialization
3. `lib/screens/scan_screen.dart` - UI improvements and state monitoring
4. `lib/providers/ble_provider.dart` - Added error clearing capability

## Testing Instructions
1. Rebuild the app and install on your iPhone
2. Launch the app with Bluetooth ON and permissions granted
3. Tap the Scan button - it should now:
   - Wait for Bluetooth to be ready
   - Start scanning successfully
   - Show clear messages if there are any issues

## Expected Behavior
- **If Bluetooth is on**: Scan starts immediately
- **If Bluetooth is initializing**: App waits up to 3 seconds for initialization
- **If Bluetooth is off**: Clear error message telling user to turn it on
- **If permissions denied**: Clear error message about permissions

## Additional Notes
- The 3-second timeout for Bluetooth initialization should be sufficient for iOS
- If users still see the "unknown" state error, they can wait a moment and try again
- The orange banner at the top proactively shows Bluetooth state before scanning
