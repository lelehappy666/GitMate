# Task 4：GitHub 工作区摘要 API 与本地在线融合报告

## 状态

已完成。GitHub 在线摘要、README 解码、本地 Git 合并、离线缓存、授权与限流状态、面板级错误和工作台聚合均已实现。

## 实现内容

### GitHub 工作区 API

- 新增 `GitHubWorkspaceAPI`、`GitHubREADME` 和稳定的 `WorkspaceAPIError`。
- 仓库摘要分别请求仓库元数据、开放议题、开放拉取请求和失败 Actions；议题与拉取请求使用独立 Search 查询。
- Actions 固定使用 `status=failure&per_page=1`。
- 所有请求使用 `Bearer` 认证头、GitHub JSON Accept 头和 `2022-11-28` API 版本；令牌不进入 URL。
- 支持注入 API 基址，并保留企业 API 的路径前缀。
- 401 和普通 403 映射为重新授权；主限流、429 和二级限流映射为带恢复时间的 `rateLimited`。
- README 只接受 Base64，移除换行后严格解码 UTF-8；保留路径和可选下载地址。

### 工作区数据融合

- 新增 `WorkspaceConnectivity`、五种 `WorkspacePanel`、`WorkspacePanelError`、`RepositoryContent` 和 `WorkspaceDashboardContent`。
- 本地 Git 是仓库状态和最近提交的事实源；最近提交请求和返回均最多 8 条。
- 本地仓库缺失或损坏时不调用本地 Git，仍返回在线摘要与 README，并记录稳定中文面板错误。
- 普通网络失败保留本地内容及有效缓存并标记离线；授权失效和限流保持独立状态。
- 在线摘要成功后按 `String(account.id)` 更新缓存；README 不进入工作区缓存。
- 缓存 TTL 为 900 秒，包含 0 和 900 秒边界；过期及未来时间快照不可用于回退或后续合并。
- 缓存更新在服务内串行执行原子“重读、校验、合并、保存”，并发刷新不同仓库不会互相覆盖。
- `LocalRepositoryCatalog.localURL(for:)` 复用安全目录名计算本地路径；目录统计或权限异常时构造 `.damaged` fallback，仓库页和工作台都继续返回在线摘要与 README。
- 工作台逐仓库隔离本地目录读取异常，单仓库失败不会中止其他仓库内容；面板错误保留仓库编号。
- 多个限流结果取较晚恢复时间，避免过早重试。

## TDD 证据

### 初始在线 API RED

保留前一实现代理留下的测试并运行：

```text
cannot find 'URLSessionGitHubWorkspaceAPI' in scope
```

失败原因是 Task 4 在线 API 尚未实现。实现摘要、限流、授权与 README 后，84 个测试全部通过。

遗留测试将 `2026-07-29T10:00:00Z` 错写为 Unix 时间 `1775034000`；核对后只将无效预期修正为准确值 `1785319200`，未改变测试行为。

### 融合服务 RED/GREEN

- 初始 RED：缺少 `WorkspaceContentService`、`WorkspaceConnectivity` 等生产类型。
- 第一轮 GREEN：91 个测试、失败 0 个。
- 增加非限流 403 和可注入 API 基址边界后：93 个测试、失败 0 个。
- 对 base URL 做反向变异，临时忽略注入值时定向测试准确失败 1 项；恢复正确实现后再次全绿。

### 正式审查修复

独立审查报告无 Critical，发现缓存有效性、并发更新、目录错误隔离、扩展限流和恢复时间选择问题。逐项增加回归测试：

- 过期快照中的其他摘要不得因目标仓库刷新而复活。
- 无法解码的旧缓存可被在线成功结果覆盖并恢复。
- 并发刷新两个仓库必须保留两个成功摘要。
- 429 与二级 403 限流必须保留 `Retry-After` 恢复时间；缺少限流头时至少等待 60 秒。
- 多个限流模块必须采用较晚恢复时间。
- 单仓库目录读取异常不得终止工作台其他仓库；直接加载仓库页也必须保留在线载荷。

