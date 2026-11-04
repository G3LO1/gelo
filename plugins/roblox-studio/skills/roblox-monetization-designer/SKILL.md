---
name: "roblox-monetization-designer"
description: "Design a Roblox game's monetization and economy: what to sell (game passes, developer products, subscriptions, private servers, rewarded ads), currencies with faucets and sinks, soft/premium split, time to first goal and grind walls, price ladders and currency packs, starter packs, where and when to prompt purchases, fair-play and kids-safe rules (pay-to-win, paid random items and odds, dark patterns), Managed Pricing and live price display, receipts and economy analytics, and a revenue scenario. Validates a monetization.json with a script and generates the Luau Products catalog module (ids, default prices, live GetPrice). Use whenever someone asks how to earn Robux from a game, what to put in the shop, how to price passes or currency packs, how to balance coins/gems, why nobody buys, or says 'monetyzacja', 'co sprzedawać w grze', 'ceny gamepassów', 'ekonomia w grze', 'jak zarobić na robloxie', 'sklep w grze'."
---

# Roblox Monetization Designer

Goal: a shop and economy that earns Robux because players are happy, not because they are cornered. On Roblox, retention drives both ranking and revenue (Creator Rewards pay for 10+ minute sessions), so every sale must leave the free game better to play, not worse.

Answer in the user's language; item names and UI copy in the languages the game targets (English first unless told otherwise).

Read `references/monetization.md` every time: it holds the design rules, heuristics and platform facts.

## 1. Inputs
Take what is known from the conversation, `PRODUCTION_PLAN.md` (monetization and economy tasks, currencies, data fields), an idea-validator report or the code (`Config`, shop controllers). Ask once with AskUserQuestion (multiple choice, recommended option first) only what is missing:
- Audience: all ages (Kids/Select) / 13+ / 17+. It decides what pressure tactics and random items are allowed.
- Game type: solo/co-op PvE or PvP (power sold in PvP is pay-to-win); session length; round-based or persistent progression.
- Currencies already in the design and what the player does per hour that earns and spends them.
- Stage: nothing built yet / shop exists but nobody buys (ask for conversion, ARPDAU, first-purchase time, DAU) / reworking an economy that inflated.
- Ambition: side income vs real business (sets how many products and how much live-ops).

## 2. Economy first
Before any price, write down per currency: faucets and sinks in units per hour of average play, and the **goals** a player chases (first upgrade, mid goals, the end of the curve with the cost of each). Fix the balance so soft-currency sinks drain about 85-125% of the faucets, the first goal arrives in ~3 minutes and nothing ends up above ~20 hours without a shortcut. Premium currency gets a small free faucet and cosmetic/convenience sinks.

## 3. Catalog
Cover the four wants (save time, look good, do more, belong) with a short list, not everything possible:
- 1 entry item (25-100 R$), 3-5 currency pack tiers where bigger = better value, 1-3 passes (the main perk, a cosmetic/VIP, a convenience), a one-time starter pack, optional subscription or rewarded ads for free players.
- For every item: what the player gets, why it is worth it at that price, the moment it is offered, and the free way to get the same thing (required when it gates a core feature).
- Apply the fairness rules: no pay-to-win in PvP, odds shown and `PolicyService` checked for paid random items, no countdowns or guilt copy in all-ages games.

## 4. Write and check the spec
Write `monetization.json` in the project (format at the top of `scripts/monetization_check.py`, example in `assets/examples/monetization-example.json`; ask before overwriting). Create the passes and products in Creator Hub (or tell the user to) and paste the asset ids in. Then:
```
python3 scripts/monetization_check.py monetization.json -o src/shared/Products.luau
```
(`--allow-todo` while ids don't exist yet; the module is only written when there are no errors.) Fix every ERROR (duplicate ids, missing free path, undisclosed odds, grants an unknown currency, no asset id) and every warning unless there's a reason to keep it (faucet/sink balance, slow first goal, grind wall, worse-value pack, pay-to-win, dark pattern). Read the revenue line as a scenario built from the user's own assumptions, never as a forecast: say so, and don't promise income.

## 5. Wire it
- `roblox-luau-codegen`: register a handler per developer product in `PurchaseService` using ids from `Products.luau`, grant by the spec's `grants`, idempotently; ownership checks for passes; economy events (`LogEconomyEvent`) with the spec's faucet/sink ids; the Dynamic Price Check before turning on Managed Pricing for products.
- `roblox-ui-designer`: shop screen (tabs per want, featured offer, owned marks, live prices from `Products.GetPrice`, hide the button while it returns nil), contextual offers at natural moments with one dismiss, purchase confirmation with VFX/SFX.
- `roblox-animation-vfx`: the purchase and reward presets.

## 6. Write `MONETIZATION.md` in the project (ask before overwriting)
```
# <Game>: monetization
Audience, game type, principles (what we never sell)

## Economy
| Currency | Kind | Faucets /h | Sinks /h | Balance | Notes |
Goals and time to afford each

## Catalog
| Item | Type | Price | Player gets | Offered when | Free path | Pay-to-win/policy check |

## Offer moments
| Moment | Offer | Frequency cap |

## Metrics
Conversion, ARPDAU, first-purchase time, currency stock, revenue share per product; what to change if each is off

## Experiments
One variable per test, 14+ days

## Risks
```

## 7. Report
- Checker summary (errors, warnings, the revenue scenario with its assumptions) and the paths of `monetization.json`, `Products.luau`, `MONETIZATION.md`.
- The 3 changes that matter most for the player experience and for revenue.
- What needs a human: creating passes/products/subscriptions in Creator Hub and pasting ids, the questionnaire (paid random items), enabling Managed Pricing, testing purchases with a test account, DevEx and tax setup.

## Hand-off
`roblox-game-production-plan` if the economy changes the task list; `roblox-luau-codegen` for handlers, ownership and analytics; `roblox-ui-designer` for the shop; `roblox-security-perf-audit` before launch (purchases, hard-coded prices); `roblox-launch-kit` for store page, pricing optimization and live-ops events.
