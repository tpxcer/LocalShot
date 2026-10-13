# LocalShot 安装说明

## 系统要求

- Apple 芯片 Mac（arm64）或 Intel Mac（x86_64），同一个 Universal 2 安装包。
- macOS 13 或更高版本；区域录屏和原位置系统翻译需要 macOS 15。

## 下载与安装

1. 从 [LocalShot Releases](https://github.com/tpxcer/LocalShot/releases/latest) 下载 `LocalShot-0.4.1-build21-open-source-universal2-arm64-x86_64.dmg`。
2. 双击打开 DMG，将 `LocalShot.app` 拖入“应用程序”文件夹。
3. 在“应用程序”中打开 LocalShot。全部功能直接可用，无需机器码或授权码。

当前公开测试版使用 ad-hoc 签名，尚未经过 Apple Developer ID 公证。若 macOS 阻止打开，请在“系统设置 → 隐私与安全性”按系统提示选择“仍要打开”。请只从本仓库 Release 下载。

## 系统权限

第一次截图或录屏需要屏幕捕获权限，请按软件提示前往系统设置允许 LocalShot，然后重新打开软件。签名身份变化时，系统可能要求重新允许。

麦克风默认关闭，只有主动开启录屏麦克风时才请求权限。当前手动滚动长截图不需要辅助功能权限。

## 旧版本迁移

0.4.0（Build 20）及以前版本使用的旧下载仓库已经移除，不能再从旧软件内检查更新。请手动下载安装一次 Build 21 或更新版本；之后软件会从本开源仓库检查和下载后续更新。

升级前请备份重要截图，或在旧版设置中将“自动清理”改为“永久保留”。截图、录屏、历史和设置在应用包之外，但启动新版仍会执行原有保留策略，过期截图可能被永久删除。

Build 17 起新录屏与截图共用保存目录；旧版 `Application Support/LocalShot/Recordings` 内的视频不会自动移动或删除。Build 18 起“最近保存”同时显示截图和录屏，“清空记录”不勾选删除文件时只隐藏记录。

## 后续更新

- 默认每 24 小时最多检查一次公开 GitHub Release；可在设置中关闭或手动检查。
- 发现新版只提示，不会静默下载或替换应用。
- 用户确认后下载 DMG，核对大小和 GitHub SHA-256 digest；通过后才保存到“下载”并打开。
- 打开 DMG 后由用户将新版拖入“应用程序”覆盖旧版。

## 校验下载

将 DMG 和同一 Release 的校验文件放到同一目录，在终端运行：

```bash
shasum -a 256 -c SHA256SUMS-v0.4.1-build21-public.txt
```

看到 `OK` 表示文件与发布版本一致。对应源码在本仓库的同名版本标签中。
