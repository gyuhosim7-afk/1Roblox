// Screenshots an HTML file with the preinstalled Chromium.
// Usage: node tools/screenshot.js <in.html> <out.png> <width> <height>
const path = require("path");
let playwright;
try {
  playwright = require("playwright");
} catch (e) {
  playwright = require("/opt/node-tools/node_modules/playwright");
}

(async () => {
  const [input, output, width, height] = process.argv.slice(2);
  const browser = await playwright.chromium.launch();
  const page = await browser.newPage({ viewport: { width: Number(width), height: Number(height) } });
  await page.goto("file://" + path.resolve(input));
  await page.waitForTimeout(150);
  await page.screenshot({ path: output });
  await browser.close();
})();