第一次并发修复运行 98 个测试时仍有 1 项失败。根因是保存使用请求开始时刻，较早启动但较晚保存的请求会把刚写入快照判断为未来时间。将时间读取移动到缓存锁内后，98 个测试全部通过。

最终复核继续发现损坏缓存无法自愈、无恢复头的二级限流会立即重试，以及直接仓库页的目录统计异常仍会外抛。三项均先增加失败测试，再以最小实现修复；最终完整测试增至 100 项。

## 最终验证

测试命令：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/gitmate-task4-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/gitmate-task4-clang-cache \
swift run GitMateCoreTestsRunner
```

结果：

```text
完成 100 个测试，失败 0 个。
退出码：0
```

编译命令使用相同工具链和缓存变量执行 `swift build`，结果为 `Build complete!`，退出码 0。

差异与安全检查：

- `git diff --check` 及所有新增文件的 `git diff --no-index --check`：无空白错误。
- 生产文件扫描未发现令牌日志、令牌缓存或 URL 查询令牌。
- 生产代码中的令牌只沿 API 方法参数传递，并在请求边界写入 `Authorization: Bearer` 头。
- 真实请求测试确认 Search 查询正确编码、令牌不在 URL、Actions 参数固定。

## 变更文件

- `Sources/GitMateCore/GitHub/GitHubWorkspaceAPI.swift`
- `Sources/GitMateCore/GitHub/URLSessionGitHubWorkspaceAPI.swift`
- `Sources/GitMateCore/Workspace/WorkspaceContentService.swift`
- `Sources/GitMateCore/Workspace/WorkspaceDependencies.swift`
- `Sources/GitMateCore/Workspace/LocalRepositoryCatalog.swift`（主协调者授权的精确范围扩展）
- `Tests/GitMateCoreTests/GitHubWorkspaceAPITests.swift`
- `Tests/GitMateCoreTests/WorkspaceContentServiceTests.swift`
- `Tests/GitMateCoreTests/TestMain.swift`
- `.superpowers/sdd/2026-07-29-全局与仓库页面10-15实施计划/task-4-report.md`

## Concerns

- 无功能或安全阻塞。
- 现有 Task 2 的 `WorkspaceCacheSnapshot` 只有快照级 `savedAt`，因此 TTL 语义是快照级而不是逐仓库级；本实现只保留仍有效快照中的其他条目，符合“保留其他条目”和现有缓存结构。
- 当前系统默认 CommandLineTools 的编译器与 SDK 版本不匹配，最终验证显式使用已安装的 Xcode 工具链；不影响测试和构建结果。

---

## 正式审查修复 Round 1

### 审查问题

1. GitHub 同时返回 `Retry-After` 与 `X-RateLimit-Reset` 时，旧实现无条件采用后者，未遵守二级限流的明确等待时间。
2. 缓存原子事务由 `WorkspaceContentService` 实例锁保护；两个服务共享同一缓存资源时，实例锁互不相识，仍可能发生丢更新。

### RED 证据

新增两项真实行为测试：

- `限流同时返回两种恢复头时优先 Retry-After`
- `两个服务共享缓存时并发刷新不会丢失摘要`

测试命令：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/gitmate-task4-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/gitmate-task4-clang-cache \
swift run GitMateCoreTestsRunner
```

初始结果：

```text
✗ 限流同时返回两种恢复头时优先 Retry-After：实际 2000000900，预期 2000000030
✗ 两个服务共享缓存时并发刷新不会丢失摘要：实际 [202]，预期 [201, 202]
完成 102 个测试，失败 2 个。
```

限流单项修复后，双头限流和既有主限流 Reset 测试均通过，完整套件只剩共享缓存 1 项失败。

### 修复实现

