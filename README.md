# GitMate

GitMate 是一款原生 macOS GitHub 管理工具。本阶段已实现第 01–09 页：登录、账户连接、权限确认、仓库首次同步设置、实时同步进度，以及错误、断网和授权失效恢复。

## 当前功能

- GitHub.com Personal Access Token 登录
- GitHub Enterprise Server 地址与 Personal Access Token 验证
- 重新启动后自动恢复已登录账户
- 访问令牌存入 macOS 钥匙串
- 读取真实用户头像与仓库列表
- 显示仓库可见性、默认分支和仓库大小
- 仓库默认全部不同步，可逐个选择手动同步或自动同步预留项
- 首次同步前由用户选择本机存储目录，选择结果会在重新启动后恢复
- 同步前检测同名文件、非 Git 文件夹和不同远程仓库，发生冲突时不会覆盖
- 使用系统 Git 执行 clone 与 fetch
- 大量仓库惰性渲染、头像缓存与后台同步
- 横向进度条、Git 实时进度和当前文件显示
- 支持主动停止同步并终止后台 Git 任务
- 单仓库失败、网络中断和授权失效恢复

## 运行要求

- macOS 14 或更高版本
- Swift 6
- 已创建 GitHub Personal Access Token

GitHub.com 与 GitHub Enterprise 均使用 Personal Access Token 登录。Classic Token
建议至少启用 `repo` 与 `read:user` 权限；如果需要管理 Actions，再增加
`workflow` 权限。细粒度令牌需要为目标仓库授予对应的读取或写入权限。

令牌验证成功后只保存在 macOS 钥匙串，不会写入项目文件或明文配置。

## 页面预览

开发时可直接打开任意引导页面，不会连接 GitHub、写入钥匙串或执行 Git：

```bash
swift run GitMate --preview-page 1
swift run GitMate --preview-page 6
swift run GitMate --preview-page 8
```

支持的页码为 `1...9`。

## 验证

运行轻量测试：

```bash
CLANG_MODULE_CACHE_PATH=.build/clang-module-cache \
SWIFT_MODULECACHE_PATH=.build/swift-module-cache \
swift run --disable-sandbox GitMateCoreTestsRunner
```

编译应用：

```bash
CLANG_MODULE_CACHE_PATH=.build/clang-module-cache \
SWIFT_MODULECACHE_PATH=.build/swift-module-cache \
swift build --disable-sandbox
```

仓库会下载到用户在首次同步页面选择的父文件夹中。同步页面会显示该目录，
并可直接在 Finder 中打开。

当前“自动”模式仅保存用户偏好并执行一次首次同步，与手动模式的首次行为相同。
定时检查、后台持续拉取、网络恢复后自动更新等真正的自动同步功能尚未开发。

当前开发机器只有 Apple Command Line Tools，没有完整 Xcode。因此已验证 Swift Package
测试、原生 SwiftUI 可执行程序编译和 `.app` 临时签名；钥匙串授权弹窗、VoiceOver
与发布公证仍需在完整 Xcode 环境继续验证。
