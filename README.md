# GitMate

GitMate 是一款原生 macOS GitHub 管理工具。本阶段已实现第 01–09 页：登录、账户连接、权限确认、仓库首次同步设置、实时同步进度，以及错误、断网和授权失效恢复。

## 当前功能

- GitHub.com Device Flow 登录
- GitHub Enterprise Server 地址与 Personal Access Token 验证
- 访问令牌存入 macOS 钥匙串
- 读取真实用户头像与仓库列表
- 显示仓库可见性、默认分支和仓库大小
- 每仓库选择不同步、手动同步或自动同步
- 使用系统 Git 执行 clone 与 fetch
- 横向进度条和实时文件显示
- 单仓库失败、网络中断和授权失效恢复

## 运行要求

- macOS 14 或更高版本
- Swift 6
- 已创建支持 Device Flow 的 GitHub OAuth App

在环境变量中配置 OAuth App 客户端编号：

```bash
export GITMATE_GITHUB_CLIENT_ID="你的客户端编号"
swift run GitMate
```

如果未配置客户端编号，登录授权页会显示明确的配置错误；GitHub Enterprise 登录不依赖该变量。

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
