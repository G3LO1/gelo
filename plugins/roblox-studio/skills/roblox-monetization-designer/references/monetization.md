# Monetization reference

Design rules and platform facts for earning Robux without wrecking retention. Platform facts are copied from the
repo's other references (checked October 2026 on create.roblox.com); Roblox changes terms often, so re-check anything
a price or a launch date depends on. Numbers marked "heuristic" are starting points to playtest, not Roblox rules.

## Contents
1. What to sell: product types
2. Economy design: faucets, sinks, two currencies
3. Prices and ladders
4. Where and when to offer things
5. Fairness, policy and kids
6. Technical rules (receipts, prices, ownership)
7. Measuring and tuning
8. Earning programs

## 1. What to sell
| Type | Use for | Notes |
| --- | --- | --- |
| Game pass | permanent perks: 2x earnings, extra slots, VIP area, cosmetics bundles | one-time; check ownership with `UserOwnsGamePassAsync` (cached by `PurchaseService.OwnsPass`) |
| Developer product | repeatable: currency packs, boosts, revives, skips, gifts | grant in `ProcessReceipt`, idempotent (template `PurchaseService`) |
| Subscription | recurring value: monthly perks, battle-pass-like track | needs a verified account; verify current terms; id is a string like `EXP-...` |
| Private server | social/co-op games with friend groups | priced in Creator Hub; regionalized automatically |
| Ads (rewarded video) | free players who won't pay | reward must be a developer product, disclose the ad; creator 13+ and ID-verified, 2,000+ unique monthly visitors |

Roblox keeps 30% of passes and products. A good catalog covers four wants: **save time** (boosts, skips), **look good**
(cosmetics), **do more** (slots, extra modes), **support/belong** (VIP, supporter pack). Pure power in PvP is the one
to avoid (section 5).

## 2. Economy design
Every currency needs faucets (where it comes from) and sinks (where it goes), per hour of play for an average active player.
- **Soft currency** (earned by playing): sinks should drain about 85-125% of the faucets (heuristic). Below that it
  inflates and prices lose meaning; above that it feels like a wall. `monetization_check.py` checks this band.
- **Premium currency** (sold for Robux): keep a small free faucet (daily reward, quests, achievements) so free players
  taste it, but far less than the sinks want. Sell it in packs; sinks should be mostly cosmetics and convenience.
