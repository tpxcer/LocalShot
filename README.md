# LocalShot

LocalShot 是一款开源、纯本地的 macOS 截图与录屏工具，支持 Apple 芯片和 Intel Mac。

从 **0.4.0（Build 20）** 开始，所有功能安装后直接可用，无需机器码、授权码或激活。源码采用 **GNU GPL v3（GPL-3.0-only）**，允许使用、修改和再分发；分发修改版时须遵守 GPL v3 的源码公开和许可证要求。

[下载安装包](https://github.com/tpxcer/LocalShot-Downloads/releases/latest) · [安装说明与功能展示](https://github.com/tpxcer/LocalShot-Downloads) · [反馈问题](https://github.com/tpxcer/LocalShot/issues)

## 系统要求

- macOS 13 或更高版本；Apple 芯片（arm64）与 Intel（x86_64）使用同一个 Universal 2 安装包。
- 区域录屏和原位置翻译需要 macOS 15 或更高版本。
- 自行构建需要 Swift 6.1+ 和 macOS SDK；建议安装完整 Xcode。
- 当前安装包为 ad-hoc 签名公开测试版，尚未经过 Apple Developer ID 公证。

## 当前能力

- 菜单栏入口。
- 区域、窗口和主显示器全屏截图。
- macOS 14+ 的区域、窗口和全屏截图使用 ScreenCaptureKit；旧系统保留系统截图回退。
- 快捷区域截图覆盖层：系统标准尺寸彩虹箭头光标、扩大后的方形像素放大镜、窗口悬停吸附、自由拖选、选区移动、8 点缩放、尺寸标签、深色悬浮工具条和 3/6/9px 属性面板。
- 截图时可直接使用粗箭身与大实心三角头箭头、画笔、马赛克/模糊、椭圆、直角矩形、步骤编号和文字，并执行撤销、保存、取消、完成并复制、OCR、原位置翻译和置顶。
- 区域长截图：先框选单个窗口内的目标区域，再由你使用鼠标滚轮或触控板慢慢向下滚动；采集期间保留蓝色选区细边框，LocalShot 按固定窗口相对位置采集、识别固定顶部/底部并纵向去重拼接，右侧实时预览会自动跟随最新内容，完成后点击浮层中的“完成”。
- 区域屏幕录制（macOS 15+）：框选后持续显示红色边框和悬浮控制条，可选择系统声音与麦克风并录制本地 H.264 MP4；默认开启系统声音、关闭麦克风，视频与截图保存在同一个本地目录，停止后在 Finder 中定位视频。
- PNG/JPEG 输出、JPEG 质量、光标和窗口阴影设置。
- 自定义截图与录屏保存目录、文件名前缀、历史保留期限和悬浮层自动关闭时间。
- 屏幕捕获、麦克风权限状态与系统设置入口；只有主动开启录屏麦克风时才请求麦克风权限。
- 区域截图默认使用 `⌘⌃A`，识别文字使用 `⌘⇧O`；窗口和全屏使用 `⌃⌥2/3`。如果 `⌘⌃A` 已被其他应用占用，会自动回退到 `⌃⌥1`；所有快捷键都可重新录制或禁用，并支持内部冲突校验和失败回滚。
- 截图后的快速访问悬浮层。
- 复制、另存为、Finder 定位和删除。
- 最近保存列表同时显示截图和录屏；截图打开快速访问，录屏在 Finder 中定位。
- 完整历史缩略图窗口，可按文件名、日期、本地 OCR 文字和截图类型搜索筛选。
- 本地 OCR 历史索引支持缓存复用、图片变更后重新识别和已删除记录清理。
- 非破坏性标注编辑器：裁剪、箭头、直线/虚线、矩形、椭圆、画笔、高亮、文字、步骤编号、聚光灯、马赛克/保色模糊、安全遮挡、对象选择/移动/缩放/旋转、撤销、重做和 PNG 导出。
- 本地 OCR：截图工具栏点击“识别文字”后可在原截图内二次框选文字范围；也可用 `⌘⇧O` 直接框选屏幕文字。使用 Vision 识别文字和文字框，可选择文本并复制全部。
- OCR 与翻译结果可复制全部内容或单个文字块。
- 原位置系统翻译：macOS 15+ 使用 Apple Translation，支持译文覆盖预览、复制和翻译图片导出。
- 图片美化：背景、边距、圆角、阴影和自动/1:1/4:3/16:9/4:5 输出比例。
- 截图置顶：支持多个浮动窗口、透明度调节、点击穿透和从菜单栏恢复交互。
- 可导入单张本地图片用于标注、OCR、原位置翻译或图片美化；外部图片不会加入可删除的截图历史。
- 外部图片的标注项目保存在本机 Application Support，不会在原图片旁创建伴随文件。
- 可在设置中使用 macOS 官方登录项机制控制开机启动，并显示是否需要系统批准。
- 直接分发版默认每 24 小时查询一次公开 GitHub Release；可关闭自动检查，也可手动检查。发现新版后由用户确认下载，SHA-256 校验通过才会保存到“下载”并打开 DMG。
- 原创应用图标由项目内 Core Graphics 脚本生成，不依赖外部素材。

## 当前不包含

- GIF 和整屏视频录制。
- 云服务、账号或同步。
- 对大范围持续动画、视频、横向位移页面的稳定滚动截图支持。

## 隐私

截图、区域录屏、OCR、翻译、历史索引和标注都在本机处理。详细的数据保存位置、系统权限和删除规则见 [PRIVACY.md](PRIVACY.md)。

应用包同时包含 Apple 隐私清单 `PrivacyInfo.xcprivacy`，声明不跟踪、不收集数据，并按实际用途申报本地偏好和文件时间戳 API。

## 构建

克隆后可直接构建，无需配置签发私钥、账号或运行时服务：

```bash
git clone https://github.com/tpxcer/LocalShot.git
cd LocalShot
swift build -c release --product LocalShot
sh scripts/package-app.sh
open build/LocalShot.app
```

通用安装包及回归验证：

```bash
swift run LocalShotCoreCheck
swift run LocalShotEditingCheck
swift run LocalShotOCRCheck
swift run LocalShotTranslationCheck
swift run LocalShotBeautificationCheck
swift run LocalShotScrollingCheck
swift run LocalShotHistoryIndexCheck
swift run LocalShotHotKeyCheck
swift run LocalShotUpdaterCheck
# 可选联网验收：下载当前公开 DMG 到临时目录并校验后清理
swift run LocalShotUpdaterLiveCheck
swift build
swift scripts/generate-app-icon.swift
sh scripts/package-app.sh
sh scripts/verify-release.sh
sh scripts/package-dmg.sh
sh scripts/sign-notarize.sh
```

核心逻辑使用以上独立可执行程序自检；完整 UI 测试需在完整 Xcode 环境执行。

`scripts/package-app.sh` 默认打包 release 优化构建；需要本地调试包时可显式设置 `CONFIGURATION=debug`。`scripts/verify-release.sh` 会运行全部自检、生成 release 应用包并验证 Info.plist、图标、隐私清单、更新网络边界和签名状态。

打包脚本会生成 ad-hoc 签名。正式发布时可使用 `REQUIRE_SIGNATURE=1` 强制要求有效签名，或使用 `REQUIRE_DEVELOPER_ID=1` 强制要求 Developer ID Application 签名。

完成一次全量回归后，可以使用 `SKIP_BUILD=1 sh scripts/verify-release.sh` 只复核现有 release 二进制和应用包资源。

`scripts/package-dmg.sh` 会从已验证的 release 应用包生成只读压缩 DMG，卷内包含 `LocalShot.app` 和指向系统 `/Applications` 的拖放入口；随后以只读隐藏方式挂载并逐项核对二进制、图标、隐私清单和 Applications 链接。脚本不会自动覆盖同名镜像；只复核已有镜像时可使用 `REUSE_EXISTING=1 sh scripts/package-dmg.sh`。

`scripts/sign-notarize.sh` 用于最终 Developer ID 签名与 Apple 公证。它要求显式提供 `SIGN_IDENTITY` 和预先配置好的 `NOTARY_PROFILE`，不会创建或保存账号凭据；缺少任一项时会在签名和上传前立即退出。

## 发布边界

- 直接分发版只允许更新模块访问固定 GitHub Release 端点；截图、录屏、OCR、翻译和历史功能不上传本地内容。Mac App Store Target 不包含 GitHub 更新模块。
- 当前工程不包含运行时激活验证、机器码生成、授权签发工具或许可证服务器。
- 后续 Developer ID 签名和公证仍需维护者自己的 Apple Developer 证书。

真实桌面验收使用项目内 `TestFixtures`，完整操作项见 [UI_ACCEPTANCE.md](UI_ACCEPTANCE.md)，不会读取用户私人图片。

## 许可证

Copyright (C) 2026 tpxcer。源码和项目原创资源按 [GNU GPL v3](LICENSE) 发布，SPDX 标识为 `GPL-3.0-only`。软件按许可证约定不提供担保。

发布安装包的对应源码位于本仓库相同版本标签；修改并再分发时，请提供相应源码和许可证。macOS 系统框架由 Apple 提供，不包含在本仓库中。
