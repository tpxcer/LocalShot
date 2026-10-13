# LocalShot 源码恢复

LocalShot 从 0.4.0（Build 20）开始公开源码并取消激活验证。

## 新电脑恢复开发

安装 Xcode 或提供 Swift 6.1+ 与 macOS SDK 的开发工具，然后运行：

```bash
git clone https://github.com/tpxcer/LocalShot.git
cd LocalShot
git fetch --tags
swift build -c release --product LocalShot
sh scripts/package-app.sh
```

无需恢复授权签发私钥。旧版授权系统不参与当前软件的构建或运行。

## 恢复安装包

在 [LocalShot Releases](https://github.com/tpxcer/LocalShot/releases) 下载当前安装包。对应版本源码可从本仓库相同版本标签下载，安装方法见 [INSTALL.md](INSTALL.md)。

0.4.0（Build 20）及以前版本使用旧更新源，需手动下载安装一次 0.4.1（Build 21）或更新版本。之后会从本仓库检查和下载更新。

## 用户数据

GitHub 保存代码和发布文件；截图、录屏、设置与历史索引保存在使用者本机。需要在电脑丢失后恢复这些本地数据时，应另行使用 Time Machine 等方式备份。

## 历史备份边界

GitHub 只保留本开源仓库。旧下载仓库和旧私有源码归档已由维护者备份到本机后移除；旧开发历史不在公开仓库中，不能仅依靠 GitHub 恢复。当前完整源码和安装包继续在本仓库维护。
