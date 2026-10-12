#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/build/LocalShot.app"
CONTENTS_DIR="$APP_DIR/Contents"
BINARY="$CONTENTS_DIR/MacOS/LocalShot"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
REQUIRE_SIGNATURE=${REQUIRE_SIGNATURE:-0}
REQUIRE_DEVELOPER_ID=${REQUIRE_DEVELOPER_ID:-0}
SKIP_BUILD=${SKIP_BUILD:-0}
SKIP_PACKAGE=${SKIP_PACKAGE:-0}
UNIVERSAL_BINARY=${UNIVERSAL_BINARY:-"$ROOT_DIR/.build-universal/LocalShot"}

cd "$ROOT_DIR"

if [ "$SKIP_BUILD" != "1" ]; then
    for product in \
        LocalShotCoreCheck \
        LocalShotEditingCheck \
        LocalShotOCRCheck \
        LocalShotTranslationCheck \
        LocalShotBeautificationCheck \
        LocalShotScrollingCheck \
        LocalShotHistoryIndexCheck \
        LocalShotHotKeyCheck \
        LocalShotUpdaterCheck
    do
        swift run "$product"
    done

    PACKAGE_APP=0 CONFIGURATION=release sh scripts/build-universal-app.sh
fi

test -x "$UNIVERSAL_BINARY"
for architecture in arm64 x86_64
do
    lipo "$UNIVERSAL_BINARY" -verify_arch "$architecture"
done
if [ "$SKIP_PACKAGE" != "1" ]; then
    BINARY_PATH="$UNIVERSAL_BINARY" \
    REQUIRED_ARCHITECTURES="arm64 x86_64" \
    CONFIGURATION=release \
    sh scripts/package-app.sh >/dev/null
fi

plutil -lint "$CONTENTS_DIR/Info.plist"
plutil -lint "$RESOURCES_DIR/PrivacyInfo.xcprivacy"

test "$(plutil -extract CFBundleIdentifier raw "$CONTENTS_DIR/Info.plist")" = "com.localshot.prototype"
test "$(plutil -extract CFBundleIconFile raw "$CONTENTS_DIR/Info.plist")" = "LocalShot.icns"
test "$(plutil -extract LSUIElement raw "$CONTENTS_DIR/Info.plist")" = "true"
test -n "$(plutil -extract NSScreenCaptureUsageDescription raw "$CONTENTS_DIR/Info.plist")"
test -n "$(plutil -extract NSMicrophoneUsageDescription raw "$CONTENTS_DIR/Info.plist")"
test "$(plutil -extract NSPrivacyTracking raw "$RESOURCES_DIR/PrivacyInfo.xcprivacy")" = "false"

test -x "$BINARY"
for architecture in arm64 x86_64
do
    lipo "$BINARY" -verify_arch "$architecture"
done
test -f "$RESOURCES_DIR/LocalShot.icns"
test -f "$RESOURCES_DIR/PRIVACY.md"
test -f "$RESOURCES_DIR/LICENSE"
cmp Support/Info.plist "$CONTENTS_DIR/Info.plist"
cmp Support/LocalShot.icns "$RESOURCES_DIR/LocalShot.icns"
cmp Support/PrivacyInfo.xcprivacy "$RESOURCES_DIR/PrivacyInfo.xcprivacy"
cmp PRIVACY.md "$RESOURCES_DIR/PRIVACY.md"
cmp LICENSE "$RESOURCES_DIR/LICENSE"

for architecture in arm64 x86_64
do
    otool -arch "$architecture" -l "$BINARY" \
        | grep -A4 'LC_BUILD_VERSION' \
        | grep -F 'minos 13.0' >/dev/null
    NON_SYSTEM_LIBRARIES=$(
        otool -arch "$architecture" -L "$BINARY" \
            | tail -n +2 \
            | awk '{print $1}' \
            | grep -Ev '^(/System/Library/|/usr/lib/)' \
            || true
    )
    if [ -n "$NON_SYSTEM_LIBRARIES" ]; then
        echo "发布检查失败：$architecture 发现未打包的非系统动态依赖：" >&2
        printf '%s\n' "$NON_SYSTEM_LIBRARIES" >&2
        exit 1
    fi
done

