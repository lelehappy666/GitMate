import fs from "node:fs/promises";
import path from "node:path";

const root = process.cwd();
const sourceDir = path.join(
  root,
  ".superpowers/brainstorm/53164-1785202648/content",
);
const outputDir = path.join(root, "output/design/GitMate全部页面设计图");

const sourceFiles = await fs.readdir(sourceDir);
const latestByPage = new Map();

for (const name of sourceFiles) {
  const match = name.match(/^page-(\d{2})-(.+)-v(\d+)\.html$/);
  if (!match) continue;

  const page = Number(match[1]);
  if (page < 1 || page > 91) continue;

  const candidate = {
    name,
    page,
    slug: match[2],
    version: Number(match[3]),
  };
  const current = latestByPage.get(page);
  if (!current || candidate.version > current.version) {
    latestByPage.set(page, candidate);
  }
}

const pages = [];
for (let page = 1; page <= 91; page += 1) {
  const source = latestByPage.get(page);
  if (!source) {
    throw new Error(`缺少第 ${page} 页设计稿`);
  }

  const html = await fs.readFile(path.join(sourceDir, source.name), "utf8");
  const labelMatch = html.match(
    /<span class="(?:page-index|batch-page-index)">([^<]+)<\/span>/,
  );
  const label = labelMatch?.[1]?.trim() ?? `页面 ${String(page).padStart(2, "0")}`;
  const image = `${String(page).padStart(2, "0")}-${source.slug}.png`;

  await fs.access(path.join(outputDir, image));
  pages.push({...source, label, image});
}

const cards = pages
  .map(
    ({page, label, image, version}) => `
      <article class="card">
        <a href="${image}" target="_blank" rel="noreferrer">
          <img src="${image}" alt="${label}" loading="${page <= 4 ? "eager" : "lazy"}">
        </a>
        <div class="meta">
          <strong>${label}</strong>
          <span>2× Retina · V${version} · 点击查看原图</span>
        </div>
      </article>`,
  )
  .join("");

const indexHtml = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>GitMate 全部页面设计图</title>
  <style>
    :root {
      color-scheme: light;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text",
        "PingFang SC", "Microsoft YaHei", sans-serif;
      color: #172033;
      background: #f5f7fa;
    }
    * { box-sizing: border-box; }
    body { margin: 0; }
    header {
      position: sticky;
      top: 0;
      z-index: 10;
      display: flex;
      min-height: 72px;
      padding: 14px 24px;
      align-items: center;
      justify-content: space-between;
      gap: 20px;
      border-bottom: 1px solid #dfe4eb;
      background: rgba(255, 255, 255, .92);
      backdrop-filter: blur(18px);
    }
    h1 { margin: 0 0 4px; font-size: 20px; }
    header p { margin: 0; color: #657287; font-size: 12px; }
    .count {
      padding: 7px 10px;
      border-radius: 999px;
      color: #1f69b4;
      background: #eaf3fc;
      font-size: 12px;
      font-weight: 750;
      white-space: nowrap;
    }
    main {
      display: grid;
      max-width: 1680px;
      margin: 0 auto;
      padding: 24px;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 20px;
    }
    .card {
      overflow: hidden;
      border: 1px solid #dfe4eb;
      border-radius: 14px;
      background: #fff;
      box-shadow: 0 8px 26px rgba(31, 45, 65, .07);
    }
    .card a {
      display: block;
      overflow: hidden;
      border-bottom: 1px solid #e8ecf1;
      background: #edf1f5;
    }
    .card img {
      display: block;
      width: 100%;
      height: auto;
      transition: transform .2s ease;
    }
    .card a:hover img { transform: scale(1.008); }
    .meta {
      display: flex;
      min-height: 62px;
      padding: 12px 14px;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
    }
    .meta strong { font-size: 13px; }
    .meta span { color: #7b8798; font-size: 11px; white-space: nowrap; }
    @media (max-width: 900px) {
      main { grid-template-columns: 1fr; padding: 14px; }
      header { padding: 12px 14px; }
      .meta { align-items: flex-start; flex-direction: column; }
    }
  </style>
</head>
<body>
  <header>
    <div>
      <h1>GitMate 全部页面设计图</h1>
      <p>2× Retina 高保真原图，按页面编号排列，可独立打开、下载或分享。</p>
    </div>
    <span class="count">共 ${pages.length} 张</span>
  </header>
  <main>${cards}
  </main>
</body>
</html>
`;

const readme = `# GitMate 全部页面设计图

- 共 ${pages.length} 张独立 2× Retina PNG 图片，页码范围 01–91。
- 图片仅保留软件窗口画板，不包含设计说明和确认按钮。
- 页面 01–29 约为 2884 × 1384px，页面 30–91 约为 2884 × 1364px。
- 同一页面存在多个修改版本时，仅保留已确认的最高版本。
- 双击 \`index.html\` 可连续浏览全部页面。
- 点击索引中的任意图片，可打开该页面原图。
- 页面 92 是历史连续预览，不属于独立功能页面，因此未重复导出。
`;

await fs.writeFile(path.join(outputDir, "index.html"), indexHtml, "utf8");
await fs.writeFile(path.join(outputDir, "README.md"), readme, "utf8");

console.log(`已生成 ${pages.length} 张设计图的浏览索引。`);
