# GitMate

GitMate 是一款原生 macOS GitHub 管理工具。当前已贯通第 01–15
页：登录、账户连接、权限确认、仓库首次同步，以及全局与单仓库只读工作区。

## 当前功能

- GitHub.com Personal Access Token 登录
- GitHub Enterprise Server 地址与 Personal Access Token 验证
- 重新启动后自动恢复已登录账户
- 访问令牌存入 macOS 钥匙串
- 读取真实用户头像与仓库列表
- 显示仓库可见性、默认分支和仓库大小
- 仓库默认全部不同步，可逐个选择手动同步或自动同步
- 使用系统 Git 执行 clone 与 fetch
- 大量仓库惰性渲染、头像缓存与后台同步
- 横向进度条、Git 实时进度和当前文件显示
- 支持主动停止同步并终止后台 Git 任务
- 单仓库失败、网络中断和授权失效恢复
- 全局工作台汇总仓库健康、本地改动、开放 Issue、PR 与 Actions 失败
- 仓库总览使用 README 首张有效图片生成海报封面，失败时稳定回退
- 仓库侧栏可浏览总览、README、文件与提交、节点式提交图
- README 使用原生组件安全渲染，不执行 HTML 或脚本
- 文件、提交、纯文本差异和双父合并关系均为只读浏览

## 工作区数据与边界

页面 10–15 采用本地优先策略：本地 Git 状态、文件树和提交历史直接来自同步
目录；GitHub 在线摘要与 README 失败时保留可用的本地或短期缓存内容。切换账户
会取消旧页面任务，但不会删除已同步仓库。

当前阶段不会执行编辑文件、暂存、提交、推送、合并、切换分支或删除仓库等写
操作。仓库总览的“最近同步时间”在没有可靠同步事件来源时保持为空，不使用文件
扫描时间或提交时间冒充。README 图片的完整离线缓存，以及行内链接的精确富文本
位置仍是后续优化项。

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
swift run GitMate --preview-page 10
swift run GitMate --preview-page 15
swift run GitMate --preview-page 10 --preview-state offline
swift run GitMate --preview-page 11 --preview-state error
```

支持的页码为 `1...15`。第 01–09 页沿用首次同步预览；第 10–15 页固定显示
3 个示例仓库、真实格式头像地址、README 封面与回退封面、本地改动、PR、
Actions 失败、文件树、提交列表和双父合并提交图。`--preview-state` 支持
`offline` 与 `error`，用于检查离线和面板错误状态；不传时为正常状态。

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

仓库默认下载到：

```text
~/Library/Application Support/GitMate/Repositories
```

同步页面会显示该目录，并可直接在 Finder 中打开。

工作区摘要缓存与仓库封面缓存分别位于：

```text
~/Library/Caches/GitMate/Workspace
~/Library/Caches/GitMate/RepositoryCovers
```

当前已使用完整 Xcode 工具链验证 Swift Package 测试和原生 SwiftUI
可执行程序编译。应用签名、钥匙串授权弹窗、VoiceOver、`.app` 归档与公证
仍需在正式发布流程中继续验收。
