---
name: "roblox-monetization"
description: "Monetize a Roblox game end to end without clicking through Creator Hub: picks the game passes and developer products (Starter Pack, 2x Cash, +25% Size, VIP, server events...), sets Robux prices, generates their icons (codex-image / any image tool, or placeholder art), creates and updates them through the Roblox Open Cloud API with the API key from an environment variable, and writes the IDs into a Luau module that the game's MonetizationService (ProcessReceipt grants, pass perks, multipliers) and ShopController (purchase prompts, live prices, shop grid, purchase popup) read. Use whenever someone wants to add or change game passes, developer products, a shop, Robux prices or monetization in their Roblox game, mentions Open Cloud API keys, MarketplaceService or ProcessReceipt, or says 'zmonetyzuj grę', 'dodaj gamepassy', 'zrób dev producty', 'sklep za robuxy'."
---

# Roblox Monetization

Goal: one command takes the game from "no store" to working, priced, illustrated game passes and developer products that are wired into the game's code, and running it again only changes what changed. Nothing is clicked in Creator Hub except creating the API key once.

Answer in the user's language; write code, identifiers, item names and descriptions in English unless the game targets another language.

## 1. Setup (once per experience)
Check `ROBLOX_API_KEY` (environment or a `.env` that git ignores) and the universe ID before anything else. If either is missing, give the user these steps and wait:

