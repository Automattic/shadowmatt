#!/bin/bash

# Build the executable
swift build -c debug

# Create app bundle structure
APP_NAME="Shadowmatt"
APP_DIR=".build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy executable
cp ".build/debug/${APP_NAME}" "${MACOS_DIR}/"

# Copy resources if they exist
if [ -d ".build/debug/Shadowmatt_Shadowmatt.bundle" ]; then
    cp -R ".build/debug/Shadowmatt_Shadowmatt.bundle" "${RESOURCES_DIR}/"
fi

# Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Shadowmatt</string>
    <key>CFBundleIdentifier</key>
    <string>com.shadowmatt.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Shadowmatt</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Shadowmatt needs microphone access to record and transcribe audio.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Shadowmatt needs screen recording permission to capture system audio.</string>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo "App bundle created at: ${APP_DIR}"
echo "Run with: open ${APP_DIR}"
