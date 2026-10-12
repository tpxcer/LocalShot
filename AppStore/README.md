# LocalShot Mac App Store 提交资料

此目录保存 Mac App Store 首次提交所需的本地草稿，不包含 Apple 账号、证书、密码、验证码、税务或银行信息。

## 已准备

- 简体中文产品页文案、关键词和首次版本说明。
- App Review 审核说明与无演示账号说明。
- “不收集数据、不追踪”的隐私问卷草稿。
- 年龄分级和无障碍信息草稿。
- App Sandbox entitlements：`Support/LocalShot-AppStore.entitlements`，包含用户所选文件读写和应用范围安全书签。
- XcodeGen 工程规格：`project.yml`；完整 Xcode 安装后生成并校验 `.xcodeproj`。
- 商店截图规格与画面清单。

## 仍需用户确认

- 最终应用名称是否为 `LocalShot`。
- Apple Developer Team、唯一 Bundle ID 和 SKU。
- V1 是否免费、发布国家或地区。
- 公开支持网址、隐私政策网址和维护者联系邮箱。
- 最低系统是否采用建议的 macOS 14；工程已配置 Apple Silicon 与 Intel 双架构。

## 外部门禁

- 安装并启用完整 Xcode 26。
- 用户本人登录 Apple Developer 与 App Store Connect，并完成双重认证。
- Apple Developer Program 会员有效，最新协议已接受。
- Xcode 自动管理 Apple Distribution 签名和 provisioning profile。
- 创建 App Store Connect 应用记录后，再把最终 Bundle ID、SKU 和 URL 写入提交配置。

## 提交前验证

1. 商店 Target 使用 `APP_STORE` 编译条件和 macOS 14 最低版本。
2. Archive 包含 App Sandbox 和用户所选文件读写权限，不包含临时例外。
3. 商店构建不执行 `/usr/sbin/screencapture`，所有截图使用 ScreenCaptureKit。
4. 真实沙盒签名下复测区域、窗口、全屏、长截图、OCR、翻译、导入、另存为和自定义截图目录重启恢复。
5. 上传包内没有 `com.apple.quarantine`。
6. 上传 TestFlight，使用从 TestFlight 安装的版本完成最终验收。
