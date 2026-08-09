# Task 3：严格只读的本地 Git 服务实施报告

## 状态

已完成。生产读取路径只会构造 `status`、`ls-tree`、`show`、`log` 五类只读 Git 命令；输入校验、输出解析、原始字节通道、分页和错误传播均有自动化测试。

## 实现内容

### 本地 Git 模型与协议

- 新增 `LocalGitReading`，覆盖仓库状态、文件树、文件内容、提交分页、提交详情、差异和提交图。
- 新增 `LocalRepositoryStatus`、`GitFileEntry`、`GitFileContent`、`GitCommit`、`GitCommitPage`、`GitCommitDetail`、`GitChangedFile`、`GitDiff`、`CommitGraphPage` 和签名状态模型。
- 新增可描述的输入校验与 Git 输出解析错误。

### 严格只读命令与输入边界

- 状态：`-C <repo> status --porcelain=v2 --branch -z`
- 文件树：`-C <repo> ls-tree -z -l <revision> -- <path>`
- 文件：`-C <repo> show <revision>:<path>`
- 提交/图：`-C <repo> log --format=<字段格式> -n <limit> [--skip <offset>]`
- 详情/差异：`-C <repo> show --format=<字段格式> --numstat --patch <hash>`
- revision/hash 只允许 ASCII 字母数字和安全 Git revision 标点，且不得以 `-` 开头。
- path 必须相对、不得含 `..` 或 NUL；文件树空根路径规范化为 Git 可用的 `.`。
- limit 严格限制为 `1...200`；cursor 只接受非负 ASCII 十进制整数。
- 本地读取环境恒为空，命令参数不携带凭据。

### Git 输出解析

- 提交记录使用 `0x1f` 字段分隔和 `0x1e` 记录分隔，兼容 7/8 字段并解析父提交、装饰和 ISO 8601 时间。
- 文件树按 `ls-tree -z -l` 的 mode/type/object/size/path 解析，单条不安全路径直接过滤，畸形记录抛错。
- porcelain v2 解析 branch、upstream、ahead/behind，并统计 staged、unstaged、untracked、conflict。
- show 元数据以 `0x1e` 与 numstat/patch 分离，保留完整 `%B` 消息、签名三态、二进制 numstat 和 patch 空白。

### 无损 Data 通道

- 保持 `CommandExecuting.execute(arguments:environment:)` 签名不变，为 `CommandOutput` 增加 stdout/stderr Data cases，同时保留 String cases 兼容测试 fake。
- `ProcessCommandExecutor` 原样传递 Data chunk，不再裁剪行、删除空行或改写 stdout 内容。
- 每个 pipe 使用独立 `ProcessPipeReader`，将“读取 + consume”置于同一锁内；termination 移除 handler 后通过同一锁 drain，两个流均排空后才 finish，避免尾段乱序或在途早段丢失。
- stderr 原始 Data 用于非零退出错误聚合，错误文本采用 UTF-8 replacement decoding 并清洗 URL userinfo。
- `CommandLocalGitReader` 原样拼接 Data；String fake 仅按 UTF-8 追加，不自行插入分隔符。
- `GitRepositorySyncService` 分 stdout/stderr 缓冲 Data，按 CR/LF 完整行解码后再脱敏和节流；跨 UTF-8 标量和跨 chunk URL 凭据均不会损坏或泄露。超过 16 KiB 的未终止活动行会安全省略，并丢弃到下一个行分隔符。

### 测试双契约

- `FakeCommandExecutor` 区分“未启用调用契约”和“严格调用契约”。
- 严格模式会拒绝参数不符、额外调用和缺少预置结果。
- `verifyComplete()` 检查剩余预期调用与未消费结果。
- 业务测试除校验命令契约外，仍断言真实解析后的模型与错误传播。

## TDD 证据

所有测试期望值均由固定夹具手工推导；真实仓库夹具只在测试设置阶段执行 `init/config/add/commit`，生产实现没有 Git 写操作。

### 第 1 轮：基础提交与树解析

- RED 命令：`swift run --disable-sandbox GitMateCoreTestsRunner`
- RED 结果：退出码 1，编译器报告 `cannot find 'GitOutputParser' in scope`。
- GREEN 结果：51 个测试，失败 0 个。

### 第 2 轮：全部模型、解析、命令与输入边界

- RED 结果：退出码 1，缺少 `GitChangedFile`、`CommandLocalGitReader`、`LocalGitReaderError`、`parseStatus` 和 `parseShow`，与预期一致。
- GREEN 结果：65 个测试，失败 0 个。

### 第 3 轮：fake 参数契约

- RED 结果：退出码 1，`expectedInvocations` 为额外初始化参数。
- GREEN 结果：65 个测试，失败 0 个。

### 第 4 轮：测试突变检查

- 临时反向突变：仅检查 `../` 前缀、签名恒为 verified、忽略畸形 numstat、接受负 cursor。
- RED 结果：67 个测试中 4 个定向失败，分别命中嵌套路径逃逸、签名映射、畸形 numstat 和负 cursor。
- 恢复正确实现后的 GREEN：67 个测试，失败 0 个。