- 限流恢复时间按以下顺序解析：
  1. 有效 `Retry-After` 秒数；
  2. 仅当 `X-RateLimit-Remaining == 0` 时使用有效 `X-RateLimit-Reset`；
  3. 二级限流或 429 没有有效恢复头时使用 `now + 60 秒`。
- `WorkspaceCaching` 新增同步原子 `update(accountID:_:)`。
- `JSONWorkspaceCache` 在自身资源锁内完成读取、变换、清洗和原子写入；公开 `load`、`save` 与 `update` 共享同一锁，内部使用 unlocked helper，避免锁重入。
- `WorkspaceContentService` 删除实例级缓存事务锁，在线摘要保存改为调用缓存资源的 `update`。
- 测试缓存 fixture 同样用资源锁实现 `update`；确定性交错 fixture 强制两个旧事务都读取相同空快照，证明旧实现会稳定丢失一个摘要。

### GREEN 与完整验证

完整测试：

```text
完成 102 个测试，失败 0 个。
退出码：0
```

完整编译：

```text
Build complete!
退出码：0
```

差异与安全检查：

- `git diff --check`：无空白错误。
- 生产代码扫描未发现令牌日志、缓存字段或 URL 查询令牌。
- 新增缓存协议不携带令牌；变换只处理工作区快照。

### Round 1 变更文件

- `Sources/GitMateCore/GitHub/URLSessionGitHubWorkspaceAPI.swift`
- `Sources/GitMateCore/Workspace/WorkspaceCache.swift`
- `Sources/GitMateCore/Workspace/WorkspaceContentService.swift`
- `Tests/GitMateCoreTests/GitHubWorkspaceAPITests.swift`
- `Tests/GitMateCoreTests/WorkspaceContentServiceTests.swift`
- `.superpowers/sdd/2026-07-29-全局与仓库页面10-15实施计划/task-4-report.md`

### Round 1 Concerns

- 无未解决的功能或安全阻塞。
- 默认 CommandLineTools 仍存在编译器与 SDK 版本不匹配，验证继续使用已安装的 Xcode 工具链。

---

## 正式审查修复 Round 2

### 覆盖测试

`Tests/GitMateCoreTests/GitHubWorkspaceAPITests.swift` 新增：

- `无效 Retry-After 回退主限流恢复时间`
- 表驱动覆盖 `-5`、`NaN`、`Infinity` 和非数字字符串。
- 响应同时携带 `X-RateLimit-Remaining: 0` 与合法未来 `X-RateLimit-Reset`，所有无效 `Retry-After` 都必须回退 Reset。

### RED 证据

命令：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/gitmate-task4-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/gitmate-task4-clang-cache \
swift run GitMateCoreTestsRunner
```

结果：

```text
✗ 无效 Retry-After 回退主限流恢复时间：
  实际 2000000000，预期 2000000900
完成 103 个测试，失败 1 个。
```

旧实现使用 `max(0, delay)`，把 `-5` 变为 0 秒并允许立即重试。

### 最小修复

- 只有 `Retry-After` 能解析为有限数值且 `delay >= 0` 时才采用。
- 负数、NaN、Infinity 和非数字都视为无效。
- 无效时继续使用既有优先级：主限流合法 Reset，其次 secondary/429 的 `now + 60 秒` 安全默认。
- 移除将负数夹为 0 的 `max(0, delay)`。

### GREEN 与完整验证

完整测试：

```text
完成 103 个测试，失败 0 个。
退出码：0
```

完整编译：

```text
Build complete!
退出码：0
```

差异与安全检查：

- `git diff --check`：无空白错误。
- 生产代码扫描未发现令牌日志、缓存字段或 URL 查询令牌。

### Round 2 变更文件

- `Sources/GitMateCore/GitHub/URLSessionGitHubWorkspaceAPI.swift`
- `Tests/GitMateCoreTests/GitHubWorkspaceAPITests.swift`
- `.superpowers/sdd/2026-07-29-全局与仓库页面10-15实施计划/task-4-report.md`

### Round 2 Concerns

- 无未解决的功能或安全阻塞。
