# Undead Eats (working title)

Example game built with the `roblox-studio` plugin: idea validated, planned, then coded with
`roblox-luau-codegen` and given a UI with `roblox-ui-designer`.

Rojo project. Implemented so far from `PRODUCTION_PLAN.md`: SYS-01..SYS-05, DATA-01, SYS-07 (truck
health model; repair interaction still TODO), SYS-11 (upgrade shop), UI-02 (HUD) and UI-06 (upgrade shop UI).

```
rojo serve        # then connect from the Rojo plugin in Studio
```

Studio: Game Settings > Security > Enable Studio Access to API Services (otherwise data uses an in-memory mock).

## UI
`ui/ui-spec.json` is the source of the UI (Bubbly Cartoon style, see the ui-designer skill). Build it once in Studio
and save the place: run `ui/BuildUi.luau` in the Command Bar (it creates `StarterGui.Hud`, `StarterGui.UpgradeShop`
and the `ReplicatedStorage.UIStyles.UndeadEatsUI` theme). After editing the spec, regenerate the script:

```
python3 ../../plugins/roblox-studio/skills/roblox-ui-designer/scripts/spec_to_luau.py ui/ui-spec.json -o ui/BuildUi.luau
```

Controllers bind by name (`src/client/Lib/UiBind.luau` warns about anything missing):
- `HudController`: `Hud/CashPanel/CashLabel`, `TimerPanel/{PhaseLabel,DayLabel,TimerLabel,TimerBar/Fill}`,
  `TruckHpPanel/HpBar/{HpFill,HpLabel}`, `ShopButton`.
- `ShopController`: `UpgradeShop/Panel/Header/{CashChip/CashLabel,CloseButton}`, cards in `Panel/ItemList`
  with attribute `UpgradeId` and children `LevelLabel`, `BuyButton`.

## Upgrade shop
Run phases: Ready -> (Day -> Night -> Shop) x 5 -> Results (no Shop after the last night). In the Shop phase
(`Config.Run.ShopSeconds`) the window opens by itself; any player spends team cash. Definitions and prices:
`src/shared/Upgrades.luau`. Server: `UpgradeService` (remote `BuyUpgrade`, only in the Shop phase, validated
and rate-limited), effects on workspace attributes `CookSpeed`, `TurretSlots`, `TruckMaxHp`.

## Tests
From the repo root: `lune run tests/undead-eats/run` runs a whole run (day, night, shop, purchases, truck
destroyed, reset) with the server services and both UI controllers against the UI from `ui/ui-spec.json`.

## Layout
| Path | Studio location |
| --- | --- |
| `src/shared` | ReplicatedStorage.Shared (`Config`, `Net`, `Guard`, data tables `Recipes`, `Turrets`, `Zombies`, `Nights`) |
| `src/server` | ServerScriptService.Server (`Services/*` loaded by `init.server.luau`, `Lib/*` helpers) |
| `src/client` | StarterPlayerScripts.Client (`Controllers/*`, `Lib/UiBind`) |

## World contract (what the map must provide, MAP-01)
`GreyboxService` builds all of this from plain parts while `Config.Greybox` is true and the map has no tagged objects.

| Tag | Attributes | Purpose |
| --- | --- | --- |
| `IngredientCrate` | `Ingredient` = Bun / Patty / Sausage / Potato / Dough / Cheese | takes an ingredient into the hands |
| `Station` | `StationType` = Grill / Fryer / Oven | cooking; publishes `State`, `Progress`, `BurnProgress`, `Dish`, `Inputs` |
| `ServiceWindow` | – | hand dishes to customers |
| `QueueSlot` | `Index` (1 = nearest the window) | where customers wait |
| `CustomerSpawn` | – | where customers appear and leave to |

Optional: `ServerStorage.ItemModels.<itemId>` (carried item models), `ServerStorage.Customers` (customer rigs).
ProximityPrompts are created if the objects have none.

## State for UI
`workspace` attributes: `GameState`, `StateEndsAt` (compare with `workspace:GetServerTimeNow()`), `Day`, `Cash`,
`TruckHp`, `TruckMaxHp`, `Upgrade_<Id>`, `CookSpeed`, `TurretSlots`.
Player attribute `Carrying`. Customer models in `workspace.Customers`: `Order`, `Total`, `Patience`, `Waiting`.

## Hooks for upcoming tasks
`TruckService.Damage(amount)` / `Repair(amount)` (SYS-06 zombies, SYS-07 repair), `GameService.SkipNight()` (SYS-06),
`EconomyService.Add/Spend` (SYS-08), workspace attribute `TurretSlots` (SYS-08 build mode),
player attribute `TipMultiplier` (Double Tips pass, MON-01).
