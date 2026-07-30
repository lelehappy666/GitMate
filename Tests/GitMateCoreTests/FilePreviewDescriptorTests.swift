import Foundation
import GitMateCore

let filePreviewDescriptorTests = [
    TestCase("文件预览按真实签名识别位图与 PDF") {
        let png = Data([
            0x89, 0x50, 0x4E, 0x47,
            0x0D, 0x0A, 0x1A, 0x0A
        ])
        try expectEqual(
            FilePreviewClassifier.classify(
                path: "image.dat",
                data: png,
                decodedText: nil
            ).kind,
            .rasterImage,
            "PNG 必须按内容签名识别而不是依赖扩展名"
        )
        try expectEqual(
            FilePreviewClassifier.classify(
                path: "manual.bin",
                data: Data("%PDF-1.7".utf8),
                decodedText: nil
            ).kind,
            .pdf,
            "PDF 必须按真实文件头识别"
        )
    },
    TestCase("伪造图片扩展名不会进入图片预览") {
        let document = FilePreviewClassifier.classify(
            path: "fake.png",
            data: Data([0x00, 0x01, 0x02, 0x03]),
            decodedText: nil
        )

        try expectEqual(
            document.kind,
            .unsupportedBinary,
            "扩展名与签名不符时不得交给图片解码器"
        )
    },
    TestCase("HTML SVG Markdown 与脚本分类到正确预览") {
        try expectEqual(
            FilePreviewClassifier.classify(
                path: "preview.html",
                data: Data("<html><body>安全预览</body></html>".utf8),
                decodedText: "<html><body>安全预览</body></html>"
            ).kind,
            .html,
            "HTML 应进入安全网页预览"
        )
        try expectEqual(
            FilePreviewClassifier.classify(
                path: "diagram.svg",
                data: Data("<svg viewBox='0 0 10 10'></svg>".utf8),
                decodedText: "<svg viewBox='0 0 10 10'></svg>"
            ).kind,
            .vectorImage,
            "SVG 应进入受限矢量预览"
        )
        try expectEqual(
            FilePreviewClassifier.classify(
                path: "README.md",
                data: Data("# 标题".utf8),
                decodedText: "# 标题"
            ).kind,
            .source(.markdown),
            "Markdown 应使用靠左源码预览"
        )
        try expectEqual(
            FilePreviewClassifier.classify(
                path: "Scripts/build.py",
                data: Data("print('ok')".utf8),
                decodedText: "print('ok')"
            ).kind,
            .source(.python),
            "脚本文件应识别语言并进入源码预览"
        )
    },
    TestCase("文件预览覆盖常见位图签名与脚本语言") {
        let signatures: [(String, Data)] = [
            ("a.jpg", Data([0xFF, 0xD8, 0xFF])),
            ("a.gif", Data("GIF89a".utf8)),
            ("a.tiff", Data([0x49, 0x49, 0x2A, 0x00])),
            ("a.bmp", Data([0x42, 0x4D, 0x00, 0x00])),
            (
                "a.webp",
                Data("RIFF".utf8)
                    + Data([0, 0, 0, 0])
                    + Data("WEBP".utf8)
            ),
            (
                "a.heic",
                Data([0, 0, 0, 0])
                    + Data("ftyp".utf8)
                    + Data("heic".utf8)
            )
        ]
        for (path, data) in signatures {
            try expectEqual(
                FilePreviewClassifier.classify(
                    path: path,
                    data: data,
                    decodedText: nil
                ).kind,
                .rasterImage,
                "\(path) 应按签名识别为位图"
            )
        }

        let languages: [(String, SourceLanguage)] = [
            ("main.swift", .swift),
            ("index.tsx", .typescript),
            ("build.sh", .shell),
            ("main.rs", .rust),
            ("query.sql", .sql),
            ("config.yml", .yaml),
            ("App.kt", .kotlin),
            ("server.go", .go)
        ]
        for (path, language) in languages {
            let text = "sample"
            try expectEqual(
                FilePreviewClassifier.classify(
                    path: path,
                    data: Data(text.utf8),
                    decodedText: text
                ).kind,
                .source(language),
                "\(path) 应识别对应脚本语言"
            )
        }
    },
    TestCase("无效文本与未知二进制显示不同状态") {
        try expectEqual(
            FilePreviewClassifier.classify(
                path: "Legacy.txt",
                data: Data([0xFF, 0xFE]),
                decodedText: nil
            ).kind,
            .invalidText,
            "已知文本扩展名解码失败应提示无效文本"
        )
        try expectEqual(
            FilePreviewClassifier.classify(
                path: "Archive.bin",
                data: Data([0x00, 0xFF, 0x10]),
                decodedText: nil
            ).kind,
            .unsupportedBinary,
            "未知二进制应显示不支持状态"
        )
    },
    TestCase("不同预览格式使用独立安全大小上限") {
        try expectEqual(
            FilePreviewPolicy.maximumBytes(for: "README.md"),
            2 * 1_024 * 1_024,
            "源码预览上限应为 2MB"
        )
        try expectEqual(
            FilePreviewPolicy.maximumBytes(for: "diagram.svg"),
            25 * 1_024 * 1_024,
            "图片与 SVG 预览上限应为 25MB"
        )
        try expectEqual(
            FilePreviewPolicy.maximumBytes(for: "manual.pdf"),
            50 * 1_024 * 1_024,
            "PDF 预览上限应为 50MB"
        )
    },
    TestCase("安全 HTML 只允许内存页面导航") {
        try expect(
            HTMLPreviewSecurityPolicy.allowsNavigation(
                to: URL(string: "about:blank")!
            ),
            "about:blank 必须允许"
        )
        try expect(
            HTMLPreviewSecurityPolicy.allowsNavigation(
                to: URL(string: "data:text/html,hello")!
            ),
            "data URI 必须允许"
        )
        for value in [
            "https://example.com",
            "http://example.com",
            "file:///tmp/secret",
            "gitmate://open"
        ] {
            try expect(
                !HTMLPreviewSecurityPolicy.allowsNavigation(
                    to: URL(string: value)!
                ),
                "\(value) 必须被安全策略拒绝"
            )
        }
    },
    TestCase("短源码容器至少铺满真实可用宽度") {
        try expectEqual(
            SourcePreviewLayoutPolicy.minimumContentWidth(
                viewportWidth: 1_000,
                horizontalPadding: 36
            ),
            964,
            "源码容器必须使用扣除内边距后的真实宽度"
        )
    }
]
