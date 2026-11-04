# What to sell, at what price

Rules of thumb for the first catalog. Prices are starting points: switch on Managed Pricing (`managedPricing: true`) or run price tests from the launch kit (`roblox-launch-kit`) once there is traffic.

## Pass or product?
- **Game pass**: bought once, forever. Permanent perks and multipliers: 2x Cash, +25% Size, VIP chat tag/area, extra inventory slots, auto-collect, faster walk, radio. Grant types: `perk` (just ownership, read with `Owns`) or `multiplier` (`stat` + `value`, read with `Multiplier`). Multipliers of the same stat stack by multiplication (2x Cash pass + 1.5x Cash pass = 3x).
- **Developer product**: consumable, bought again and again. Currency packs, starter pack, revives/skips, temporary boosts, server-wide events (Cash Rain, Lucky Hour), donations. Grant types: `currency` (`field` in `Config.DefaultData` + `amount`) or `handler` (custom code via `OnProduct`).
- A temporary boost (2x for 15 minutes) is a product with a `handler` that stores an expiry time in `data`; a permanent one is a pass.

## Starter catalog (simulator / tycoon / obby)
| Item | Kind | Price (Robux) | Grant |
| --- | --- | --- | --- |
| Starter Pack | product | 29-79 | currency (2-3x better value than the smallest pack), show it to new players |
| Small / Medium / Large currency | product | 49 / 199 / 799 | currency, each step 10-25% more per Robux |
| 2x Cash (or 2x the main currency) | pass | 149-399 | multiplier Cash 2 |
| +25% Size / Speed / Luck | pass | 99-249 | multiplier stat 1.25 |
| VIP | pass | 199-499 | perk (tag, area, bonus) |
| Auto-collect / auto-farm | pass | 149-349 | perk |
| Skip stage (obby) | product | 15-49 | handler |
| Server event (Cash Rain, Lucky Hour) | product | 49-199 | handler, benefits everyone: good social pressure |

Keep 4-8 items at launch: a few clear choices sell better than a wall. Order them in the manifest the way the shop should show them (cheapest impulse buy first or best value first, but consistent).

## Policy (Roblox Terms and Community Standards)
- What is bought must be delivered: no random-reward products without showing the odds (paid random items must disclose odds, and some countries forbid them), no "chance to get Robux", no off-platform payments.
- No pay-to-win against other players in competitive modes without a way to earn it; at least keep PvP fair.
- Don't use words like "free Robux" or mimic Roblox UI in names and icons.
- Developer products can be bought many times: make every handler safe to run repeatedly and never take items away on a second purchase.

## Icons
- 512x512 PNG, one bold object, readable at 64 px, no text (names are shown next to it; text in icons doesn't localize), no Robux glyph, no Roblox logo.
- Pass icons are cropped to a circle: keep the subject in the middle 80%.
- Same style for every item (`iconStyle` in the manifest), different main color per item so they are easy to tell apart in the grid.