### 第 5 轮：根路径与严格调用次数

- RED 结果：退出码 1，测试要求的 `verifyComplete()` 尚不存在。
- GREEN 结果：67 个测试，失败 0 个；真实 Git 另确认空 pathspec 会报错、`.` 可列根目录、`Sources/` 可列子项。

### 第 6 轮：真实进程无损数据

- 首次运行因环境的空 `init.defaultBranch` 导致夹具失败，不计为有效 RED；夹具显式使用 `--initial-branch=main` 后重新运行。
- 有效 RED：70 个测试中 3 个失败。
  - 非 UTF-8 blob 实际 0 字节，预期 4 字节。
  - 带空白/空行文本实际为空串。
  - 提交消息的空行、缩进和末尾换行被裁剪。
- Data 通道初版后只剩提交消息 trim 1 个失败。
- 删除 `%B` trim 后 GREEN：70 个测试，失败 0 个。

### 第 7 轮：跨 chunk UTF-8 与凭据

- RED：73 个测试中 2 个失败。
  - 中文 UTF-8 标量被切块后活动显示为 `�`。
  - URL userinfo 被切块后出现未脱敏 `private-`。
- 完整行 Data 缓冲后 GREEN：73 个测试，失败 0 个。

### 第 8 轮：termination 顺序与超长行

- RED：退出码 1，缺少测试指定的 `ProcessPipeReader`；超长行测试同时加入。
- GREEN：75 个测试，失败 0 个。
- 可控并发测试确认 drain 会等待持锁的在途 handler，并按 `A` 后 `B` 汇总；128 KiB+1 的非 UTF-8 blob 真实读取保持 131073 字节。

## 最终验证

### 完整测试

```text
CLANG_MODULE_CACHE_PATH=.build/clang-module-cache \
SWIFT_MODULECACHE_PATH=.build/swift-module-cache \
swift run --disable-sandbox GitMateCoreTestsRunner

完成 75 个测试，失败 0 个。
退出码：0
```

### 完整编译

```text
CLANG_MODULE_CACHE_PATH=.build/clang-module-cache \
SWIFT_MODULECACHE_PATH=.build/swift-module-cache \
swift build --disable-sandbox

Build complete!
退出码：0
```

### 差异与安全扫描

- `git diff --check`：退出码 0，无空白错误。
- 在 `Sources/GitMateCore/LocalGit`、`ProcessCommandExecutor.swift`、`CommandExecuting.swift` 扫描 Git 写命令字符串：唯一命中是 `type == "commit"`，它是 `ls-tree` 子模块对象类型，不是命令；无 checkout/reset/cherry-pick/merge/rebase/fetch/clone 写命令。
- 同范围扫描 `Authorization|Token|token`：无匹配。
- 生产 LocalGit 命令仅包含 status、ls-tree、show、log。

## 变更文件

- `Sources/GitMateCore/LocalGit/LocalGitReading.swift`
- `Sources/GitMateCore/LocalGit/LocalGitModels.swift`
- `Sources/GitMateCore/LocalGit/GitOutputParser.swift`
- `Sources/GitMateCore/LocalGit/CommandLocalGitReader.swift`
- `Sources/GitMateCore/Sync/CommandExecuting.swift`
- `Sources/GitMateCore/Sync/ProcessCommandExecutor.swift`
- `Sources/GitMateCore/Sync/GitRepositorySyncService.swift`
- `Tests/GitMateCoreTests/LocalGitReaderTests.swift`
- `Tests/GitMateCoreTests/RepositorySyncServiceTests.swift`
- `Tests/GitMateCoreTests/Support/FakeCommandExecutor.swift`
- `Tests/GitMateCoreTests/TestMain.swift`
- `.superpowers/sdd/2026-07-29-全局与仓库页面10-15实施计划/task-3-report.md`

## 自审

- 需求逐项核对：模型、7 个协议方法、5 类命令、三类输入校验、分页、解析错误、只读安全均已覆盖。
- 安全突变核对：错误命令参数、负/非数字游标、0/201 limit、绝对/嵌套逃逸 path、不安全 revision/hash、额外/缺少调用均有测试。
- 数据完整性核对：NUL、非 UTF-8、多 chunk 大 blob、前导/尾随空白、空行、完整提交消息和 patch 均由真实默认执行器覆盖。
- 并发核对：stdout/stderr 每个 pipe 独立串行，termination drain 与在途 handler 共用同一临界区。
- 未修改 `CommandExecuting.execute` 的生产签名；新增 Data cases 为父任务明确授权的最小兼容扩展。

## Concerns

- SwiftPM 在沙箱内提示用户级配置与缓存目录不可写，并禁用用户缓存；测试与编译退出码均为 0，不影响功能。
- 无未解决的功能或安全 concern。

---

## 正式审查修复 Round 1

### 覆盖测试文件

