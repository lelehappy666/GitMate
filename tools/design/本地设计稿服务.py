#!/usr/bin/env python3
"""为 GitMate HTML 设计稿提供 UTF-8 本地预览服务。"""

from __future__ import annotations

import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse


class DesignHandler(SimpleHTTPRequestHandler):
    """补充 UTF-8 响应，并兼容历史设计稿的 /files/ 资源路径。"""

    def guess_type(self, path: str) -> str:
        content_type = super().guess_type(path)
        if content_type == "text/html":
            return "text/html; charset=utf-8"
        if content_type == "text/css":
            return "text/css; charset=utf-8"
        if content_type in {"application/javascript", "text/javascript"}:
            return f"{content_type}; charset=utf-8"
        return content_type

    def translate_path(self, path: str) -> str:
        parsed_path = unquote(urlparse(path).path)
        if parsed_path.startswith("/files/"):
            parsed_path = "/" + parsed_path.removeprefix("/files/")
        return super().translate_path(parsed_path)

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser(description="启动 GitMate 设计稿本地预览服务")
    parser.add_argument("--port", type=int, default=51950, help="监听端口")
    parser.add_argument(
        "--directory",
        type=Path,
        default=Path(".superpowers/brainstorm/53164-1785202648/content"),
        help="设计稿 HTML 所在目录",
    )
    args = parser.parse_args()

    directory = args.directory.expanduser().resolve()
    if not directory.is_dir():
        raise SystemExit(f"设计稿目录不存在：{directory}")

    def handler(*handler_args, **handler_kwargs):
        return DesignHandler(
            *handler_args,
            directory=str(directory),
            **handler_kwargs,
        )

    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    print(f"设计稿服务已启动：http://127.0.0.1:{args.port}/")
    print(f"设计稿目录：{directory}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
