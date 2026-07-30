import AppKit
import SwiftUI

struct CommitGraphRegionEditor: View {
    let actionTitle: String
    let confirm: (String, String) -> Void
    let cancel: () -> Void

    @State private var title: String
    @State private var color: Color

    private let presetColors = [
        "#2F80ED",
        "#7B61FF",
        "#219653",
        "#F2994A",
        "#EB5757",
        "#2D9CDB",
    ]

    init(
        title: String,
        colorHex: String,
        actionTitle: String,
        confirm: @escaping (String, String) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.actionTitle = actionTitle
        self.confirm = confirm
        self.cancel = cancel
        _title = State(initialValue: title)
        _color = State(
            initialValue: CommitGraphRegionColor.color(hex: colorHex)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(actionTitle)
                    .font(.system(size: 20, weight: .bold))
                Text("区域仅用于标记大版本范围，不改变提交和分组关系。")
                    .font(.system(size: 12))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }

            TextField("例如：v2.0 稳定版", text: $title)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 10) {
                Text("标识颜色")
                    .font(.system(size: 12.5, weight: .semibold))

                HStack(spacing: 10) {
                    ForEach(presetColors, id: \.self) { value in
                        Button {
                            color = CommitGraphRegionColor.color(
                                hex: value
                            )
                        } label: {
                            Circle()
                                .fill(
                                    CommitGraphRegionColor.color(
                                        hex: value
                                    )
                                )
                                .frame(width: 25, height: 25)
                                .overlay {
                                    if CommitGraphRegionColor.hex(color)
                                        == value {
                                        Circle()
                                            .stroke(.white, lineWidth: 3)
                                            .padding(3)
                                    }
                                }
                                .overlay {
                                    Circle().stroke(
                                        GitMateTheme.border,
                                        lineWidth: 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()
                        .frame(height: 24)

                    ColorPicker(
                        "自定义",
                        selection: $color,
                        supportsOpacity: false
                    )
                }
            }

            HStack {
                Spacer()
                Button("取消", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    confirm(
                        title,
                        CommitGraphRegionColor.hex(color)
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}

enum CommitGraphRegionColor {
    static func color(hex: String) -> Color {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16)
        else {
            return CommitGraphPalette.color(0)
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func hex(_ color: Color) -> String {
        guard let resolved = NSColor(color).usingColorSpace(.sRGB) else {
            return "#2F80ED"
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(resolved.redComponent * 255)),
            Int(round(resolved.greenComponent * 255)),
            Int(round(resolved.blueComponent * 255))
        )
    }
}
