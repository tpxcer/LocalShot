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

在 [LocalShot-Downloads Releases](https://github.com/tpxcer/LocalShot-Downloads/releases) 下载当前安装包。对应版本源码可从本源码仓库相同版本标签下载。

## 用户数据

GitHub 保存代码和发布文件；截图、录屏、设置与历史索引保存在使用者本机。需要在电脑丢失后恢复这些本地数据时，应另行使用 Time Machine 等方式备份。

## 维护者归档

此前私有开发历史保留在 `tpxcer/LocalShot-Private-Archive`，仅仓库所有者可访问。公开仓库从经过清理的源码快照开始维护。
