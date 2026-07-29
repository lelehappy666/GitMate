# GitMate

GitMate 是一款原生 macOS GitHub 管理工具。当前已实现第 01–09 页登录与首次同步流程，以及第 16–23 页分支、标签、规则和议题工作区。

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
- 单仓库失败、网络中断和授权失效恢复
- 首次同步完成后自动进入仓库工作区
- 同时查看本地和远端分支、跟踪关系、领先落后与工作区状态
- 创建、签出、合并、推送和安全删除分支
- 合并本地与远端 Git 标签，支持创建、推送、获取和删除，并进入对应 GitHub Release
- 读取和无损管理 GitHub Ruleset，组织继承规则保持只读，弱化保护前二次确认
- 筛选、搜索、分页浏览和保存议题视图
- 查看议题 Markdown、时间线、评论、负责人、标签和里程碑
- 创建和编辑议题与评论，关闭、重新打开和锁定议题
- 新建议题 Markdown 编写与预览、模板、标签、里程碑和本地草稿
- 可拖动、可缩放和自动聚焦的节点式里程碑无限画布
- 议题标签使用分析、创建、编辑、安全删除和可恢复合并

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
swift run GitMate --preview-page 16
swift run GitMate --preview-page 19
swift run GitMate --preview-page 22
swift run GitMate --preview-page 23
```

支持的页码为 `1...9` 和 `16...23`。第 16–23 页预览使用隔离演示数据，不会连接 GitHub、修改本地仓库或写入钥匙串。

## 仓库工作区页面

| 页码 | 页面 | 主要能力 |
| --- | --- | --- |
| 16 | 分支 | 本地与远端引用、同步状态、创建、签出、推送、删除 |
| 17 | 标签 | 轻量与附注标签、远端状态、Release |
| 18 | 分支规则 | GitHub Ruleset、仓库规则编辑、组织继承只读 |
| 19 | 议题总览 | 搜索、筛选、保存视图、分页 |
| 20 | 议题详情 | Markdown、时间线、评论、状态与锁定 |
| 21 | 新建议题 | 模板、预览、标签、里程碑、本地草稿 |
| 22 | 里程碑 | 无限画布、节点关系、缩放、点击弹出详情 |
| 23 | 议题标签 | 标签库、使用分析、编辑、删除、安全合并 |

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

当前开发机器只有 Apple Command Line Tools，没有完整 Xcode。因此已验证 Swift Package 测试和原生 SwiftUI 可执行程序编译；应用签名、钥匙串授权弹窗、VoiceOver、`.app` 归档与公证需要安装完整 Xcode 后继续验证。