PRIVACY_CONTENT=$(plutil -p "$RESOURCES_DIR/PrivacyInfo.xcprivacy")
for value in \
    NSPrivacyAccessedAPICategoryFileTimestamp \
    NSPrivacyAccessedAPICategoryUserDefaults \
    DDA9.1 \
    C617.1 \
    3B52.1 \
    CA92.1
do
    printf '%s' "$PRIVACY_CONTENT" | grep -F "$value" >/dev/null
done

SCROLLING_FIXTURE="$ROOT_DIR/TestFixtures/scrolling-test.html"
test -f "$SCROLLING_FIXTURE"
for section in 01 02 03 04 05 06 07 08 09 10
do
    grep -F "LOCALSHOT-SECTION-$section" "$SCROLLING_FIXTURE" >/dev/null
done
grep -F 'position: sticky' "$SCROLLING_FIXTURE" >/dev/null
grep -F 'animation: move' "$SCROLLING_FIXTURE" >/dev/null
grep -F 'LOCALSHOT-SCROLL-END' "$SCROLLING_FIXTURE" >/dev/null
grep -F 'case "capture-scrolling":' Sources/LocalShot/App/AppModel.swift >/dev/null
if rg -n 'https?://|src="[^"]+"|href="[^"]+"' "$SCROLLING_FIXTURE"; then
    echo "发布检查失败：滚动截图验收页包含外部资源或链接。" >&2
    exit 1
fi

FREEZE_RESULT_SOURCE="Sources/LocalShot/Selection/QQCaptureOverlayController.swift"
FREEZE_SERVICE_SOURCE="Sources/LocalShot/Capture/ScreenCaptureKit/ScreenCaptureKitService.swift"
grep -F 'let frozenSelectionImage: CGImage' "$FREEZE_RESULT_SOURCE" >/dev/null
grep -F 'Set(previews.keys) == Set(scalesByDisplayID.keys)' "$FREEZE_SERVICE_SOURCE" >/dev/null
grep -F 'result.frozenSelectionImage' Sources/LocalShot/App/AppModel.swift >/dev/null
if grep -F 'if let frozenSelectionImage = result.frozenSelectionImage' \
    Sources/LocalShot/App/AppModel.swift >/dev/null; then
    echo "发布检查失败：区域截图仍允许缺少冻结帧并回退到实时捕获。" >&2
    exit 1
fi

UPDATER_SOURCE="Sources/LocalShotUpdater/LocalShotUpdateService.swift"
EXPECTED_UPDATE_URL="https://api.github.com/repos/tpxcer/LocalShot-Downloads/releases?per_page=20"
test -f "$UPDATER_SOURCE"
test "$(rg -o 'https?://[^"]+' "$UPDATER_SOURCE")" = "$EXPECTED_UPDATE_URL"
grep -F 'URLSessionConfiguration.ephemeral' "$UPDATER_SOURCE" >/dev/null
grep -F 'digest == release.asset.sha256' "$UPDATER_SOURCE" >/dev/null
strings "$BINARY" | grep -F "$EXPECTED_UPDATE_URL" >/dev/null

if strings "$BINARY" | rg -n 'license\.authorizationCode|LocalShot 尚未授权|复制机器码|输入授权码|激活全部功能'; then
    echo "发布检查失败：主应用二进制仍包含旧授权验证内容。" >&2
    exit 1
fi

if rg -n 'licenseManager|requireLicense|LocalShotLicenseManager|LocalShotLicensing' \
    Sources/LocalShot/App Sources/LocalShot/Views Package.swift; then
    echo "发布检查失败：主应用仍依赖旧授权验证代码。" >&2
    exit 1
fi

if rg -n \
    --glob '!**/LocalShotUpdater/**' \
    --glob '!**/LocalShotUpdaterCheck/**' \
    '(^|[[:space:]])import[[:space:]]+Network([[:space:]]|$)|URLSession|NWConnection|NWPathMonitor|https?://' \
    Package.swift Sources; then
    echo "发布检查失败：发现更新模块之外的网络实现或远程 URL。" >&2
    exit 1
fi

