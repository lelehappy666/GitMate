import AppKit
import SwiftUI

enum GitMateTheme {
    static let background = Color.white
    static let canvas = Color(red: 0.965, green: 0.975, blue: 0.988)
    static let panel = Color(red: 0.975, green: 0.982, blue: 0.992)
    static let sidebar = Color(red: 0.952, green: 0.965, blue: 0.98)
    static let surfaceMuted = Color(red: 0.945, green: 0.958, blue: 0.976)
    static let selection = Color(red: 0.865, green: 0.925, blue: 0.995)
    static let textPrimary = Color(red: 0.075, green: 0.105, blue: 0.16)
    static let textSecondary = Color(red: 0.25, green: 0.31, blue: 0.39)
    static let textTertiary = Color(red: 0.42, green: 0.47, blue: 0.54)
    static let accent = Color(red: 0.12, green: 0.45, blue: 0.82)
    static let accentSoft = Color(red: 0.90, green: 0.95, blue: 1.0)
    static let border = Color(red: 0.84, green: 0.87, blue: 0.91)
    static let success = Color(red: 0.20, green: 0.58, blue: 0.34)
    static let warning = Color(red: 0.88, green: 0.56, blue: 0.12)
    static let danger = Color(red: 0.80, green: 0.20, blue: 0.25)

    static let cornerRadius: CGFloat = 16
    static let compactCornerRadius: CGFloat = 11
    static let contentMaxWidth: CGFloat = 1_080
    static let workspaceSidebarWidth: CGFloat = 240
    static let workspaceHeaderHeight: CGFloat = 66
    static let workspaceListWidth: CGFloat = 520
    static let workspaceRowHeight: CGFloat = 64
}

struct GitMateAvatar: View {
    let url: URL?
    var size: CGFloat = 48
    var fallbackText: String? = nil
    var fallbackColorIndex = 0
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let fallbackText = normalizedFallbackText {
                ZStack {
                    Circle().fill(fallbackColor.opacity(0.14))
                    Text(fallbackText)
                        .font(
                            .system(
                                size: max(size * 0.36, 8),
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(fallbackColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(GitMateTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(GitMateTheme.border, lineWidth: 1)
        }
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard let url,
                  let data = await AvatarDataCache.shared.data(for: url)
            else {
                return
            }
            guard !Task.isCancelled else { return }
            image = NSImage(data: data)
        }
    }

    private var normalizedFallbackText: String? {
        let value = fallbackText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return String(value.prefix(2))
    }

    private var fallbackColor: Color {
        let colors: [Color] = [
            Color(red: 0.08, green: 0.38, blue: 0.75),
            Color(red: 0.37, green: 0.20, blue: 0.68),
            Color(red: 0.10, green: 0.47, blue: 0.33),
            Color(red: 0.68, green: 0.31, blue: 0.08),
            Color(red: 0.62, green: 0.16, blue: 0.34),
            Color(red: 0.18, green: 0.43, blue: 0.52)
        ]
        let index = Int(fallbackColorIndex.magnitude % UInt(colors.count))
        return colors[index]
    }
}

private actor AvatarDataCache {
    static let shared = AvatarDataCache()

    private let maximumEntryCount = 256
    private var cachedData: [URL: Data] = [:]
    private var insertionOrder: [URL] = []
    private var inFlightTasks: [URL: Task<Data?, Never>] = [:]

    func data(for url: URL) async -> Data? {
        if let data = cachedData[url] {
            return data
        }
        if let task = inFlightTasks[url] {
            return await task.value
        }

        let task = Task<Data?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode)
            else {
                return nil
            }
            return data
        }
        inFlightTasks[url] = task
        let data = await task.value
        inFlightTasks[url] = nil

        if let data {
            cachedData[url] = data
            insertionOrder.append(url)
            if insertionOrder.count > maximumEntryCount {
                let expiredURL = insertionOrder.removeFirst()
                cachedData[expiredURL] = nil
            }
        }
        return data
    }
}
