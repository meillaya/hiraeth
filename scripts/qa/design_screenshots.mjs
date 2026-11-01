// Hiraeth responsive QA: captures every public surface at the nine
// acceptance widths and asserts the layout contract (no horizontal overflow,
// sheet inset by band, header mode by breakpoint). Usage:
//
//   node scripts/qa/design_screenshots.mjs http://127.0.0.1:4000 [outDir]
//
import { chromium } from "playwright";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const base = process.argv[2];
const outDir = process.argv[3] || "artifacts/qa/design";

if (!base) {
  console.error("usage: node scripts/qa/design_screenshots.mjs <base-url> [outDir]");
  process.exit(2);
}

const widths = [390, 560, 760, 834, 900, 1040, 1180, 1280, 1440];
const pages = [
  ["home", "/"],
  ["browse", "/browse"],
  ["publishers", "/publishers"],
  ["series", "/series"],
  ["contributors", "/contributors"],
  ["search", "/search?q=the"]
];

const booksResponse = await fetch(new URL("/api/v1/books?page_size=1", base));
if (booksResponse.ok) {
  const payload = await booksResponse.json();
  const slug = payload.data?.[0]?.slug;
  if (slug) pages.push(["book", `/books/${slug}`]);
}

const publishersResponse = await fetch(new URL("/api/v1/publishers?page_size=1", base));
if (publishersResponse.ok) {
  const payload = await publishersResponse.json();
  const slug = payload.data?.[0]?.slug;
  if (slug) pages.push(["press", `/publishers/${slug}`]);
}

const seriesResponse = await fetch(new URL("/api/v1/series?page_size=1", base));
if (seriesResponse.ok) {
  const payload = await seriesResponse.json();
  const slug = payload.data?.[0]?.slug;
  if (slug) pages.push(["collection", `/series/${slug}`]);
}

await mkdir(outDir, { recursive: true });
const browser = await chromium.launch();
const report = [];
const failures = [];

for (const [name, route] of pages) {
  for (const width of widths) {
    const page = await browser.newPage({
      viewport: { width, height: 900 },
      deviceScaleFactor: 1
    });

    try {
      const response = await page.goto(new URL(route, base).href, {
        waitUntil: "networkidle",
        timeout: 45_000
      });

      if (!response || response.status() >= 400) {
        failures.push({ page: name, width, problem: `HTTP ${response?.status()}` });
        continue;
      }

      await page.evaluate(() => document.fonts.ready);
      await page.waitForTimeout(200);

      const metrics = await page.evaluate(() => {
        const sheet = document.querySelector(".sb-sheet");
        const nav = document.querySelector(".sb-nav");
        const menu = document.querySelector(".sb-tool--menu");
        const style = sheet ? getComputedStyle(sheet) : null;
        return {
          scrollWidth: document.documentElement.scrollWidth,
          innerWidth: window.innerWidth,
          sheetWidth: sheet ? sheet.getBoundingClientRect().width : null,
          sheetMargin: style ? parseFloat(style.marginLeft) : null,
          navDisplay: nav ? getComputedStyle(nav).display : null,
          menuDisplay: menu ? getComputedStyle(menu).display : null
        };
      });

      const inset = width <= 560 ? 6 : width <= 760 ? 8 : 18;
      const expectedSheet = Math.min(width - inset * 2, 1640);

      if (metrics.scrollWidth > metrics.innerWidth + 1) {
        failures.push({ page: name, width, problem: "horizontal overflow" });
      }

      if (metrics.sheetWidth && Math.abs(metrics.sheetWidth - expectedSheet) > 1.5) {
        failures.push({
          page: name,
          width,
          problem: `sheet width ${metrics.sheetWidth.toFixed(1)} != ${expectedSheet}`
        });
      }

      if (metrics.sheetMargin !== null && Math.abs(metrics.sheetMargin - inset) > 1.5) {
        failures.push({
          page: name,
          width,
          problem: `sheet inset ${metrics.sheetMargin} != ${inset}`
        });
      }

      if (width <= 1040 && metrics.navDisplay !== "none") {
        failures.push({ page: name, width, problem: "desktop nav visible below 1041px" });
      }

      if (width > 1040 && metrics.menuDisplay !== "none") {
        failures.push({ page: name, width, problem: "menu button visible above 1040px" });
      }

      const file = path.join(outDir, `${name}-${width}.png`);
      await page.screenshot({ path: file, fullPage: false });
      report.push({ page: name, width, route, screenshot: file, ...metrics });
    } catch (error) {
      failures.push({ page: name, width, problem: error.message });
    } finally {
      await page.close();
    }
  }
}

await browser.close();
await writeFile(path.join(outDir, "report.json"), JSON.stringify({ report, failures }, null, 2));

console.log(`captured ${report.length} frames in ${outDir}`);
if (failures.length > 0) {
  console.error(JSON.stringify(failures, null, 2));
  process.exit(1);
}
console.log("layout contract: PASS");
