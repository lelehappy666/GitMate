import GitMateCore
import SwiftUI

struct CommitGraphGroupSuggestionSheet: View {
    let suggestions: [CommitGraphGroupSuggestion]
    let confirm: (Set<String>) -> Void
    let cancel: () -> Void

    @State private var selectedIDs: Set<String>

    init(
        suggestions: [CommitGraphGroupSuggestion],
        confirm: @escaping (Set<String>) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.suggestions = suggestions
        self.confirm = confirm
        self.cancel = cancel
        _selectedIDs = State(
            initialValue: Set(suggestions.map(\.id))
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自动分组建议")
                        .font(.system(size: 20, weight: .bold))
                    Text("建议不会自动创建，确认后才会写入当前仓库画布。")
                        .font(.system(size: 12))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
            }
            .padding(22)

            Divider()

            if suggestions.isEmpty {
                ContentUnavailableView(
                    "暂无可用建议",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("当前分支没有独占且连通的提交区域。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(suggestions) { suggestion in
                    Toggle(
                        isOn: Binding(
                            get: {
                                selectedIDs.contains(suggestion.id)
                            },
                            set: { selected in
                                if selected {
                                    selectedIDs.insert(suggestion.id)
                                } else {
                                    selectedIDs.remove(suggestion.id)
                                }
                            }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.branchName)
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(suggestion.memberHashes.count) 个独占提交")
                                .font(.system(size: 11))
                                .foregroundStyle(
                                    GitMateTheme.textSecondary
                                )
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.vertical, 5)
                }
            }

            Divider()

            HStack {
                Button("取消", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("确认创建") {
                    confirm(selectedIDs)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIDs.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 520, height: 460)
        .background(.white)
    }
}
