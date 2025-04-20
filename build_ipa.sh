#!/bin/bash

# Exit on error
set -e

echo "📱 Building IPA for App Store submission..."

# Ensure clean build
echo "🧹 Cleaning previous builds..."
flutter clean

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get

# Build iOS archive
echo "🔨 Building iOS archive..."
flutter build ipa --release --export-options-plist=ios/exportOptions.plist

echo "✅ IPA build complete! The IPA file is located at:"
echo "build/ios/ipa/location_tracker.ipa"
echo ""
echo "You can now use Apple's Transporter app to upload the IPA to App Store Connect." 