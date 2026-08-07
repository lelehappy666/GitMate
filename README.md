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
- 可通过系统文件夹选择器原地添加已有 GitHub 仓库，不复制、移动或链接目录
- 导入时只读取仓库根目录、origin 和当前分支，重启后继续使用原始本地路径
- 默认只管理本地仓库，云端仓库通过独立分页按需浏览和下载
- 云端仓库每次加载 30 个，未进入窗口的仓库不会提前读取封面
- 云端仓库的语言筛选直接使用 GitHub 返回的主要语言
- 仓库封面只加载当前窗口与下一行，最多并发 3 路
- 已加载封面持久缓存在本地，刷新云端仓库时才按可见范围重新检查
- 大量仓库惰性渲染、头像缓存与后台同步
- 横向进度条、Git 实时进度和当前文件显示
- 支持主动停止同步并终止后台 Git 任务
- 单仓库失败、网络中断和授权失效恢复
- 全局工作台汇总仓库健康、本地改动、开放 Issue、PR 与 Actions 失败
- 仓库总览使用 README 首张有效图片生成海报封面，失败时稳定回退
- 仓库侧栏可浏览总览、README、文件与提交、双布局提交图
- 每次点击侧栏“提交图”都会从本地 Git 刷新，页面内也可手动刷新
- 刷新会校验提交、父边、本地与远程分支指向，并显示完整、警告或失败状态
- 提交图可在 GitKraken 式传统布局与无限画布之间切换，保留当前选中和画布视口
- 大仓库按可见区域查询提交与连线，并提供历史导航条、搜索聚焦和语义缩放
- README 使用原生组件安全渲染，不执行 HTML 或脚本
- 文件、提交、纯文本差异和双父合并关系均为只读浏览

## 工作区数据与边界

页面 10–15 采用本地优先策略：本地 Git 状态、文件树和提交历史直接来自同步
目录；GitHub 在线摘要与 README 失败时保留可用的本地或短期缓存内容。切换账户
会取消旧页面任务，但不会删除已同步仓库。

当前阶段不会执行编辑文件、暂存、提交、推送、合并、切换分支或删除仓库等写
操作。仓库总览的“最近同步时间”在没有可靠同步事件来源时保持为空，不使用文件
扫描时间或提交时间冒充。仓库封面使用独立的持久缓存；README 正文中的全部行内
图片离线缓存，以及行内链接的精确富文本位置仍是后续优化项。

提交图只读取本地与远程分支的 Git 关系，不会修改引用、提交或工作区。
传统布局按“最新提交在上”排列；画布布局按“最早提交在上”排列，
并保留 Group、折叠、版本区域、固定连线端口和视口。刷新会先展示本地缓存，
再读取完整 Git 快照并进行完整性对账；刷新失败时保留上一份正确场景。
五万提交规模下，传统布局仅生成可见行与预加载行，画布仅查询视口附近的节点和连线候选；
切换曲线与直角折线时不重算 Git 拓扑、分组或端口。

手动添加已有仓库时，GitMate 只执行只读 Git 查询并登记原始目录。仓库必须配置
`origin`，且远端主机必须与当前登录的 GitHub.com 或 GitHub Enterprise 账户一致。
登记记录按账户保存；重新添加同一远端仓库时更新为最近选择的目录。

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

支持的页码为 `1...15`。第 01–09 页沿用首次同步预览；第 10–15 页显示
2 个本地仓库与 1 个云端仓库、真实格式头像地址、README 封面与回退封面、
本地改动、PR、Actions 失败、文件树、提交列表和双父合并提交图。
`--preview-state` 支持
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

原地添加的本地仓库登记记录位于：

```text
~/Library/Application Support/GitMate/ImportedRepositories
```

登记文件只保存清洗后的远端地址和本地文件 URL，不保存访问令牌、URL 用户名、
密码、查询参数或片段。

当前已使用完整 Xcode 工具链验证 Swift Package 测试、原生 SwiftUI
可执行程序编译、页面 10–11 默认窗口布局和本地临时签名 `.app`。
钥匙串授权弹窗、完整 VoiceOver 流程与正式公证仍需在发布流程中继续验收。
