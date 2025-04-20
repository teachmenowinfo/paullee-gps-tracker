# App Store Build & Submission Guide

## Prerequisites

1. Apple Developer account
2. Xcode installed
3. Flutter SDK installed
4. App Store Connect account set up
5. App registered in App Store Connect
6. App signing certificates and provisioning profiles

## Build Steps

### 1. Update App Information

Make sure your app has the correct version and build number:

```bash
# Open pubspec.yaml and set the version
# Example: version: 1.0.0+1
```

### 2. Configure iOS App

1. Make sure the Bundle ID in Xcode matches your App Store Connect app
2. Update app icons in `ios/Runner/Assets.xcassets`
3. Update the app name in `Info.plist`

### 3. Generate IPA File

Run the provided build script:

```bash
./build_ipa.sh
```

This will:
- Clean the project
- Get all dependencies
- Build release IPA file with App Store settings

The IPA will be generated at:
```
build/ios/ipa/location_tracker.ipa
```

### 4. Upload to App Store

#### Option 1: Using Transporter App

1. Download and install [Transporter](https://apps.apple.com/us/app/transporter/id1450874784) from the Mac App Store
2. Open Transporter
3. Sign in with your Apple ID
4. Click the "+" button to add your IPA file
5. Select your IPA file from the build directory
6. Click "Upload" to begin the upload process

#### Option 2: Using Application Loader in Xcode

1. Open Xcode
2. Go to Xcode → Open Developer Tool → Application Loader
3. Sign in with your Apple ID
4. Choose "Deliver Your App" and select the IPA file
5. Follow the on-screen instructions

### 5. Complete App Store Submission

After uploading:

1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. Select your app
3. Set up all required metadata:
   - Screenshots
   - App description
   - Keywords
   - Support URL
   - Privacy Policy URL
4. Submit for review

## Troubleshooting

### Common Issues

1. **Signing Issues**:
   - Ensure your certificates and provisioning profiles are valid
   - Check that the team ID in `exportOptions.plist` matches your Apple Developer account

2. **Missing Icons**:
   - Make sure all required app icons are included

3. **Invalid Binary**:
   - Check App Store validation errors in App Store Connect
   - Fix any reported issues in your code or configuration

4. **Metadata Rejected**:
   - Follow Apple's guidelines for screenshots and descriptions

### Getting Help

- [Flutter Documentation](https://flutter.dev/docs/deployment/ios)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [Apple Developer Forums](https://developer.apple.com/forums/) 