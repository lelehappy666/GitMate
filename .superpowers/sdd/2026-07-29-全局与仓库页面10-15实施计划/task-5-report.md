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

---

## 正式审查修复 Round 1

### 审查问题与根因

1. parser 与 extractor 分别使用按行解析和正则替换，无法可靠表达多行、未闭合 HTML 状态，也无法完整缓冲跨行标签。
2. extractor 每行固定先找 Markdown、再找 HTML，并且每类只取首个匹配，违反全局源码顺序，首候选被拒后也不会继续同一行后续图片。
3. URL 解析未区分显式 scheme 与相对 URL，`https:relative.png` 可进入候选；受阻主机比较未去除尾随点。
4. 缓存以两个固定文件分别原子写入，并由实例级锁保护；两个缓存实例交错保存时仍可能得到新数据配旧元数据。

### RED 覆盖

`Tests/GitMateCoreTests/READMEBlockParserTests.swift` 新增：

- `多行和未闭合 HTML 注释屏蔽内部 Markdown`
- `跨行危险容器及未闭合对象屏蔽到匹配结束或 EOF`
- `跨行普通标签被缓冲且跨行 img 只提取白名单属性`
- `围栏代码内未闭合 HTML 状态不影响围栏外解析`

`Tests/GitMateCoreTests/RepositoryCoverExtractorTests.swift` 新增：

- `封面忽略多行及未闭合 HTML 状态中的图片`
- `封面按全局源码顺序处理 HTML 与 Markdown 图片`
- `同一行首张图片被拒后继续选择后续有效候选`
- `多个 Markdown 图片严格按源码顺序筛选`
- `封面拒绝显式无主机 URL 与尾点受阻主机`
- `两个缓存实例并发保存不会混配数据与元数据`
- `缓存只读取 current 指向且 generation 匹配的完整文件对`

分阶段 RED：

```text
HTML 状态 RED：完成 124 个测试，失败 3 个。
range/URL RED：完成 128 个测试，失败 4 个。
generation 缓存 RED：完成 130 个测试，失败 3 个。
```

失败均对应审查指出的真实行为，不是测试编译或 fixture 错误。

### 修复实现

- 新增内部共享 `READMEHTMLSanitizer`：
  - 先隔离 fenced code，以稳定占位符保留原始语言和内容。
  - HTML 注释从 `<!--` 屏蔽到 `-->`，未闭合时持续到 EOF。
  - `script`、`iframe`、`object` 大小写不敏感，连同内部内容删除；未闭合时持续到 EOF。
  - 普通 HTML 标签按引号状态跨行缓冲；仅完整 `img` 转换为内部图片占位符，其他标签和事件属性只保留必要换行。
  - parser 与 extractor 共用同一 sanitizer，不再分别维护危险 HTML 正则。
- extractor 在清洗后的完整源文本上收集全部 Markdown 图片 range 与 HTML 图片占位符 range，合并排序后逐个筛选；同一行多个候选和内联封面候选都按源码顺序处理。
- `READMEURLPolicy` 统一要求 `http`/`https` 和非空 host；显式 scheme 不再按相对 URL 解析，host 比较前小写并移除所有尾随点。
- 缓存改为 generation pointer 协议：
  - 稳定目录为 `Covers/<repository-id>/<sha256>/`。
  - 每次保存以 UUID 写入 `<generation>.data` 和 `<generation>.json`。
  - JSON 内保存同一 generation，最后原子写入 `current` 作为唯一发布点。
  - load 只读取 `current` 对应文件对并校验 generation；缺文件、损坏或混配返回 `nil`。
  - 未发布 generation 保留但不可见；两个实例并发保存只能读取任一完整 pair。

### GREEN 与最终验证

各阶段完成后分别达到 124/124、128/128、130/130。最终完整 runner：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/gitmate-task5-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/gitmate-task5-clang-cache \
swift run --disable-sandbox GitMateCoreTestsRunner
```

结果：

```text
完成 130 个测试，失败 0 个。
退出码：0
```

完整编译：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/gitmate-task5-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/gitmate-task5-clang-cache \
swift build --disable-sandbox
```

结果：

```text
Build complete!
退出码：0
```

安全与差异检查：

- `git diff --check` 和新增 sanitizer 的 `git diff --no-index --check` 通过。
- README Core 未发现 SwiftUI、AppKit、WebKit、Network、URLSession、网络启动调用、`hashValue` 或认证敏感符号。
- 危险协议、危险容器、多行/未闭合 HTML、fenced code 隔离、尾点受阻主机、路径逃逸、未发布 generation、缺失 pair 和跨实例并发均有真实行为测试。

### Round 1 变更文件

- `Sources/GitMateCore/README/READMEHTMLSanitizer.swift`
- `Sources/GitMateCore/README/READMEBlockParser.swift`
- `Sources/GitMateCore/README/RepositoryCoverExtractor.swift`
- `Sources/GitMateCore/README/RepositoryCoverCache.swift`
- `Tests/GitMateCoreTests/READMEBlockParserTests.swift`
- `Tests/GitMateCoreTests/RepositoryCoverExtractorTests.swift`
- `.superpowers/sdd/2026-07-29-全局与仓库页面10-15实施计划/task-5-report.md`

### Round 1 Concerns

- 无 Critical 或 Important 遗留问题。
- 表格单元格链接、README parser 的内联图片块和剩余小型 regex 去重是正式审查已记账的 Minor，本轮按要求不扩大语法范围；封面 extractor 的内联图片候选已由全局 range scanner 自然覆盖。
- generation 保存允许保留旧文件对；这是本轮明确允许的缓存策略，后续如需空间回收，应只清理非 current generation。
