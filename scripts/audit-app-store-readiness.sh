#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENTITLEMENTS="$ROOT_DIR/Support/LocalShot-AppStore.entitlements"
METADATA="$ROOT_DIR/AppStore/metadata/zh-Hans"
STRICT=${STRICT:-0}

count_characters() {
    LC_ALL=en_US.UTF-8 wc -m < "$1" | tr -d ' '
}

count_bytes() {
    LC_ALL=C wc -c < "$1" | tr -d ' '
}

require_max_characters() {
    file=$1
    maximum=$2
    count=$(count_characters "$file")
    if [ "$count" -gt "$maximum" ]; then
        echo "App Store 检查失败：$file 为 $count 个字符，超过 $maximum。" >&2
        exit 1
    fi
}

plutil -lint "$ENTITLEMENTS" >/dev/null
ENTITLEMENT_CONTENT=$(plutil -p "$ENTITLEMENTS")
printf '%s' "$ENTITLEMENT_CONTENT" | grep -F '"com.apple.security.app-sandbox" => true' >/dev/null
printf '%s' "$ENTITLEMENT_CONTENT" | grep -F '"com.apple.security.files.bookmarks.app-scope" => true' >/dev/null
printf '%s' "$ENTITLEMENT_CONTENT" | grep -F '"com.apple.security.files.user-selected.read-write" => true' >/dev/null

for file in \
    name.txt \
    subtitle.txt \
    keywords.txt \
    promotional_text.txt \
    description.txt \
    whats_new.txt
do
    test -s "$METADATA/$file"
done

require_max_characters "$METADATA/name.txt" 30
require_max_characters "$METADATA/subtitle.txt" 30
require_max_characters "$METADATA/promotional_text.txt" 170
require_max_characters "$METADATA/description.txt" 4000
require_max_characters "$METADATA/whats_new.txt" 4000

KEYWORD_BYTES=$(count_bytes "$METADATA/keywords.txt")
if [ "$KEYWORD_BYTES" -gt 100 ]; then
    echo "App Store 检查失败：关键词为 $KEYWORD_BYTES 字节，超过 100。" >&2
    exit 1
fi

for file in \
    AppStore/review_notes.md \
    AppStore/privacy_answers.md \
    AppStore/age_rating.md \
    AppStore/accessibility.md \
    AppStore/screenshots/README.md \
    PRIVACY.md \
    Support/PrivacyInfo.xcprivacy
do
    test -s "$ROOT_DIR/$file"
done

grep -F '#if APP_STORE' "$ROOT_DIR/Sources/LocalShot/App/DistributionChannel.swift" >/dev/null
grep -F '#if !APP_STORE' "$ROOT_DIR/Sources/LocalShot/Update/UpdateController.swift" >/dev/null
grep -F 'capture.directoryBookmark' "$ROOT_DIR/Sources/LocalShot/Settings/AppSettings.swift" >/dev/null
grep -F '.withSecurityScope' "$ROOT_DIR/Sources/LocalShot/Settings/AppSettings.swift" >/dev/null
if grep -F 'product: LocalShotUpdater' "$ROOT_DIR/project.yml" >/dev/null; then
    echo "App Store 检查失败：商店 Target 不应依赖 GitHub 更新模块。" >&2
    exit 1
fi

if rg -n \
    --glob '!**/LocalShotUpdater/**' \
    --glob '!**/LocalShotUpdaterCheck/**' \
    '(^|[[:space:]])import[[:space:]]+Network([[:space:]]|$)|URLSession|NWConnection|NWPathMonitor|https?://' \
    "$ROOT_DIR/Package.swift" "$ROOT_DIR/Sources"; then
    echo "App Store 检查失败：商店源码范围发现网络实现或远程 URL。" >&2
    exit 1
fi

test -n "$(plutil -extract NSMicrophoneUsageDescription raw "$ROOT_DIR/Support/Info-AppStore.plist")"
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.audio-input' "$ROOT_DIR/Support/LocalShot-AppStore.entitlements")" = "true"
grep -F 'SCRecordingOutput' "$ROOT_DIR/Sources/LocalShot/Recording/ScreenRecordingService.swift" >/dev/null

if rg -n '(^|[[:space:]])import[[:space:]]+ReplayKit([[:space:]]|$)|RPScreenRecorder|AVCapture(Session|Input|Output)' \
    "$ROOT_DIR/Package.swift" "$ROOT_DIR/Sources"; then
    echo "App Store 检查失败：发现未批准的 ReplayKit 或摄像头采集实现。" >&2
    exit 1
fi

if [ "$STRICT" = "1" ]; then
    if ! xcodebuild -version >/dev/null 2>&1; then
        echo "App Store 严格检查失败：尚未安装或启用完整 Xcode。" >&2
        exit 1
    fi
    if ! find "$ROOT_DIR" -maxdepth 3 -name '*.xcodeproj' -print -quit | grep -q .; then
        echo "App Store 严格检查失败：尚未建立 Xcode App 工程。" >&2
        exit 1
    fi
    if ! grep -F 'Capture/SystemScreenshotAdapter.swift' "$ROOT_DIR/project.yml" >/dev/null; then
        echo "App Store 严格检查失败：Xcode 商店 Target 未排除外部截图适配器。" >&2
        exit 1
    fi
    if ! grep -F '#if !APP_STORE' "$ROOT_DIR/Sources/LocalShot/App/AppModel.swift" >/dev/null; then
        echo "App Store 严格检查失败：商店截图流程未编译隔离外部截图回退。" >&2
        exit 1
    fi
fi

echo "LocalShot App Store 源码与资料检查：PASS"
if [ "$STRICT" != "1" ]; then
    echo "提示：完整 Xcode、Xcode App 工程、签名、Bundle ID、公开 URL 和 Archive 由 STRICT=1 门禁继续验证。"
fi