- `Tests/GitMateCoreTests/LocalGitReaderTests.swift`
  - type-2 重命名后的三个原路径分别以 `? `、`u `、`1 ` 开头，均不得再次计数或解析。
  - 真实临时 Git 仓库的提交消息包含合法 `0x1f` 与 `0x1e`，详情必须逐字节保留，差异仍须正常解析。
  - 详情与差异分别验证两条新的只读 `show` 参数契约。
  - fake 参数不匹配后，正确调用仍获得原预置结果；`verifyComplete()` 继续报告历史契约失败。
- `Tests/GitMateCoreTests/RepositorySyncServiceTests.swift`
  - String stdout 与 String stderr 的 URL userinfo 均跨两个 chunk，完整行缓冲后才允许脱敏上报。

### RED 证据

命令：

```text
CLANG_MODULE_CACHE_PATH=.build/clang-module-cache \
SWIFT_MODULECACHE_PATH=.build/swift-module-cache \
swift run --disable-sandbox GitMateCoreTestsRunner
```

初始结果：79 个测试，失败 6 个，退出码 1。

具体失败：

1. String stderr 分片实际提前上报 `remote: https://private-`。
2. String stdout 分片实际提前上报 `remote: https://private-`。
3. type-2 的 `1 old-ordinary.swift` 被当作独立状态记录并抛 `malformedStatus`。
4. 详情调用仍执行旧的含 `%B` US/RS 格式，与新 NUL 契约不匹配。
5. 真实提交消息在内部 `0x1e` 处被提前截断并抛 `malformedShow`。
6. fake 参数不匹配后提前消费预期与结果，后续正确调用变成“未预期额外命令”。

### 逐项 GREEN 证据

1. String stdout/stderr 都编码为 UTF-8 Data 并进入对应 `GitActivityDataBuffer` 后：失败数由 6 降至 4，两项跨 chunk 脱敏测试通过。
2. porcelain v2 改为索引遍历并明确消费 type-2 下一段原路径后：失败数由 4 降至 3，三个特殊前缀原路径均未误计。
3. fake 仅在参数匹配时同时出队预期与结果，并持久记录所有契约失败后：失败数由 3 降至 2；正确调用复用了未消费结果，`verifyComplete()` 仍失败。
4. 详情/差异拆为两条只读 show，并使用 NUL 固定边界后：79 个测试，失败 0 个。

### 修复实现

- `GitRepositorySyncService`
  - `.standardOutput(String)` 与 `.standardError(String)` 不再直接上报。
  - String 先转 UTF-8 Data，分别进入 stdout/stderr 缓冲；只在完整 CR/LF 行或流结束 flush 时解码、脱敏与节流。
- `GitOutputParser.parseStatus`
  - 使用索引遍历 NUL 记录。
  - type-2 记录解析 XY 后强制存在并跳过下一段原路径；缺失原路径视为畸形输出。
- `CommandLocalGitReader` 与 `GitOutputParser`
  - commit detail：`show --no-patch --format=<NUL 固定字段，%B 最后> <hash>`。
  - diff：`show --format=%H%x00 --numstat --patch <hash>`。
  - Git 对象不能含 NUL，因此提交消息中的 `0x1e`、`0x1f`、换行与缩进都可无损保留。
  - 两条命令均为只读 `show`，未增加写操作。
- `FakeCommandExecutor`
  - 参数不匹配、额外调用、缺少结果均持久记录。
  - 仅参数匹配成功才移除期望调用并消费对应结果。
  - `verifyComplete()` 优先报告历史契约失败，再检查剩余预期与结果。

### Round 1 最终验证

完整测试：

```text
完成 79 个测试，失败 0 个。
退出码：0
```

完整编译：

```text
swift build --disable-sandbox
Build complete!
退出码：0
```

差异与安全扫描：

- `git diff --check`：退出码 0。
- LocalGit、ProcessCommandExecutor、CommandExecuting 中扫描 checkout/reset/cherry-pick/merge/rebase/fetch/clone/commit 命令字符串：仅命中 `type == "commit"` 的 Git tree 对象类型，不是命令。
- 同范围扫描 `Authorization|Token|token`：无匹配。
- 新增生产命令仅为两条 `show` 只读形态。

### Round 1 变更文件

- `Sources/GitMateCore/LocalGit/CommandLocalGitReader.swift`
- `Sources/GitMateCore/LocalGit/GitOutputParser.swift`
- `Sources/GitMateCore/Sync/GitRepositorySyncService.swift`
- `Tests/GitMateCoreTests/LocalGitReaderTests.swift`
- `Tests/GitMateCoreTests/RepositorySyncServiceTests.swift`
- `Tests/GitMateCoreTests/Support/FakeCommandExecutor.swift`
- `.superpowers/sdd/2026-07-29-全局与仓库页面10-15实施计划/task-3-report.md`

### Round 1 自审与 Concerns

- 四项正式审查发现均有先失败、后通过的行为回归。
- production LocalGit 仍严格只读；测试夹具中的 commit 仅用于构造真实提交对象。
- SwiftPM 用户级缓存不可写警告仍存在，不影响测试与编译退出码。
- 无未解决的功能或安全 concern。
