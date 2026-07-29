# Task 5：README 安全解析与仓库封面报告

## 状态

已完成。README 现在可在纯 Core 层解析为安全块模型、目录、外链和纯文本；仓库封面支持安全候选筛选、稳定回退模型与磁盘缓存。

## 实现内容

### README 安全解析

- 新增 `READMEBlock`、`READMEInlineContent`、`READMEOutlineItem`、`READMEExternalLink` 与 `READMEDocument`。
- 支持一级至六级标题、段落、围栏代码、Markdown/HTML 图片、表格、有序与无序列表、任务列表、引用和分隔线。
- 标题锚点清理标点并对重复标题追加稳定序号。
- 连续正文合并为段落，只暴露 `http` 与 `https` 外链。
- 相对图片基于 README URL 解析；缺少安全基址或使用危险协议时丢弃图片。
- `script`、`iframe`、`object` 连同内部文本完全移除。
- 围栏代码先隔离再解析，内部链接、图片和 HTML 不参与链接或封面提取。
- HTML 只识别 `img` 的 `src`、`alt`、`width`、`height`；单行或多行包装标签和事件属性不会进入文档模型。
- Core 层只依赖 Foundation 与 CryptoKit，不依赖 SwiftUI、AppKit、WebKit，也不执行 HTML 或发起网络请求。

### 仓库封面

- 按 README 源顺序选择第一张有效候选。
- 拒绝受阻主机、文件名含 `badge`/`status`/`icon`、声明尺寸小于 240 像素以及 SVG。
- 拒绝危险协议，并忽略危险 HTML 容器、HTML 注释和围栏代码中的伪图片。
- 无声明尺寸的普通 Markdown 截图可作为候选。
- `FallbackRepositoryCover` 只保存 SHA-256 seed、仓库首字母和语言颜色 token，可稳定编码解码，不依赖界面类型。

### 封面缓存

- `RepositoryCoverCaching` 公开 `Int64 repositoryID` 的 `load`、`save`、`clear` 接口。
- 默认路径为 `~/Library/Caches/GitMate/Covers/<repository-id>/<sha256>`。
- source URL 只作为 SHA-256 输入，不直接进入路径；禁止使用进程随机的 `hashValue`。
- 数据文件保存图像原始 `Data`，JSON 侧车只保存内容类型、保存时间和可选像素尺寸，不保存 source URL、Token 或凭据。
- 缓存读写和清理由实例锁串行保护，写入使用原子文件替换。

## TDD 证据

### 第一轮 RED/GREEN

先加入简报指定的脚本拒绝与封面筛选测试。首次真实 RED 为：

```text
cannot find 'READMEBlockParser' in scope
cannot find 'RepositoryCoverExtractor' in scope
```

完成最小实现后，完整 runner 为：

```text
完成 105 个测试，失败 0 个。
```

### 第二轮 RED/GREEN

逐步加入相对 URL、围栏代码隔离、重复标题、表格、任务列表、HTML img、受阻主机、小图、SVG、真实缓存读写、路径逃逸、清理和稳定回退测试。

主要 RED：

```text
完成 118 个测试，失败 11 个。
```

README 解析修复后收敛为 6 个封面与缓存失败；完成封面提取、SHA-256 缓存和回退模型后：

```text
完成 118 个测试，失败 0 个。
```

随后新增 HTML 包裹图片边界，先观察到 119 项中 1 项失败，再修复空 HTML 包装段落。额外自审继续加入同一行 HTML 包装与 HTML 注释伪封面边界，先观察到 2 项失败，再完成最小修复。稳定哈希测试还执行了反向变异：临时将 SHA-256 改为固定文件名时，该测试准确失败；恢复实现后重新全量验证。

## 最终验证

完整 runner：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/gitmate-task5-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/gitmate-task5-clang-cache \
swift run --disable-sandbox GitMateCoreTestsRunner
```

结果：

```text
完成 119 个测试，失败 0 个。
退出码：0
```

完整编译使用相同工具链和缓存变量执行：

```bash
swift build --disable-sandbox
```

结果：

```text
Build complete!
退出码：0
```

安全与差异检查：

- `git diff --check` 与全部新增文件的 `git diff --no-index --check` 均通过。
- Core README 目录未发现 SwiftUI、AppKit、WebKit、Network、URLSession、网络启动调用、`hashValue`、Authorization、Bearer 或 access token。
- Core README 目录未硬编码 `javascript:`、`data:`、`file:`、`ftp:` 等危险协议。
- 自动化测试真实验证危险协议、危险 HTML 容器、围栏代码隔离、缓存路径和元数据凭据边界。

## 变更文件

- `Sources/GitMateCore/README/READMEModels.swift`
- `Sources/GitMateCore/README/READMEBlockParser.swift`
- `Sources/GitMateCore/README/RepositoryCoverExtractor.swift`
- `Sources/GitMateCore/README/RepositoryCoverCache.swift`
- `Tests/GitMateCoreTests/READMEBlockParserTests.swift`
- `Tests/GitMateCoreTests/RepositoryCoverExtractorTests.swift`
- `Tests/GitMateCoreTests/TestMain.swift`
- `.superpowers/sdd/2026-07-29-全局与仓库页面10-15实施计划/task-5-report.md`

## Concerns

- 无功能或安全阻塞。
- 当前环境的 SwiftPM 用户缓存目录只读，因此 runner 与 build 会打印缓存禁用警告；使用项目既有的 Xcode 工具链、`--disable-sandbox` 和 `/private/tmp` 模块缓存后，测试与编译均成功。
- 封面筛选按简报要求不下载图片探测真实尺寸；未声明尺寸的普通 Markdown 图片依赖主机、文件名和扩展名规则筛选。
