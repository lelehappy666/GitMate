import fs from "node:fs/promises";
import path from "node:path";

const root = process.cwd();
const sourceDir = path.join(
  root,
  ".superpowers/brainstorm/53164-1785202648/content",
);
const renderDir = path.join(root, "tmp/design-retina-html");

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

await fs.mkdir(renderDir, {recursive: true});

const retinaStyles = `
<style id="gitmate-retina-export">
  html {
    margin: 0 !important;
    padding: 0 !important;
    background: #eef2f6 !important;
  }
  body {
    margin: 0 !important;
    padding: 0 !important;
    overflow: hidden !important;
    background: #eef2f6 !important;
  }
  body > *:not(.app-window):not(.batch-entry):not(style) {
    display: none !important;
  }
  body > style { display: none !important; }
  body > .app-window,
  body > .batch-entry {
    display: none !important;
  }
  .page-meta,
  .change-summary,
  .state-strip,
  .specs,
  .decision,
  .options {
    display: none !important;
  }
  .app-window.retina-target {
    display: block !important;
    width: 1440px !important;
    height: 690px !important;
    min-height: 690px !important;
    margin: 0 !important;
    border-radius: 0 !important;
    box-shadow: none !important;
    transform: scale(2);
    transform-origin: 0 0;
  }
  .batch-entry.retina-target {
    display: block !important;
    width: 1440px !important;
    height: 680px !important;
    margin: 0 !important;
    transform: scale(2);
    transform-origin: 0 0;
  }
  .batch-entry > *:not(.batch-app) {
    display: none !important;
  }
  .batch-app {
    width: 1440px !important;
    height: 680px !important;
    margin: 0 !important;
    border-radius: 0 !important;
    box-shadow: none !important;
  }
</style>`;

const manifest = [];
for (let page = 1; page <= 91; page += 1) {
  const source = latestByPage.get(page);
  if (!source) {
    throw new Error(`缺少第 ${page} 页设计稿`);
  }

  const rawFragment = await fs.readFile(path.join(sourceDir, source.name), "utf8");
  const targetToken = page >= 30
    ? '<article class="batch-entry'
    : '<div class="app-window';
  const targetIndex = rawFragment.lastIndexOf(targetToken);
  if (targetIndex < 0) {
    throw new Error(`第 ${page} 页未找到软件窗口画板`);
  }
  const fragment = [
    rawFragment.slice(0, targetIndex),
    rawFragment
      .slice(targetIndex)
      .replace(targetToken, `${targetToken} retina-target`),
  ].join("");
  const outputName = `${String(page).padStart(2, "0")}-${source.slug}.html`;
  const document = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
</head>
<body>
${fragment}
${retinaStyles}
</body>
</html>
`;
  await fs.writeFile(path.join(renderDir, outputName), document, "utf8");
  manifest.push({
    page,
    slug: source.slug,
    version: source.version,
    html: outputName,
    image: `${String(page).padStart(2, "0")}-${source.slug}.png`,
    height: page >= 30 ? 1360 : 1380,
  });
}

await fs.copyFile(
  path.join(sourceDir, "page-01-welcome-bg-v1.png"),
  path.join(renderDir, "page-01-welcome-bg-v1.png"),
);
await fs.writeFile(
  path.join(renderDir, "manifest.json"),
  JSON.stringify(manifest, null, 2),
  "utf8",
);

console.log(`已生成 ${manifest.length} 个 2× Retina 渲染页面。`);
