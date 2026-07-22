# Portfolio / Realizacje — how it works & how to maintain it

A filterable gallery of past work, added as a dedicated page in both languages.

## What was added

**New files**
- `realizacje.html` — Polish page ("Realizacje")
- `realizacje-en.html` — English page ("Portfolio")
- `portfolio-*.jpg` — 8 placeholder images (4:5 crop) to be swapped for real photos

**Modified files**
- `style.css` — appended a "PORTFOLIO / REALIZACJE" block (filters, grid, lightbox)
- `script.js` — added filtering + lightbox logic (placed *before* the contact-form early-return so it runs on this page)
- All 8 existing pages — added the Portfolio link to the top nav and the footer, in order **Home · Services · Portfolio · Contact**

## How to add a real photo

1. Save your photo into the site folder. Keeping the existing filenames (e.g. `portfolio-swetry-01.jpg`) means you just overwrite the placeholder — nothing else to change. A 4:5 (portrait) crop looks best; other ratios still work.
2. To add a *new* item, copy one gallery tile block and edit it. A tile looks like this:

```html
<button class="portfolio-item" data-category="swetry" data-caption="Cotton sweater — private-label production" aria-label="Enlarge: Cotton sweater">
    <img src="portfolio-swetry-01.jpg" alt="Cotton sweater" width="800" height="1000" loading="lazy">
    <span class="portfolio-caption">Cotton sweater</span>
</button>
```

- `data-category` — which filter it belongs to (see categories below). **Must match** one of the filter buttons.
- `data-caption` — the text shown in the enlarged (lightbox) view.
- `<span class="portfolio-caption">` — the short label shown on the card itself (on hover / always on mobile).
- `alt` — a plain description of the photo, for accessibility.

## Photo-only tiles (no caption)

Captions are optional. For a tile that should show just the photo, delete both the `data-caption` attribute and the `<span class="portfolio-caption">` line. The third tile on each page is left this way as a working example.

## Categories

Filters are driven by the buttons at the top of the page. Current set:

| Filter button (PL / EN)      | `data-category` / `data-filter` value |
|------------------------------|----------------------------------------|
| Wszystkie / All              | `all`                                  |
| Swetry / Sweaters            | `swetry`                               |
| Kardigany / Cardigans        | `kardigany`                            |
| Sukienki / Dresses           | `sukienki`                             |
| Akcesoria / Accessories      | `akcesoria`                            |

The internal values (`swetry`, `kardigany`, …) are shared across both languages, so only the visible button label differs between PL and EN. To rename a category, change the button text. To add one, add a new `<button class="filter-btn" data-filter="NEW">…</button>` and give tiles the matching `data-category="NEW"`. If a category ends up with no items, the page shows a "no items in this category" message automatically.

## Behavior notes

- Clicking a tile opens a lightbox; navigate with the on-screen arrows or the ← / → keys, close with ✕, the Esc key, or by clicking the dark background.
- The lightbox steps through only the *currently filtered* set.
- Fully responsive: 3 columns on desktop, 2 on tablet, 1 on phone (where captions stay visible since there's no hover).
