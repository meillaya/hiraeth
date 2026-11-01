// Hiraeth accessibility QA: runs axe-core against every public surface at a
// mobile and a desktop width and fails on serious or critical WCAG A/AA
// violations. Usage:
//
//   node scripts/qa/accessibility_screenshots.mjs http://127.0.0.1:4000 [outDir]
//
import AxeBuilder from "@axe-core/playwright";
import { chromium } from "playwright";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const base = process.argv[2];
const outDir = process.argv[3] || "artifacts/qa/accessibility";

if (!base) {
  console.error(
    "usage: node scripts/qa/accessibility_screenshots.mjs <base-url> [outDir]"
  );
  process.exit(2);
}

const widths = [390, 1440];
const routes = [
  ["home", "/"],
  ["browse", "/browse"],
  ["publishers", "/publishers"],
  ["series", "/series"],
  ["contributors", "/contributors"],
  ["search", "/search?q=the"]
];

async function addFirstSlug(route, apiPath, name) {
  try {
    const response = await fetch(new URL(apiPath, base));
    if (!response.ok) return;
    const payload = await response.json();
    const slug = payload.data?.[0]?.slug;
    if (slug) routes.push([name, route(slug)]);
  } catch {
    // A missing endpoint is a visual-run concern, not an accessibility failure.
  }
}

await addFirstSlug((slug) => `/books/${slug}`, "/api/v1/books?page_size=1", "book");
await addFirstSlug(
  (slug) => `/publishers/${slug}`,
  "/api/v1/publishers?page_size=1",
  "press"
);
await addFirstSlug(
  (slug) => `/series/${slug}`,
  "/api/v1/series?page_size=1",
  "collection"
);

await mkdir(outDir, { recursive: true });

const browser = await chromium.launch();
const report = [];
const failures = [];

for (const [name, route] of routes) {
  for (const width of widths) {
    const context = await browser.newContext({
      viewport: { width, height: 900 },
      deviceScaleFactor: 1
    });
    const page = await context.newPage();

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

      const results = await new AxeBuilder({ page })
        .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
        .analyze();

      const violations = results.violations.map((violation) => ({
        id: violation.id,
        impact: violation.impact,
        help: violation.help,
        nodes: violation.nodes.map((node) => ({
          target: node.target,
          summary: node.failureSummary
        }))
      }));

      const blocking = violations.filter(
        (violation) => violation.impact === "serious" || violation.impact === "critical"
      );

      report.push({ page: name, width, route, violations });

      for (const violation of blocking) {
        failures.push({
          page: name,
          width,
          problem: `${violation.impact}: ${violation.id} (${violation.nodes.length} node(s))`
        });
      }
    } catch (error) {
      failures.push({ page: name, width, problem: error.message });
    } finally {
      await context.close();
    }
  }
}

await browser.close();

await writeFile(
  path.join(outDir, "report.json"),
  JSON.stringify({ report, failures }, null, 2)
);

console.log(`checked ${report.length} page/width frames in ${outDir}`);
if (failures.length > 0) {
  console.error(JSON.stringify(failures, null, 2));
  process.exit(1);
}
console.log("accessibility contract: PASS");
