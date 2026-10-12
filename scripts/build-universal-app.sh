#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURATION=${CONFIGURATION:-release}
ARM64_SCRATCH=${ARM64_SCRATCH:-"$ROOT_DIR/.build-arm64"}
X86_64_SCRATCH=${X86_64_SCRATCH:-"$ROOT_DIR/.build-x86_64"}
UNIVERSAL_DIR=${UNIVERSAL_DIR:-"$ROOT_DIR/.build-universal"}
UNIVERSAL_BINARY="$UNIVERSAL_DIR/LocalShot"
PACKAGE_APP=${PACKAGE_APP:-1}

case "$CONFIGURATION" in
    debug|release)
        ;;
    *)
        echo "不支持的构建配置：$CONFIGURATION（仅支持 debug 或 release）" >&2
        exit 1
        ;;
esac

cd "$ROOT_DIR"

swift build \
    -c "$CONFIGURATION" \
    --arch arm64 \
    --product LocalShot \
    --scratch-path "$ARM64_SCRATCH"
ARM64_BIN_DIR=$(swift build \
    -c "$CONFIGURATION" \
    --arch arm64 \
    --product LocalShot \
    --scratch-path "$ARM64_SCRATCH" \
    --show-bin-path)

swift build \
    -c "$CONFIGURATION" \
    --arch x86_64 \
    --product LocalShot \
    --scratch-path "$X86_64_SCRATCH"
X86_64_BIN_DIR=$(swift build \
    -c "$CONFIGURATION" \
    --arch x86_64 \
    --product LocalShot \
    --scratch-path "$X86_64_SCRATCH" \
    --show-bin-path)

ARM64_BINARY="$ARM64_BIN_DIR/LocalShot"
X86_64_BINARY="$X86_64_BIN_DIR/LocalShot"
test -x "$ARM64_BINARY"
test -x "$X86_64_BINARY"

mkdir -p "$UNIVERSAL_DIR"
lipo -create \
    "$ARM64_BINARY" \
    "$X86_64_BINARY" \
    -output "$UNIVERSAL_BINARY"
chmod 755 "$UNIVERSAL_BINARY"
for architecture in arm64 x86_64
do
    lipo "$UNIVERSAL_BINARY" -verify_arch "$architecture"
done

if [ "$PACKAGE_APP" = "1" ]; then
    BINARY_PATH="$UNIVERSAL_BINARY" \
    REQUIRED_ARCHITECTURES="arm64 x86_64" \
    CONFIGURATION="$CONFIGURATION" \
    sh scripts/package-app.sh >/dev/null
fi

echo "Universal 2 构建：PASS"
file "$UNIVERSAL_BINARY"
echo "$UNIVERSAL_BINARY"
