import SwiftUI

struct ConflictEditorPane: View {
    let title: String
    let text: String?
    let isEditable: Bool
    var editableText: Binding<String>?

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(GitMateTheme.panel)
            Divider()
            if isEditable, let editableText {
                TextEditor(text: editableText)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(.white)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(text ?? "这一侧已删除文件")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )
                        .padding(12)
                }
                .background(.white)
            }
        }
        .overlay {
            Rectangle()
                .stroke(GitMateTheme.border, lineWidth: 1)
        }
    }
}
