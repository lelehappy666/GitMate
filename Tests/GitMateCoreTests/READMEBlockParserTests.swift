import Foundation
import GitMateCore

let readmeBlockParserTests = [
    TestCase("README 不执行脚本和危险协议") {
        let parser = READMEBlockParser()
        let document = parser.parse("""
        # 标题
        <script>alert('x')</script>
        [危险](javascript:alert(1))
        [安全](https://github.com)
        """)

        try expect(!document.plainText.contains("alert('x')"), "脚本内容不得渲染")
        try expectEqual(document.links.map(\.url.scheme), ["https"], "只保留安全链接")
    },
    TestCase("危险 HTML 容器连同跨行内部文本完全移除") {
        let document = READMEBlockParser().parse("""
        开始
        <SCRIPT type="text/javascript">
        不得出现的脚本说明
        </SCRIPT>
        <iframe src="https://example.com">
        不得出现的框架说明
        </iframe>
        <object>
        不得出现的对象说明
        </object>
        结束
        """)

        try expectEqual(
            document.plainText,
            "开始\n结束",
            "危险容器内部文本不得进入文档"
        )
    },
    TestCase("相对图片按 README 地址解析且拒绝危险图片协议") {
        let baseURL = URL(
            string: "https://raw.githubusercontent.com/GitMate/app/main/README.md"
        )!
        let document = READMEBlockParser().parse(
            """
            ![界面](docs/dashboard.png)
            ![数据](data:image/png;base64,AAAA)
            ![文件](file:///tmp/secret.png)
            ![脚本](javascript:alert(1))
            """,
            baseURL: baseURL
        )
        let images = document.blocks.compactMap { block -> URL? in
            guard case let .image(url, _) = block else { return nil }
            return url
        }

        try expectEqual(
            images.map(\.absoluteString),
            [
                "https://raw.githubusercontent.com/GitMate/app/main/docs/dashboard.png"
            ],
            "只能保留解析后的 HTTP 或 HTTPS 图片"
        )
    },
    TestCase("围栏代码保留原文但不提取其中链接图片或 HTML") {
        let document = READMEBlockParser().parse("""
        ```html
        <script>alert('示例')</script>
        [伪链接](https://inside.example)
        ![伪图片](https://inside.example/image.png)
        ```
        [外链](http://outside.example)
        """)

        try expectEqual(
            document.links.map(\.url.absoluteString),
            ["http://outside.example"],
            "围栏代码中的 Markdown 不得参与链接提取"
        )
        let codeBlocks = document.blocks.compactMap { block -> String? in
            guard case let .code(_, value) = block else { return nil }
            return value
        }
        try expectEqual(
            codeBlocks,
            [
                """
                <script>alert('示例')</script>
                [伪链接](https://inside.example)
                ![伪图片](https://inside.example/image.png)
                """
            ],
            "围栏代码应作为纯文本代码块保留"
        )
        try expect(
            !document.blocks.contains {
                guard case .image = $0 else { return false }
                return true
            },
            "围栏代码中的图片不得变成图片块"
        )
    },
    TestCase("重复标题生成稳定且唯一的锚点") {
        let markdown = """
        # Hello, World!
        ## 安装
        ## 安装
        # Hello World
        """
        let first = READMEBlockParser().parse(markdown)
        let second = READMEBlockParser().parse(markdown)

        try expectEqual(
            first.outline.map(\.id),
            ["hello-world", "安装", "安装-2", "hello-world-2"],
            "标题锚点应清理标点并为重复项追加稳定序号"
        )
        try expectEqual(first.outline, second.outline, "重复解析必须生成相同目录")
    },
    TestCase("表格任务列表引用分隔线和图片解析为真实块模型") {
        let document = READMEBlockParser().parse(
            """
            | 名称 | 状态 |
            | --- | :---: |
            | Parser | 完成 |

            - [x] 安全解析
            - [ ] 缓存封面

            1. 第一项
            2. 第二项

            > 只执行受信任内容

            ---

            <img src="https://example.com/cover.png" alt="封面" width="800" height="500" onclick="evil()">
            """,
            baseURL: nil
        )

        try expectEqual(
            document.blocks,
            [
                .table(headers: ["名称", "状态"], rows: [["Parser", "完成"]]),
                .list(ordered: false, items: ["[x] 安全解析", "[ ] 缓存封面"]),
                .list(ordered: true, items: ["第一项", "第二项"]),
                .quote("只执行受信任内容"),
                .divider,
                .image(
                    url: URL(string: "https://example.com/cover.png")!,
                    alt: "封面"
                )
            ],
            "应生成可由原生视图消费的块模型"
        )
        try expect(
            !document.plainText.contains("onclick"),
            "HTML img 不得保留非白名单属性"
        )
    },
    TestCase("段落聚合文本并只暴露 HTTP 外链") {
        let document = READMEBlockParser().parse("""
        第一行 [安全](https://example.com/path)
        第二行 [相对](docs/help.md) [危险](javascript:alert(1))
        """)

        try expectEqual(
            document.blocks,
            [
                .paragraph(
                    READMEInlineContent(
                        text: "第一行 安全\n第二行 相对 危险",
                        links: [
                            READMEExternalLink(
                                title: "安全",
                                url: URL(string: "https://example.com/path")!
                            )
                        ]
                    )
                )
            ],
            "连续正文应合成段落并保留安全链接模型"
        )
    },
    TestCase("HTML 包裹中的 img 只保留安全图片属性") {
        let document = READMEBlockParser().parse(
            """
            <p align="center">
              <img src="assets/hero.png" alt="主界面" width="900" onerror="steal()">
            </p>
            <picture><img src="assets/mobile.png" alt="移动界面"></picture>
            """,
            baseURL: URL(string: "https://example.com/docs/README.md")!
        )

        try expectEqual(
            document.blocks,
            [
                .image(
                    url: URL(string: "https://example.com/docs/assets/hero.png")!,
                    alt: "主界面"
                ),
                .image(
                    url: URL(string: "https://example.com/docs/assets/mobile.png")!,
                    alt: "移动界面"
                )
            ],
            "多行和单行 HTML 包裹都不得阻止安全 img 解析"
        )
        try expect(!document.plainText.contains("onerror"), "事件属性不得进入纯文本")
    }
]
