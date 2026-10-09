---
name: "roblox-luau-codegen"
description: "Write production-ready Roblox Luau code from a game's production plan (PRODUCTION_PLAN.md / tasks.csv) or a feature description: Rojo project skeleton, session-locked player data, idempotent purchases, validated and rate-limited remotes, and the game's own systems (rounds, currency, shop, inventory, combat, NPCs, placement, leaderboards, codes, UI controllers), checked with StyLua/Selene and playtested when Studio is connected. Use whenever someone wants to code, script or implement their Roblox game or a system from the plan, asks for Luau/Lua scripts for Roblox Studio, or says 'napisz kod', 'zrób skrypty', 'zaimplementuj system', even if they don't mention the plan."
---

# Roblox Luau Codegen

Goal: code that keeps working on a live server full of exploiters, phones and DataStore hiccups, not just in a Studio playtest, and that is structured so the team can keep building on it. The two things that destroy Roblox games after launch are lost/duplicated data and exploitable remotes, so those come from a tested template instead of being rewritten each time.

Answer in the user's language; write code, identifiers and code comments in English.

## 1. Inputs
- Look for `PRODUCTION_PLAN.md` / `tasks.csv` in the project (from the `roblox-game-production-plan` skill) and use its task IDs, data fields, products and analytics events. Without a plan, work from the conversation; for a single small script, skip the plan entirely.
- Scope: by default the scripting, data, monetization and analytics tasks of the current milestone (MVP first). State the task list you will implement in one line and continue; ask only if the scope is unclear.
- Delivery, ask once with AskUserQuestion if it is not obvious:
  1. **Rojo project on disk** (default when working in a folder or repo): files under `src/`, synced to Studio with Rojo.
  2. **Straight into Studio** when Roblox Studio MCP tools are connected: same hierarchy, created with the Studio tools (`list_roblox_studios` first, confirm the place).
  3. **Paste-ready**: every file with its exact Studio location and script type.

## 2. Scaffold (once per project)
Copy `assets/template/` into the project root. Never overwrite existing files; if the project already has its own structure, adapt the template modules into it instead of forcing the layout.

| File (Studio location) | Role |
| --- | --- |
| `default.project.json` | Rojo mapping below |
| `src/shared` -> ReplicatedStorage.Shared | `Config` (data defaults, product/pass IDs), `Net` (all remotes, validation, rate limits), `Guard` (validators) |
| `src/server/init.server.luau` -> ServerScriptService.Server (Script) | Boots every module in `Services`: `Init()` then `Start()` |
| `src/server/Services/DataService.luau` | Session-locked DataStore profiles, autosave, BindToClose, migrations, Studio mock |
| `src/server/Services/PurchaseService.luau` | Idempotent `ProcessReceipt`, pass ownership cache |
| `src/client/init.client.luau` -> StarterPlayerScripts.Client (LocalScript) | Boots every module in `Controllers` |
| `src/client/Controllers/DataController.luau` | Read-only synced copy of the player's data for UI |
| `selene.toml`, `stylua.toml` | Lint and format config |

Read the template files before extending them: their public functions are the contract every new system uses. The template and `references/patterns.md` were tested (session locking, purchases, remotes) and their Roblox API calls checked against current docs: don't "correct" them from memory. If something there looks wrong, keep it and raise it in the report. Then fill `Config.DefaultData` from the plan's data (currencies, inventory, progression, settings, timestamps) and put products/passes from the plan into `Config.Products` / `Config.Passes` with ID `0` and a `-- TODO: paste ID from Creator Hub` comment.

## 3. Write the systems
Read `references/patterns.md` before writing systems: it holds the coding rules, ready patterns (currency + analytics, shop, cooldowns, hit validation, rounds, placement, NPC pathfinding, leaderboards, codes, daily rewards, text filtering, PolicyService, animations, UI controllers) and the security checklist.

- Server logic: `src/server/Services/<Name>Service.luau`; client: `src/client/Controllers/<Name>Controller.luau`; shared tuning/item tables: `src/shared/<Name>Data.luau`. Modules expose `Init()` (no yielding; only set up own state or register with another service, e.g. `PurchaseService.RegisterProduct`) and `Start()` (connect events, start loops, use other services).
- Start each module with a short header: which plan tasks it implements (`-- Plan: SYS-03, SYS-04`) and its public API.
- Remotes: add the name to `Net.Events` / `Net.Functions`, handle on the server with `Net.handle` / `Net.handleInvoke` and `Guard` validators for every argument; the client only sends intents (`Net.fire("BuyItem", itemId)`), never results.
- Persistent state only through `DataService.Update`; new fields go into `Config.DefaultData`; renames or type changes get a migration and a `Config.Data.Version` bump.
- Developer products: `PurchaseService.RegisterProduct` in a `MonetizationService`; pass perks through `PurchaseService.OwnsPass` and `OnPassPurchased`.
- Analytics events from the plan: economy events after every successful currency change, funnel steps for onboarding and shop.
- Stay inside the task scope. Leave a `TODO` only where the team must supply something (asset/animation/sound/product IDs, tuning numbers), and list those TODOs in the report.

## 4. Verify
1. Format the files you wrote (`stylua <files>`) and run `scripts/check.sh <project-root> src` (bundled: StyLua syntax/format + Selene lints, skips tools that are missing). Fix every error and every warning in your own code.
2. Review your diff as an exploiter and as a server outage, using the security checklist in `references/patterns.md`: garbage arguments, 1000 calls per second, another player's instance, NaN and negative numbers, server shutdown mid-save, double purchase.
3. With Studio MCP tools: sync or insert, playtest with `start_stop_play`, read `get_console_output`, and fix until the console is clean; test two players when possible. Without Studio, give the user a short manual test list (join, buy, rejoin, data kept, second device).
Never claim the game works in Studio unless a playtest actually ran.

## 5. Report
- Files created or changed, grouped by plan task ID.
- What was verified (checks, playtest) and what was not.
- Manual steps for the team: Game Settings > Security > Enable Studio Access to API Services (DataStores in Studio), create products/passes and paste IDs into `Config`, upload animations and sounds to the account or group that owns the experience and paste IDs, install Rojo (`rojo serve` + Studio plugin) if using files.
- Offer to mark the implemented tasks as done in `PRODUCTION_PLAN.md`.