- **Two currencies is the usual ceiling.** A third needs a clear reason (event tokens that expire).
- **Time to first goal**: the first thing the player can afford should arrive inside ~3 minutes, the first reward before 60 s
  (launch-kit's bounce windows). Later goals grow roughly 2-3x each step; if the top goal takes more than ~20 h of play
  with nothing to shorten it, it is a wall.
- **Sinks that don't punish**: upgrades with growing costs, rebirth/prestige, cosmetics, crafting fees, repair costs, expiring
  boosts. Avoid sinks that delete progress.
- **Boost math**: a 2x coins pass doubles faucets for owners. Make sure the sinks scale so the pass speeds things up
  without making the free game feel pointless; price it so a typical payer gets value in about a week of play.

## 3. Prices and ladders
- Offer an **entry item** around 25-100 Robux (heuristic): the first purchase is the hardest, later ones are easy.
- Currency packs: 3-5 tiers; each bigger tier must give **more per Robux** than the one below (the checker warns
  otherwise); mark the best-value tier; the middle tier should be what most buyers pick.
- Anchor: show the biggest pack beside the others so the middle looks reasonable. Show what the player gets, not only a number.
- Starter pack: one-time, 2-4x the value of its price, shown after the first successful loop, gone after purchase or a few days
  (a countdown is only fine for 13+ audiences, see section 5).
- Pass prices cluster at 100-1,000 Robux for perks, 1,000+ for big bundles (heuristic); test, don't guess.
- Never hard-code prices in UI; read them live (section 6). Managed Pricing sets regional prices between 30% and 100%
  of your default.
- **Price optimization** needs ~60,000 transactions in the previous 30 days; before that, copy comparable games and test
  one variant at a time with Experiments for 14+ days.

## 4. Where and when to offer
- Offer at **natural moments**, never in the way: after a win or a milestone, when the player is one step short of a goal
  ("need 40 more coins: buy a pack"), on death/fail screens (revive, keep progress), at a full inventory (more slots).
- One prompt per moment, never repeated in the same session after a "no". No purchase prompt in the first minute.
- Shop screen: tabs per want (boosts, cosmetics, packs), the featured offer on top, owned items marked, a clear free alternative.
- Make every purchase **feel immediate**: instant grant, a VFX/SFX (`roblox-animation-vfx` purchase preset), a visible change.
- Gifting and social: "buy for a friend" and supporter perks drive purchases in co-op games.
- Free path first: every core feature reachable without paying; pay buys time, looks or convenience.

## 5. Fairness, policy and kids
- **Pay-to-win**: in PvP, don't sell stats/weapons that decide fights; sell looks, convenience, side modes. In co-op/PvE, power for
  Robux is a design choice but still keep a free path.
- **Paid random items** (crates, spins): disclose in the Maturity & Compliance Questionnaire, show the odds in the UI, and check
  `PolicyService` per player (some regions restrict them). Never sell random items as the only way to a core item.
- **Kids and all-ages games**: no countdown pressure, no fake scarcity, no guilt copy ("your pet will be sad"), no purchase
  prompts that block play, clear prices, easy dismiss. These are also what players report as manipulative.
- **Giveaway/Robux bait** in names or descriptions lowers exposure (launch-kit store page).
- Don't sell things the player can't understand yet (a 1,000 R$ bundle in minute one).
- Refund-sensitive: gifts and trades between players with different price levels need `GetUsersPriceLevelsAsync`.

## 6. Technical rules
- Receipts: grant in `MarketplaceService.ProcessReceipt`, idempotent by `PurchaseId`, save before `PurchaseGranted`
  (`roblox-luau-codegen` template does this).
- **Prices come from the platform**: `MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)` for products,
  `Enum.InfoType.GamePass` for passes, then `PriceInRobux`; the generated `Products.GetPrice` does this with a cache and
  returns nil (hide the button) when it can't be read. Run Dynamic Price Check (up to 5 test accounts) before enabling
  Managed Pricing for developer products.
- Prompt purchases with `PromptGamePassPurchase`, `PromptProductPurchase`; update the UI on the finished events, but trust
  only the server (receipt/ownership) for granting.
- Don't use prices as game logic (e.g. "item power = price"); regional prices differ.
- Product IDs belong in one module (`Products.luau` generated from `monetization.json`); product handlers register against it.
- Economy events: `AnalyticsService:LogEconomyEvent` for every faucet and sink after the transaction succeeds, named
  consistently (source/sink ids = the ids in your spec).

## 7. Measuring and tuning
Watch weekly: payer conversion (payers / DAU; low single digits is normal), ARPDAU, average purchases per payer, first-purchase time
(minutes from first join), currency stock per player (growing without bound = inflation), share of revenue per product,
D1/D7 retention of payers vs non-payers. Funnels: shop opened -> item viewed -> prompt shown -> purchased.
Change one thing at a time, 14+ days per test. If retention drops after a monetization change, revert first, analyze after.

## 8. Earning programs
Creator Rewards (since 24 July 2025) replaced Premium Payouts and Engagement-Based Payouts: Daily Engagement Rewards
(5 Robux when an Active Spender plays 10+ minutes and the game is among their first three of the day) and Audience
Expansion Rewards (35% of a new or returning user's first $100 of purchases in 60 days; needs 100+ average DAU, ID
verification and DevEx). Sessions over 10 minutes therefore matter directly for revenue. DevEx rate and thresholds change:
the `usd_per_robux` assumption in the spec defaults to 0.0035; verify it before showing money figures.