1. [create.roblox.com](https://create.roblox.com) > **All tools** > **Open Cloud** > **API Keys** > **Create API Key**.
2. Access permissions: add **game-passes** and **developer-products**, pick the experience, tick **read** and **write** for both. Optional: IP allowlist and an expiration date.
3. **Save & Generate Key**, then store it outside the code:
   - `.env` next to `monetization.json`: `ROBLOX_API_KEY=...` and make sure `.gitignore` has `.env`, or
   - an environment variable (`setx ROBLOX_API_KEY "..."` on Windows, `export ROBLOX_API_KEY=...` in `~/.zshrc`/`~/.bashrc`).
4. Universe ID: Creator Hub > the experience > `...` > **Copy Universe ID** (not the place ID), into `"universeId"` in the manifest or `ROBLOX_UNIVERSE_ID`.

Never ask for the key in the chat, never echo it, never write it into a file you create, a commit, or Luau (a key in a game script would ship to every server and leak). If the user pastes a key anyway, don't repeat it: tell them to revoke it in Creator Hub and make a new one. `monetize.py` only reads the key from the environment or `.env` and never prints it.

## 2. Catalog: `monetization.json`
Start from `assets/monetization.example.json` (copy it to the game's project root). Pick items from the game's production plan (`PRODUCTION_PLAN.md`, monetization tasks) or its core loop; read `references/catalog.md` for what to sell, price ladders and the grant types. For each item:

| Field | Meaning |
| --- | --- |
| `key` | PascalCase Luau name used in code (`DoubleCash`). Never rename after the first sync. |
| `kind` | `pass` (bought once: perks, multipliers, VIP) or `product` (bought again: currency, boosts, server events) |
| `name`, `description` | What players see in the prompt (name ≤ 50 characters) |
| `price` | Robux, whole number. `managedPricing: true` lets Roblox optimize it per region. |
| `grant` | `currency` {field, amount} or `handler` for products; `multiplier` {stat, value} or `perk` for passes |
| `icon`, `iconPrompt` | Icon file (default `icons/<key>.png`) and what to draw |
| `forSale` | `false` takes it off sale (Open Cloud cannot delete items) |

Show the user the catalog as a table (item, kind, price, what it gives) and get a yes before the first sync: it creates real store items.

## 3. Icons
1. `python3 <skill>/scripts/monetize.py prompts` writes `icons/prompts.json` (one prompt per item, output path, size; pass prompts keep the art inside a circle because Roblox crops pass icons round).
2. Generate the images with the best tool available, in this order:
   - a `codex-image` skill (plugin `codex-image-in-cc`: `/codex-image:batch` with the prompts file, or `/codex-image` per item); it uses the user's ChatGPT/Codex login. If it is not installed and the user wants it: `claude plugin marketplace add KingOfGaming/codex-image-in-cc` then `claude plugin install codex-image@codex-image-in-cc` (needs Node 18.18+ and `@openai/codex`).
   - any other image generation tool or MCP server the session has;
   - otherwise `monetize.py icons --placeholder`: clean gradient badges with the item's label (`2x`, `+25%`, `5K`) so the store works today; real art can replace the files later and the next sync re-uploads only the changed icons.
3. `monetize.py check` validates the manifest and every icon (format, square, at least 512 px, not flat, pass art not in the corners). Fix every error; mention warnings.

## 4. Sync with Roblox
```
python3 <skill>/scripts/monetize.py sync --dry-run   # what would be created/updated
python3 <skill>/scripts/monetize.py sync
```
- Creates missing items (multipart POST with name, description, price, sale flags and the 512x512 PNG icon), PATCHes only changed fields, re-uploads an icon only when its image changed, adopts items that already exist with the exact same name instead of duplicating them, and recreates items deleted in Creator Hub.
- Writes `monetization.lock.json` (IDs, icon asset IDs, icon hashes: commit it, it holds no secrets) after every item, so a crash never loses an ID, and then `src/shared/Monetization.luau` (`luauOutput`). `monetize.py luau` rewrites the module from the lock without calling Roblox.
- Errors explain themselves (401 bad key, 403 missing permission or experience not on the key, 400 rejected field, rate limits are retried). API details: `references/open-cloud.md`.

## 5. Wire it into the game
Works on the `roblox-luau-codegen` template (scaffold it first if the project has no structure; otherwise adapt the two modules to the project's own purchase handling and keep exactly one `ProcessReceipt`).

1. Copy `assets/MonetizationService.luau` to `src/server/Services/` and `assets/ShopController.luau` to `src/client/Controllers/`. Read both headers: they are the API.
2. Add `"PurchaseResult"` to `Net.Events` in `src/shared/Net.luau`.
3. Every `currency` grant field must exist as a number in `Config.DefaultData`.
4. Use the perks where the game computes them, on the server:
   - `Cash += base * MonetizationService.Multiplier(player, "Cash")`
   - `scale = baseScale * MonetizationService.Multiplier(player, "Size")` (e.g. `Humanoid.BodyHeightScale.Value`)
   - `if MonetizationService.Owns(player, "VIP") then ... end`, `MonetizationService.OnPass("VIP", fn)` for instant effects after buying.
   - `handler` products: `MonetizationService.OnProduct("ServerEvent", function(player, data) ... end)` in some service's `Init`; change only `data`, start world effects with `task.defer`. Until a handler exists the receipt stays unprocessed and Roblox retries it, so nothing is lost.
5. Shop UI: bind the buttons from the game's own UI (`roblox-ui-designer`) with `ShopController.Bind(button, "DoubleCash", priceLabel)`, or call `ShopController.Build(frame)` for a ready grid. Prices always come from `GetPrice` (MarketplaceService), never typed into the UI. The purchase popup appears after the server granted the purchase; turn it off with `ShopController.ShowPopup = false` if the UI has its own, and hook `ShopController.OnPurchased`.
6. Log economy analytics for currency grants as in `references/patterns.md` of `roblox-luau-codegen` (source `IAP`, SKU = item key).

## 6. Verify
1. `monetize.py check` clean, `sync` reports every item OK on a second run (0 created, 0 updated).
2. `scripts/check.sh` of `roblox-luau-codegen` on the project (StyLua + Selene), and the `roblox-security-perf-audit` scanner on the new code if it is installed.
3. With Studio MCP tools: playtest, buy each item (test purchases in Studio are free and still run `ProcessReceipt`), confirm the grant, the popup, the multiplier and that a rejoin keeps products and passes. Without Studio: give the user that list as manual steps.
Never claim purchases work in the game unless a playtest ran.

## 7. Report
- The catalog table with IDs; they are also visible in Creator Hub > the experience > Monetization > Passes / Developer Products.
- Files created or changed, what was verified and what was not.
- What the team still has to do: real icons if placeholders were used, `OnProduct` handlers they own, publishing the place so the new IDs reach live servers.
