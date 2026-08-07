# GitMate

GitMate 是一款原生 macOS GitHub 与本地 Git 管理工具。当前已实现第 01–09 页
登录与首次同步，以及第 30–37 页本地 Git 工作台。

## 当前功能

- GitHub.com Personal Access Token 登录
- GitHub Enterprise Server 地址与 Personal Access Token 验证
- 重新启动后自动恢复已登录账户
- 访问令牌存入 macOS 钥匙串
- 读取真实用户头像与仓库列表
- 显示仓库可见性、默认分支和仓库大小
- 仓库默认全部未选择，可通过复选框选择要 Clone 的仓库
- 首次下载前由用户选择本机存储目录，选择结果会在重新启动后恢复
- 下载前检测同名文件、非 Git 文件夹和不同远程仓库，发生冲突时不会覆盖
- 使用系统 Git 执行首次 Clone，不会自动 Fetch、Pull 或 Push
- 大量仓库惰性渲染、头像缓存与后台下载
- 仓库数量与当前仓库双进度条、Git 实时状态显示
- 支持立即暂停、继续和停止下载
- 支持手动刷新 GitHub 云端仓库列表并保留有效选择
- 单仓库失败、网络中断和授权失效恢复
- 最多五万条工作区变更的分批读取、筛选和惰性渲染
- 文件与代码块暂存、取消暂存、差异查看和提交
- Stash 创建、预览、Apply、Pop 与删除
- Merge、Rebase、Cherry-pick 预检、继续和中止
- 文本三方冲突编辑与二进制整文件选择
- HTTPS、SSH 与 SCP 风格远程仓库管理
- Fetch、Pull、普通 Push 与精确 `force-with-lease`

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

支持的引导页码为 `1...9`，本地 Git 页码为 `30...37`。本地 Git 预览使用
确定性内存数据，不会执行 Git 写操作：

```bash
swift run GitMate --preview-page 30
swift run GitMate --preview-page 35
swift run GitMate --preview-page 37
```

要打开用户明确指定的真实本地仓库：

```bash
swift run GitMate --local-repository /绝对路径/到/仓库
```

真实仓库入口只接受仓库根目录的绝对路径；危险操作仍需在页面中确认。

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

仓库会下载到用户在首次下载页面选择的父文件夹中。下载页面会显示该目录，
并可直接在 Finder 中打开。

自动同步与定时检查仍未启用。Fetch、Pull 和 Push 仅在用户从本地 Git 工作台
明确触发后执行。

当前开发机器只有 Apple Command Line Tools，没有完整 Xcode。因此已验证 Swift Package
测试、原生 SwiftUI 可执行程序编译和 `.app` 临时签名；钥匙串授权弹窗、VoiceOver
与发布公证仍需在完整 Xcode 环境继续验证。
