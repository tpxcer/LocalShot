#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/build/LocalShot.app"
SIGN_IDENTITY=${SIGN_IDENTITY:-}
NOTARY_PROFILE=${NOTARY_PROFILE:-}

if [ -z "$SIGN_IDENTITY" ]; then
    echo "缺少 SIGN_IDENTITY，例如：Developer ID Application: 姓名 (TEAMID)" >&2
    exit 1
fi

if [ -z "$NOTARY_PROFILE" ]; then
    echo "缺少 NOTARY_PROFILE；请先由应用所有者在钥匙串中配置 notarytool 凭据。" >&2
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -F "$SIGN_IDENTITY" >/dev/null; then
    echo "钥匙串中没有找到指定代码签名 identity：$SIGN_IDENTITY" >&2
    exit 1
fi

xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null

cd "$ROOT_DIR"

sh scripts/verify-release.sh

codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP_DIR"

SKIP_BUILD=1 \
SKIP_PACKAGE=1 \
REQUIRE_SIGNATURE=1 \
REQUIRE_DEVELOPER_ID=1 \
sh scripts/verify-release.sh

VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP_DIR/Contents/Info.plist")
ARCHITECTURE=${PACKAGE_ARCHITECTURES:-universal2}
SIGNED_DMG="$ROOT_DIR/dist/LocalShot-$VERSION-$ARCHITECTURE-notarized.dmg"

if [ -e "$SIGNED_DMG" ]; then
    echo "目标公证镜像已存在，不会自动覆盖：$SIGNED_DMG" >&2
    exit 1
fi

SKIP_APP_VERIFY=1 \
DMG_PATH="$SIGNED_DMG" \
sh scripts/package-dmg.sh

codesign \
    --force \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$SIGNED_DMG"

codesign --verify --verbose=2 "$SIGNED_DMG"
xcrun notarytool submit "$SIGNED_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$SIGNED_DMG"
xcrun stapler validate "$SIGNED_DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$SIGNED_DMG"

echo "LocalShot Developer ID 签名与公证：PASS"
shasum -a 256 "$SIGNED_DMG"
echo "$SIGNED_DMG"
