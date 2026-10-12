enum DistributionChannel {
    #if APP_STORE
    static let updateMethod = "Mac App Store"
    static let updateDescription = "应用更新由 Mac App Store 提供；LocalShot 自身不会在后台联网检查更新。"
    #else
    static let updateMethod = "GitHub Release（自动提醒）"
    static let updateDescription = "默认每 24 小时检查一次公开版本信息；只在你确认后下载并打开新版 DMG。"
    #endif
}
