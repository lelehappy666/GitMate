import Foundation

/// 为侧边栏重复打开提交图生成仓库独立的刷新代次。
///
/// SwiftUI 的路由值在重复点击同一页面时不会改变，因此不能仅依赖路由
/// 驱动页面任务。该令牌每次请求都会产生新代次，供页面的 `.task(id:)`
/// 显式刷新使用。
public struct CommitGraphRefreshTrigger: Equatable, Sendable {
    private var revisions: [Int64: Int] = [:]

    public init() {}

    @discardableResult
    public mutating func request(repositoryID: Int64) -> Int {
        let current = revisions[repositoryID, default: 0]
        // Int 达到上限时从一重新开始，避免调试构建因溢出而崩溃。代次
        // 只用于 SwiftUI 任务身份；每个仓库的请求仍保持彼此独立。
        let next = current == Int.max ? 1 : current + 1
        revisions[repositoryID] = next
        return next
    }

    public func revision(repositoryID: Int64) -> Int {
        revisions[repositoryID, default: 0]
    }
}
