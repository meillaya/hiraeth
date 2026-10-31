import { chromium } from "playwright";
import { mkdir, writeFile } from "node:fs/promises";

const base = process.argv[2];
if (!base) {
  console.error("usage: node live_screenshots.mjs <base-url>");
  process.exit(1);
}

const outDir = "docs/screenshots";
await mkdir(outDir, { recursive: true });

async function api(path) {
  const response = await fetch(new URL(path, base));
  if (!response.ok) {
    throw new Error(`${path} returned ${response.status}`);
  }
  return response.json();
}

const books = await api("/api/v1/books?page_size=24");
const publishers = await api("/api/v1/publishers?page_size=40");
const series = await api("/api/v1/series?page_size=40");

const displayableBook = books.data?.find(
  (book) => book.cover && !/placeholder|coming.?soon/i.test(book.cover.source_url || "")
);
const bookSlug =
  books.data?.find((book) => book.slug === "deep-vellum-carcasse")?.slug ||
  displayableBook?.slug ||
  books.data?.[0]?.slug;

const pressSlug =
  publishers.data?.find((publisher) => publisher.slug === "coffee-house-press")?.slug ||
  publishers.data?.[0]?.slug;

const collectionSlug =
  series.data?.find((collection) => collection.slug === "dalkey-archive-essentials")?.slug ||
  series.data?.[0]?.slug;

if (!bookSlug || !pressSlug || !collectionSlug) {
  throw new Error("catalog API returned incomplete records; seed the database first");
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
  ["book", `/books/${bookSlug}`, "#book-detail-shell"],
  ["publishers", "/publishers", "#publishers-shell"],
  ["press", `/publishers/${pressSlug}`, "#publisher-detail-shell"],
  ["collections", "/series", "#series-shell"],
  ["collection", `/series/${collectionSlug}`, "#series-detail-shell"],
  ["contributors", "/contributors", "#contributors-shell"],
  ["search", "/search?q=the", "#search-shell"],
];

const routes = {};

for (const [name, path, selector] of shots) {
  await page.goto(new URL(path, base).href, { waitUntil: "domcontentloaded" });
  await page.waitForSelector(selector, { timeout: 30_000 });
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(1200);
  await page.screenshot({ path: `${outDir}/softbound-${name}.png`, fullPage: false });
  routes[name] = path;
  console.log(`captured ${name} ${path}`);
}

await writeFile(`${outDir}/routes.json`, JSON.stringify(routes, null, 2) + "\n");
await browser.close();
