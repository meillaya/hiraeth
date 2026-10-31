import { chromium } from "playwright";
import { mkdir } from "node:fs/promises";

const base = process.argv[2];
if (!base) {
  console.error("usage: node live_screenshots.mjs <base-url>");
  process.exit(1);
}

const outDir = "docs/screenshots";
await mkdir(outDir, { recursive: true });

const booksResponse = await fetch(new URL("/api/v1/books?page_size=1", base));
if (!booksResponse.ok) {
  throw new Error(`book API returned ${booksResponse.status}`);
}
const books = await booksResponse.json();
const slug = books.data?.[0]?.slug;
if (!slug) {
  throw new Error("catalog API returned no books; seed the database first");
}

const browser = await chromium.launch();
const page = await browser.newPage({
  viewport: { width: 1440, height: 1000 },
  deviceScaleFactor: 1,
});
await page.emulateMedia({ colorScheme: "light" });

const shots = [
  ["home", "/", "#home-shell"],
  ["browse", "/browse", "#browse-shell"],
  ["publishers", "/publishers", "main"],
  ["book", `/books/${slug}`, "#book-detail-shell"],
];

for (const [name, path, selector] of shots) {
  await page.goto(new URL(path, base).href, { waitUntil: "domcontentloaded" });
  await page.waitForSelector(selector, { timeout: 30_000 });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(1200);
  await page.screenshot({ path: `${outDir}/${name}.png`, fullPage: false });
  console.log(`captured ${name} ${path}`);
}

await browser.close();
