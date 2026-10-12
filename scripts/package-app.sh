#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/build/LocalShot.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
CONFIGURATION=${CONFIGURATION:-release}
BINARY=${BINARY_PATH:-"$ROOT_DIR/.build/$CONFIGURATION/LocalShot"}
REQUIRED_ARCHITECTURES=${REQUIRED_ARCHITECTURES:-}
ICON="$ROOT_DIR/Support/LocalShot.icns"
PRIVACY_MANIFEST="$ROOT_DIR/Support/PrivacyInfo.xcprivacy"
PRIVACY_STATEMENT="$ROOT_DIR/PRIVACY.md"
LICENSE_FILE="$ROOT_DIR/LICENSE"

case "$CONFIGURATION" in
    debug|release)
        ;;
    *)
        echo "不支持的构建配置：$CONFIGURATION（仅支持 debug 或 release）" >&2
        exit 1
        ;;
esac

if [ ! -x "$BINARY" ]; then
    echo "缺少可执行文件：$BINARY" >&2
    echo "请先运行 swift build -c $CONFIGURATION --product LocalShot" >&2
    exit 1
fi

if [ ! -f "$ICON" ]; then
    echo "缺少应用图标：$ICON" >&2
    echo "请先运行 swift scripts/generate-app-icon.swift" >&2
    exit 1
fi

if [ ! -f "$PRIVACY_MANIFEST" ]; then
    echo "缺少隐私清单：$PRIVACY_MANIFEST" >&2
    exit 1
fi

if [ ! -f "$PRIVACY_STATEMENT" ]; then
    echo "缺少隐私说明：$PRIVACY_STATEMENT" >&2
    exit 1
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
test -f "$LICENSE_FILE"
cp "$BINARY" "$MACOS_DIR/LocalShot"
chmod 755 "$MACOS_DIR/LocalShot"
for architecture in $REQUIRED_ARCHITECTURES
do
    lipo "$MACOS_DIR/LocalShot" -verify_arch "$architecture"
done
cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ICON" "$RESOURCES_DIR/LocalShot.icns"
cp "$PRIVACY_MANIFEST" "$RESOURCES_DIR/PrivacyInfo.xcprivacy"
cp "$PRIVACY_STATEMENT" "$RESOURCES_DIR/PRIVACY.md"
cp "$LICENSE_FILE" "$RESOURCES_DIR/LICENSE"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
