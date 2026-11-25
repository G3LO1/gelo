// Opens the components preview in Chromium at desktop (1920x1080) and landscape phone (844x390)
// and measures the rendered Button / ItemCard elements: big enough for a thumb, inside the safe
// area, not overlapping, states visibly different (focused bigger, pressed smaller, disabled
// dimmer), 9-slice layers drawn as 9-slice. Writes screenshots next to the HTML.
// Usage: node preview_check.js <preview.html> <screen> [out-dir]   (needs the playwright package)
const path = require("path");
const { chromium } = require("playwright");

const [html, screen, outDir] = process.argv.slice(2);
const MIN_TOUCH = 44; // px on a phone screen
const TOP_BAR = { 1080: 58, 390: 44 };
let failed = 0;
const ok = (cond, msg) => { console.log(`  ${cond ? "ok  " : "FAIL"} ${msg}`); if (!cond) failed++; };

(async () => {
  const browser = await chromium.launch();
  for (const [w, h] of [[1920, 1080], [844, 390]]) {
    const page = await browser.newPage({ viewport: { width: w, height: h } });
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.goto(`file://${path.resolve(html)}?screen=${screen}&w=${w}&h=${h}`);
    await page.waitForTimeout(300);
    if (outDir) await page.screenshot({ path: path.join(outDir, `${screen}-${w}x${h}.png`) });
    const items = await page.$$eval("[data-tags]", (els) => els
      .filter((e) => /\b(Button|ItemCard)\b/.test(e.dataset.tags))
      .map((e) => {
        const r = e.getBoundingClientRect();
        const label = e.querySelector('[data-name="Label"] .txt, [data-name="NameLabel"] .txt');
        return { name: e.dataset.name, kind: /ItemCard/.test(e.dataset.tags) ? "ItemCard" : "Button",
          x: r.x, y: r.y, w: r.width, h: r.height,
          sliced: [...e.querySelectorAll('[data-name="Base"] [data-slice], [data-name="Glass"] [data-slice]')].length,
          textAlpha: label ? parseFloat(getComputedStyle(label).color.split(",")[3] || "1") : 1 };
      }));
    const tag = `${w}x${h}`;
    ok(errors.length === 0, `${tag}: no page errors ${errors.join("; ")}`);
    ok(items.length === 8, `${tag}: 4 Buttons and 4 ItemCards rendered (${items.length})`);
    const small = items.filter((i) => Math.min(i.w, i.h) < MIN_TOUCH);
    ok(small.length === 0, `${tag}: every component >= ${MIN_TOUCH} px on both sides (smallest ${Math.round(Math.min(...items.map((i) => Math.min(i.w, i.h))))} px)`);
    const outside = items.filter((i) => i.x < 0 || i.y < TOP_BAR[h] || i.x + i.w > w || i.y + i.h > h);
    ok(outside.length === 0, `${tag}: inside the screen and below the Roblox top bar ${outside.map((i) => i.name).join(" ")}`);
    let overlaps = [];
    for (const a of items) for (const b of items) if (a.name < b.name && a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h) overlaps.push(`${a.name}/${b.name}`);
    ok(overlaps.length === 0, `${tag}: no overlapping components ${overlaps.join(" ")}`);
    for (const kind of ["Button", "ItemCard"]) {
      const s = Object.fromEntries(items.filter((i) => i.kind === kind).map((i) => [i.name.replace(kind, ""), i]));
      ok(s.Focused.w > s.Default.w && s.Pressed.w < s.Default.w, `${tag}: ${kind} focused grows, pressed shrinks (${Math.round(s.Pressed.w)} < ${Math.round(s.Default.w)} < ${Math.round(s.Focused.w)})`);
      ok(s.Disabled.textAlpha < s.Default.textAlpha, `${tag}: ${kind} disabled text is dimmed (${s.Disabled.textAlpha})`);
      ok(items.filter((i) => i.kind === kind).every((i) => i.sliced === 1), `${tag}: ${kind} base layer drawn as 9-slice`);
    }
    await page.close();
  }
  await browser.close();
  console.log(failed ? `${failed} check(s) failed` : "preview checks passed");
  process.exit(failed ? 1 : 0);
})();
