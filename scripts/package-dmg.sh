#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/build/LocalShot.app"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
DIST_DIR="$ROOT_DIR/dist"
MOUNT_POINT="$ROOT_DIR/build/LocalShotDMGMount"
APPLICATIONS_LINK="$ROOT_DIR/build/Applications"
REUSE_EXISTING=${REUSE_EXISTING:-0}
SKIP_APP_VERIFY=${SKIP_APP_VERIFY:-0}

cd "$ROOT_DIR"

if [ "$SKIP_APP_VERIFY" != "1" ]; then
    SKIP_BUILD=1 sh scripts/verify-release.sh >/dev/null
else
    test -x "$APP_DIR/Contents/MacOS/LocalShot"
    plutil -lint "$INFO_PLIST" >/dev/null
    plutil -lint "$APP_DIR/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null
fi

VERSION=$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")
ARCHITECTURES=${PACKAGE_ARCHITECTURES:-universal2}
DMG_PATH=${DMG_PATH:-"$DIST_DIR/LocalShot-$VERSION-$ARCHITECTURES.dmg"}

mkdir -p "$DIST_DIR"

if [ -L "$APPLICATIONS_LINK" ]; then
    if [ "$(readlink "$APPLICATIONS_LINK")" != "/Applications" ]; then
        echo "构建目录中的 Applications 链接目标不正确：$APPLICATIONS_LINK" >&2
        exit 1
    fi
elif [ -e "$APPLICATIONS_LINK" ]; then
    echo "构建目录中的 Applications 路径不是符号链接：$APPLICATIONS_LINK" >&2
    exit 1
else
    ln -s /Applications "$APPLICATIONS_LINK"
fi

UNEXPECTED_BUILD_ENTRIES=$(
    find "$ROOT_DIR/build" \
        -mindepth 1 \
        -maxdepth 1 \
        ! -name 'LocalShot.app' \
        ! -name 'Applications' \
        -print
)
if [ -n "$UNEXPECTED_BUILD_ENTRIES" ]; then
    echo "DMG 构建目录包含未批准的额外内容：" >&2
    printf '%s\n' "$UNEXPECTED_BUILD_ENTRIES" >&2
    exit 1
fi

if [ "$REUSE_EXISTING" = "1" ]; then
    test -f "$DMG_PATH"
else
    if [ -e "$DMG_PATH" ]; then
        echo "目标镜像已存在，不会自动覆盖：$DMG_PATH" >&2
        exit 1
    fi
    diskutil image create from \
        --format UDZO \
        --volumeName "LocalShot $VERSION" \
        "$ROOT_DIR/build" \
        "$DMG_PATH"
fi

diskutil image info "$DMG_PATH" | grep -F 'Image Format: UDZO' >/dev/null

if [ -e "$MOUNT_POINT" ]; then
    echo "验证挂载点已存在，请先确认没有残留镜像：$MOUNT_POINT" >&2
    exit 1
fi

diskutil image attach \
    --readOnly \
    --nobrowse \
    --mountPoint "$MOUNT_POINT" \
    "$DMG_PATH" >/dev/null

MOUNTED=1
cleanup() {
    if [ "$MOUNTED" = "1" ]; then
        diskutil eject "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
}
trap cleanup 0 1 2 3 15

MOUNTED_APP="$MOUNT_POINT/LocalShot.app"
test -d "$MOUNTED_APP"
test -x "$MOUNTED_APP/Contents/MacOS/LocalShot"
for architecture in arm64 x86_64
do
    lipo "$MOUNTED_APP/Contents/MacOS/LocalShot" -verify_arch "$architecture"
done
test -L "$MOUNT_POINT/Applications"
test "$(readlink "$MOUNT_POINT/Applications")" = "/Applications"
plutil -lint "$MOUNTED_APP/Contents/Info.plist" >/dev/null
plutil -lint "$MOUNTED_APP/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null
cmp "$ROOT_DIR/LICENSE" "$MOUNTED_APP/Contents/Resources/LICENSE"

SOURCE_BINARY_HASH=$(shasum -a 256 "$APP_DIR/Contents/MacOS/LocalShot" | awk '{print $1}')
MOUNTED_BINARY_HASH=$(shasum -a 256 "$MOUNTED_APP/Contents/MacOS/LocalShot" | awk '{print $1}')
SOURCE_INFO_HASH=$(shasum -a 256 "$APP_DIR/Contents/Info.plist" | awk '{print $1}')
MOUNTED_INFO_HASH=$(shasum -a 256 "$MOUNTED_APP/Contents/Info.plist" | awk '{print $1}')
SOURCE_ICON_HASH=$(shasum -a 256 "$APP_DIR/Contents/Resources/LocalShot.icns" | awk '{print $1}')
MOUNTED_ICON_HASH=$(shasum -a 256 "$MOUNTED_APP/Contents/Resources/LocalShot.icns" | awk '{print $1}')
SOURCE_PRIVACY_HASH=$(shasum -a 256 "$APP_DIR/Contents/Resources/PrivacyInfo.xcprivacy" | awk '{print $1}')
MOUNTED_PRIVACY_HASH=$(shasum -a 256 "$MOUNTED_APP/Contents/Resources/PrivacyInfo.xcprivacy" | awk '{print $1}')
SOURCE_STATEMENT_HASH=$(shasum -a 256 "$APP_DIR/Contents/Resources/PRIVACY.md" | awk '{print $1}')
MOUNTED_STATEMENT_HASH=$(shasum -a 256 "$MOUNTED_APP/Contents/Resources/PRIVACY.md" | awk '{print $1}')

test "$SOURCE_BINARY_HASH" = "$MOUNTED_BINARY_HASH"
test "$SOURCE_INFO_HASH" = "$MOUNTED_INFO_HASH"
test "$SOURCE_ICON_HASH" = "$MOUNTED_ICON_HASH"
test "$SOURCE_PRIVACY_HASH" = "$MOUNTED_PRIVACY_HASH"
test "$SOURCE_STATEMENT_HASH" = "$MOUNTED_STATEMENT_HASH"

diskutil eject "$MOUNT_POINT" >/dev/null
MOUNTED=0

echo "DMG 验证：PASS"
shasum -a 256 "$DMG_PATH"
echo "$DMG_PATH"
