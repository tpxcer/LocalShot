import CryptoKit
import Foundation
import LocalShotUpdater

private enum CheckError: Error {
    case failed(String)
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw CheckError.failed(message)
    }
}

do {
    let data = Data(
        """
        [
          {
            "tag_name": "v0.1.2-build5",
            "name": null,
            "draft": false,
            "assets": [{
              "name": "LocalShot-0.1.2-build5-offline-license-arm64.dmg",
              "size": 123456,
              "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              "browser_download_url": "https://github.com/tpxcer/LocalShot/releases/download/v0.1.2-build5/LocalShot-0.1.2-build5-offline-license-arm64.dmg"
            }]
          },
          {
            "tag_name": "v9.0.0-build99",
            "name": "draft",
            "draft": true,
            "assets": []
          },
          {
            "tag_name": "v0.1.1-build4",
            "name": "LocalShot 0.1.1 Build 4",
            "draft": false,
            "assets": [{
              "name": "LocalShot-0.1.1-build4-offline-license-arm64.dmg",
              "size": 120000,
              "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
              "browser_download_url": "https://github.com/tpxcer/LocalShot/releases/download/v0.1.1-build4/LocalShot-0.1.1-build4-offline-license-arm64.dmg"
            }]
          }
        ]
        """.utf8
    )
    let latest = try LocalShotUpdateCatalog.latestRelease(from: data, architecture: .arm64)
    try require(latest.version == LocalShotVersion(marketingVersion: "0.1.2", build: 5), "最新版本选择错误")
    try require(latest.name == "v0.1.2-build5", "空 Release 名称未回退到标签")
    try require(latest.asset.sha256 == String(repeating: "a", count: 64), "SHA-256 解析错误")
    try require(
        LocalShotUpdateCatalog.releasesAPIURL.absoluteString
            == "https://api.github.com/repos/tpxcer/LocalShot/releases?per_page=20",
        "更新源没有迁移到开源仓库"
    )
    let retiredRepositoryData = Data(
        String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "/tpxcer/LocalShot/", with: "/tpxcer/LocalShot-Downloads/")
            .utf8
    )
    do {
        _ = try LocalShotUpdateCatalog.latestRelease(from: retiredRepositoryData)
        throw CheckError.failed("旧仓库下载地址未被拒绝")
    } catch LocalShotUpdateError.noCompatibleRelease {
    }
    try require(
        LocalShotVersion(marketingVersion: "1.0", build: 1)!
            > LocalShotVersion(marketingVersion: "0.9.99", build: 99)!,
        "版本号比较错误"
    )
    try require(
        LocalShotVersion(tagName: "v0.1.2-build5")
            == LocalShotVersion(marketingVersion: "0.1.2", build: 5),
        "版本标签解析错误"
    )

    let universalData = Data(
        """
        [
          {
            "tag_name": "v0.3.2-build16",
            "name": "arm64 only",
            "draft": false,
            "assets": [{
              "name": "LocalShot-0.3.2-build16-offline-license-arm64.dmg",
              "size": 160000,
              "digest": "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
              "browser_download_url": "https://github.com/tpxcer/LocalShot/releases/download/v0.3.2-build16/LocalShot-0.3.2-build16-offline-license-arm64.dmg"
            }]
          },
          {
            "tag_name": "v0.3.1-build15",
            "name": "Universal 2",
            "draft": false,
            "assets": [
              {
                "name": "LocalShot-0.3.1-build15-offline-license-arm64.dmg",
                "size": 150000,
                "digest": "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
                "browser_download_url": "https://github.com/tpxcer/LocalShot/releases/download/v0.3.1-build15/LocalShot-0.3.1-build15-offline-license-arm64.dmg"
              },
              {
                "name": "LocalShot-0.3.1-build15-offline-license-universal2-arm64-x86_64.dmg",
                "size": 250000,
                "digest": "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                "browser_download_url": "https://github.com/tpxcer/LocalShot/releases/download/v0.3.1-build15/LocalShot-0.3.1-build15-offline-license-universal2-arm64-x86_64.dmg"
              }
            ]
          }
        ]
        """.utf8
    )
    let armLatest = try LocalShotUpdateCatalog.latestRelease(
        from: universalData,
        architecture: .arm64
    )
    try require(
        armLatest.version == LocalShotVersion(marketingVersion: "0.3.2", build: 16),
        "arm64 Mac 没有继续兼容历史 arm64 安装包"
    )
    let intelLatest = try LocalShotUpdateCatalog.latestRelease(
        from: universalData,
        architecture: .x86_64
    )
    try require(
        intelLatest.version == LocalShotVersion(marketingVersion: "0.3.1", build: 15),
        "Intel Mac 没有跳过 arm64-only Release"
    )
    try require(
        intelLatest.asset.name.contains("universal2"),
        "Intel Mac 没有选择 Universal 2 安装包"
    )

    let preferredUniversalData = Data(
        String(decoding: universalData, as: UTF8.self)
            .replacingOccurrences(of: "v0.3.2-build16", with: "invalid")
            .utf8
    )
    let preferredArmAsset = try LocalShotUpdateCatalog.latestRelease(
        from: preferredUniversalData,
        architecture: .arm64
    )
    try require(
        preferredArmAsset.asset.name.contains("universal2"),
        "同一 Release 内没有优先选择 Universal 2 安装包"
    )

    let invalidHostData = Data(
        """
        [{
          "tag_name": "v0.1.3-build6",
          "name": "invalid host",
          "draft": false,
          "assets": [{
            "name": "LocalShot-0.1.3-build6-arm64.dmg",
            "size": 1,
            "digest": "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
            "browser_download_url": "https://example.invalid/LocalShot.dmg"
          }]
        }]
        """.utf8
    )
    do {
        _ = try LocalShotUpdateCatalog.latestRelease(from: invalidHostData)
        throw CheckError.failed("非 GitHub 下载地址未被拒绝")
    } catch LocalShotUpdateError.noCompatibleRelease {
    }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalShotUpdaterCheck-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixtureURL = directory.appendingPathComponent("fixture.bin")
    let fixtureData = Data("LocalShot update check".utf8)
    try fixtureData.write(to: fixtureURL)
    let expectedDigest = SHA256.hash(data: fixtureData)
        .map { String(format: "%02x", $0) }
        .joined()
    let actualDigest = try LocalShotUpdateFile.sha256Hex(of: fixtureURL)
    try require(
        actualDigest == expectedDigest,
        "文件 SHA-256 计算错误"
    )
    let originalDMG = directory.appendingPathComponent("LocalShot.dmg")
    try Data().write(to: originalDMG)
    try require(
        LocalShotUpdateFile.uniqueDestinationURL(
            filename: "LocalShot.dmg",
            directory: directory
        ).lastPathComponent == "LocalShot (2).dmg",
        "同名下载文件不应被覆盖"
    )

    print("LocalShotUpdaterCheck: PASS")
} catch let CheckError.failed(message) {
    fputs("LocalShotUpdaterCheck: FAIL - \(message)\n", stderr)
    exit(1)
} catch {
    fputs("LocalShotUpdaterCheck: FAIL - \(error.localizedDescription)\n", stderr)
    exit(1)
}
