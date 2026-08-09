import Foundation

public enum BranchOperationError: Error, Equatable, Sendable {
    case invalidReference(String)
    case workingTreeNotClean(files: [String])
    case commandFailed(code: Int32, message: String)
    case cancelled
}

extension BranchOperationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidReference(name):
            "“\(name)”不是有效的 Git 引用名称。"
        case let .workingTreeNotClean(files):
            files.isEmpty
                ? "当前工作区存在未提交修改。"
                : "当前工作区存在未提交修改：\(files.joined(separator: "、"))"
        case let .commandFailed(code, message):
            "Git 操作失败（\(code)）：\(message)"
        case .cancelled:
            "Git 操作已取消。"
        }
    }
}
