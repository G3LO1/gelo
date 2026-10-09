---
name: "roblox-security-perf-audit"
description: "Audit an existing Roblox game for security holes and performance problems: exploitable remotes (client-sent prices/damage, missing validation and rate limits), Toolbox backdoors (require(id), getfenv, loadstring, webhooks, hidden code), data-loss and duplication risks (SetAsync, no session lock, multiple ProcessReceipt), hard-coded Robux prices that break Managed Pricing, and lag sources (loops without yields, per-frame allocations, unanchored parts, precise collisions, shadow lights, particle rates, NPC humanoids, no streaming). Runs a static Luau scanner and a place audit (in Studio or on .rbxl/.rbxm files), then gives a prioritized fix list and patches. Use whenever someone asks to check, audit, review or secure their Roblox game or scripts, mentions exploiters, hackers, backdoors, viruses in free models, data loss, duplication, lag, low FPS, memory or crashes on phones, or says 'sprawdź grę', 'czy mój kod jest bezpieczny', 'gra laguje', 'wirus w modelu'."
---

# Roblox Security & Performance Audit

Goal: find what will actually hurt the game in production (exploiters, backdoors, lost or duplicated data, lag on phones) and fix it in order of damage, with proof. Scanners find candidates fast; a human-style review of the remotes and a measurement on a real device decide what is real.

Answer in the user's language; rule IDs, code and identifiers stay in English.

## 1. Scope
Find out, from the conversation or with one AskUserQuestion round (multiple choice, recommended first), only what is missing:
- What to audit: code on disk (Rojo project), a place in Studio (Roblox Studio MCP connected), a `.rbxl/.rbxlx/.rbxm/.rbxmx` file, or a single script pasted in chat.
- The symptom, if any: exploiters doing X, data loss/duplication, lag (where, on which devices), memory crashes, a suspicious free model. A symptom narrows the audit; without one, run everything.
- Whether you may change code or only report. Default: report first, then patch what the user approves.

## 2. Run the scanners
Both are read-only and live in `scripts/`.

**Code** (any folder of `.lua/.luau`, or `.rbxmx/.rbxlx` files):
```
python3 scripts/scan_luau.py <src-or-files> [--json findings.json] [--fail-on high|medium|low|none]
```
22 rules (`SEC-*`, `DATA-*`, `PURCHASE-*`, `PRICE-*`, `PERF-*`); each finding has a severity, file:line, server/client context and the reason. Context comes from file names (`.server.luau`, `.client.luau`), folders (`server`, `ServerScriptService`, `client`, `StarterPlayer`...) or the script class in XML.

**Place** (instances, settings, and every script's source):
- In Studio with MCP: `list_roblox_studios`, confirm the place, then run the whole of `scripts/audit_studio.luau` with `execute_luau` (Edit mode is fine). It prints the report and returns it.
- On a file: `lune run scripts/audit_place.luau <file> [--dump-scripts <dir>] [--json report.json] [--fail-on ...]`. Use `--dump-scripts` and run `scan_luau.py` on the dump to scan binary places' code too. Rojo project: `rojo build -o place.rbxl` first. Lune can't read `CollisionFidelity` back from saved files; the report lists those meshes under `collisionFidelityUnreadable` (check them in Studio).
- No Studio, no file: ask the user to save the place (File > Save to File As) or to run `audit_studio.luau` in the Command Bar and paste the output.

The place audit checks: backdoor patterns in any script, scripts inside Workspace models, LoadStringEnabled, loose unanchored parts, precise collisions, tiny collidable decor, small shadow casters, semi-transparent overdraw, shadow-casting lights, particle rates (400/s cap, 100/s on phones) and total particle budget, lifetimes over the 20 s cap, NPC humanoid count, unique meshes, oversized models, streaming off on big maps, character cleanup, stacked post-processing.

Treat every finding as a lead: open the code or instance and confirm it before reporting it as a problem. Thresholds are in `Audit.Thresholds` at the top of `audit_studio.luau`; adjust them for the game (an NPC horde game expects more humanoids) and say so.

## 3. Review what scanners can't see
Read `references/security.md` and do at least:
1. **Remote inventory**: a table of every remote with its arguments, server checks, rate limit and verdict (OK / FIX / CRITICAL). CRITICAL = the client decides an outcome (currency, damage, rewards, ownership, other players' state).
2. **Trust boundaries**: movement and physics ownership for anything competitive, Touched handlers, admin commands (UserId on the server).
3. **Data and purchases**: session locking, BindToClose, one idempotent ProcessReceipt, prices from MarketplaceService.
4. **Toolbox and plugins**: for every model with scripts, read the scripts; for backdoors follow the clean-up steps (remove, search the whole place again, sandbox what stays, rotate keys).

For performance, read `references/performance.md`. If Studio is connected, playtest (`start_stop_play`) and read `get_console_output`; otherwise give the user the measurement steps (Developer Console memory, MicroProfiler on the densest view, Scene Analysis, a real low-end phone). Never claim the game runs well on phones without a measurement.

## 4. Fix
- Order: CRITICAL security and backdoors -> data loss/duplication -> purchases -> high performance issues (freezes, crashes) -> medium -> low.
- Patch with the smallest change that removes the cause; reuse the project's own validation layer. In projects built with `roblox-luau-codegen`, use `Net` schemas + `Guard` validators and `DataService.Update` instead of hand-rolled checks.
- Never delete or rewrite the user's scripts or models without saying exactly what and why and getting a yes; for Toolbox backdoors, show the offending lines first.
- After fixing, run the same scanners again and show the before/after counts; re-run the playtest when Studio is connected.

## 5. Report
1. Verdict in one line (e.g. "2 critical exploits, 1 backdoor, lag from 3 emitters; fixable in a day").
2. Findings table: severity, where (file:line or instance path), what goes wrong in production (one sentence a non-programmer understands), fix, status (fixed / proposed / needs a human).
3. Remote inventory table.
4. What was verified (scanners, playtest, device) and what was not.
5. Manual steps: Studio settings (LoadStringEnabled, HTTP, API access, third-party teleports/sales), sandboxing models, testing on a real phone, rotating keys after a backdoor.

## Hand-off
Offer `roblox-luau-codegen` to rebuild a broken system on the tested template (session-locked data, idempotent purchases, validated remotes), and `roblox-map-builder` to rebuild heavy map areas with a modular kit and streaming.