test -f Sources/LocalShot/Recording/ScreenRecordingService.swift
test -f Sources/LocalShot/Recording/MicrophonePermission.swift
test -f Sources/LocalShotCore/ScreenRecordingFileStore.swift
grep -F 'SCRecordingOutput' Sources/LocalShot/Recording/ScreenRecordingService.swift >/dev/null
grep -F 'ScreenRecordingFileStore' Sources/LocalShot/App/AppModel.swift >/dev/null
grep -F 'recentRecordings(limit:' Sources/LocalShotCore/ScreenRecordingFileStore.swift >/dev/null
grep -F 'removeAllRecordings()' Sources/LocalShotCore/ScreenRecordingFileStore.swift >/dev/null
grep -F 'Section("功能")' Sources/LocalShot/Views/MenuContentView.swift >/dev/null
grep -F 'ForEach(menuCaptureModes' Sources/LocalShot/Views/MenuContentView.swift >/dev/null
grep -F '[.area, .window, .fullScreen]' Sources/LocalShot/Views/MenuContentView.swift >/dev/null
grep -F 'Label("识别文字"' Sources/LocalShot/Views/MenuContentView.swift >/dev/null
grep -F 'Section("最近保存")' Sources/LocalShot/Views/MenuContentView.swift >/dev/null
grep -F 'model.recentSaveItems.prefix(5)' Sources/LocalShot/Views/MenuContentView.swift >/dev/null
grep -F 'Button("区域录屏"' Sources/LocalShot/Views/MenuContentView.swift >/dev/null
grep -F 'Button("打开目录"' Sources/LocalShot/Views/MenuContentView.swift >/dev/null
grep -F 'Button("清空记录…"' Sources/LocalShot/Views/MenuContentView.swift >/dev/null
grep -F 'alert.messageText = "清空保存记录？"' Sources/LocalShot/App/AppModel.swift >/dev/null
grep -F 'checkboxWithTitle: "同时删除截图和录屏文件"' Sources/LocalShot/App/AppModel.swift >/dev/null
test "$(grep -Fc 'recordingsDirectory: fileStore.capturesDirectory' Sources/LocalShot/App/AppModel.swift)" -eq 5

if rg -n 'Section\("录制"\)|Section\("最近截图"\)|打开(截图|录制)目录|清空截图记录|CaptureMode\.allCases|Label\("识别屏幕文字"' \
    Sources/LocalShot/Views/MenuContentView.swift; then
    echo "发布检查失败：菜单仍存在旧分组或旧操作文案。" >&2
    exit 1
fi

if rg -n 'openScreenRecordingDirectory|appendingPathComponent\("Recordings"' Sources/LocalShot; then
    echo "发布检查失败：录屏仍存在独立目录入口或默认存储目录。" >&2
    exit 1
fi

if rg -n '(^|[[:space:]])import[[:space:]]+ReplayKit([[:space:]]|$)|RPScreenRecorder|AVCapture(Session|Input|Output)' Package.swift Sources; then
    echo "发布检查失败：发现未批准的 ReplayKit 或摄像头采集实现。" >&2
    exit 1
fi

if codesign --verify --deep --strict "$APP_DIR" >/dev/null 2>&1; then
    SIGNATURE_DETAILS=$(codesign -d --verbose=4 "$APP_DIR" 2>&1)
    if printf '%s' "$SIGNATURE_DETAILS" | grep -F 'Signature=adhoc' >/dev/null; then
        if [ "$REQUIRE_DEVELOPER_ID" = "1" ]; then
            echo "发布检查失败：应用只有 ad-hoc 签名，不是 Developer ID Application 签名。" >&2
            exit 1
        fi
        echo "代码签名检查：ad-hoc 签名"
    elif [ "$REQUIRE_DEVELOPER_ID" = "1" ] && \
         ! printf '%s' "$SIGNATURE_DETAILS" | grep -F 'Authority=Developer ID Application:' >/dev/null; then
        echo "发布检查失败：应用签名不是 Developer ID Application。" >&2
        exit 1
    else
        echo "代码签名检查：通过"
    fi
elif [ "$REQUIRE_SIGNATURE" = "1" ]; then
    echo "发布检查失败：应用包尚未通过代码签名验证。" >&2
    exit 1
else
    echo "代码签名检查：当前开发环境未签名（正式发布时设置 REQUIRE_SIGNATURE=1）" >&2
fi

echo "LocalShot 发布前自动检查：PASS"
