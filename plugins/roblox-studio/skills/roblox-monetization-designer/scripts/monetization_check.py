#!/usr/bin/env python3
"""Checks a Roblox game's monetization design and generates the Luau catalog module.

Usage: monetization_check.py monetization.json [-o src/shared/Products.luau] [--allow-todo] [--json report.json]

monetization.json:
{
  "game": "Undead Eats",
  "audience": "all_ages",              # all_ages | 13plus | 17plus
  "pvp": false,                        # true = players fight each other (power sold for Robux becomes pay-to-win)
  "assumptions": {                     # all optional; used for the revenue scenario only
    "dau": 2000, "payer_conversion": 0.03, "purchases_per_payer_month": 2,
    "usd_per_robux": 0.0035, "platform_cut": 0.30
  },
  "currencies": [
    {"id": "Coins", "kind": "soft",    # soft = earned by playing, premium = sold for Robux
     "faucets": [{"id": "Serving", "per_hour": 3000}],
     "sinks":   [{"id": "Upgrades", "per_hour": 2600}]}
  ],
  "goals": [{"id": "FirstUpgrade", "currency": "Coins", "cost": 150}],   # first goal = first purchase a new player aims at
  "products": [
    {"id": "VIP", "type": "pass", "name": "VIP", "price": 399, "asset_id": 123,
     "mix": 1,                         # relative share of purchases (default 1)
     "gates_core": false, "free_path": "", "power": false,
     "random": false, "odds_disclosed": false, "policy_checked": false, "timer": false},
    {"id": "CoinsSmall", "type": "product", "name": "500 Coins", "price": 49, "asset_id": 456,
     "grants": {"Coins": 500}}
  ]
}
type: pass | product | subscription | private_server. "asset_id" 0 or missing = not created in Creator Hub
yet (an error unless --allow-todo; private servers need none). Subscriptions use a string id like "EXP-123".
Errors break the rules or the build (bad ids, missing free path, undisclosed odds); warnings are heuristics
(value ladder, faucet/sink balance, time to first goal, pay-to-win, dark patterns). Exit code 1 on errors.
"""

import argparse
import json
import re
import sys

TYPES = {"pass", "product", "subscription", "private_server"}
AUDIENCES = {"all_ages", "13plus", "17plus"}
NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
SOFT_LOW, SOFT_HIGH = 0.85, 1.25  # sink/faucet band that feels balanced
FIRST_GOAL_MINUTES = 3  # launch-kit: a goal reachable inside the 61-180 s bounce window
GRIND_HOURS = 20
ENTRY_PRICE = 100  # cheapest purchase above this makes the first purchase a big step
HIGH_CONVERSION = 0.08


class Report:
    def __init__(self):
        self.items = []

    def error(self, where, msg):
        self.items.append(("error", where, msg))

    def warn(self, where, msg):
        self.items.append(("warning", where, msg))

    def info(self, where, msg):
        self.items.append(("info", where, msg))

    def count(self, level):
        return sum(1 for i in self.items if i[0] == level)


def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def check_currencies(spec, r):
    totals = {}
    for i, c in enumerate(spec.get("currencies", [])):
        where = f"currencies[{i}] {c.get('id', '?')}"
        cid = c.get("id")
        if not isinstance(cid, str) or not NAME.match(cid):
            r.error(where, "id must be a Luau identifier")
            continue
        if cid in totals:
            r.error(where, "duplicate currency id")
            continue
        kind = c.get("kind")
        if kind not in ("soft", "premium"):
            r.error(where, "kind must be 'soft' or 'premium'")
            continue
        sides = {}
        for side in ("faucets", "sinks"):
            total = 0
            for j, e in enumerate(c.get(side, [])):
                rate = e.get("per_hour") if isinstance(e, dict) else None
                if not num(rate) or rate < 0:
                    r.error(f"{where} {side}[{j}]", "per_hour must be a number >= 0")
                    continue
                total += rate
            sides[side] = total
        totals[cid] = (kind, sides["faucets"], sides["sinks"])
        faucet, sink = sides["faucets"], sides["sinks"]
        if kind == "soft":
            if faucet <= 0:
                r.error(where, "soft currency without a faucet: players can never earn it")
            elif sink <= 0:
                r.warn(where, "no sinks: it only piles up and loses its value")
            else:
                ratio = sink / faucet
                if ratio < SOFT_LOW:
                    r.warn(where, f"sinks drain {ratio:.0%} of what players earn (< {SOFT_LOW:.0%}): the economy inflates, add sinks")
                elif ratio > SOFT_HIGH:
                    r.warn(where, f"sinks want {ratio:.0%} of what players earn (> {SOFT_HIGH:.0%}): it feels like a grind wall")
        else:
            if faucet <= 0:
                r.warn(where, "premium currency with no free faucet: no free path to it (a daily reward or quest keeps free players engaged)")
            elif sink > 0 and faucet >= sink:
                r.warn(where, "free faucet covers all premium sinks: nothing left to sell")
    return totals


def check_goals(spec, totals, r, products):
    goals = spec.get("goals", [])
    if not goals:
        r.warn("goals", "no goals: cannot check time to first purchase and grind walls")
        return
    sold = {cur for p in products for cur in (p.get("grants") or {}) if p.get("type") == "product"}
    for i, g in enumerate(goals):
        where = f"goals[{i}] {g.get('id', '?')}"
        cur, cost = g.get("currency"), g.get("cost")
        if cur not in totals:
            r.error(where, f"unknown currency '{cur}'")
            continue
        if not num(cost) or cost <= 0:
            r.error(where, "cost must be a number > 0")
            continue
        faucet = totals[cur][1]
        if faucet <= 0:
            continue
        minutes = cost / faucet * 60
        if i == 0 and minutes > FIRST_GOAL_MINUTES:
            r.warn(where, f"first goal takes {minutes:.1f} min of earning (> {FIRST_GOAL_MINUTES} min): the player may leave before the first purchase")
        hours = minutes / 60
        if hours > GRIND_HOURS:
            if cur in sold:
                r.info(where, f"{hours:.0f} h of earning: a grind wall; make sure the {cur} packs are a shortcut, not the only way")
            else:
                r.warn(where, f"{hours:.0f} h of earning (> {GRIND_HOURS} h) and nothing sells {cur}: a pure grind wall")
        else:
            r.info(where, f"{minutes:.1f} min of earning ({hours:.1f} h)")


def check_products(spec, totals, r, allow_todo):
    products = spec.get("products", [])
    seen = set()
    audience = spec.get("audience", "all_ages")
    for i, p in enumerate(products):
        pid = p.get("id")
        where = f"products[{i}] {pid if pid else '?'}"
        if not isinstance(pid, str) or not NAME.match(pid):
            r.error(where, "id must be a Luau identifier")
            continue
        if pid in seen:
            r.error(where, "duplicate id")
        seen.add(pid)
        typ = p.get("type")
        if typ not in TYPES:
            r.error(where, f"type must be one of {sorted(TYPES)}")
            continue
        if not is_int(p.get("price")) or p["price"] <= 0:
            r.error(where, "price must be a whole number of Robux > 0")
        if typ != "private_server":
            aid = p.get("asset_id")
            if typ == "subscription":
                ok = isinstance(aid, str) and aid.startswith("EXP-") and len(aid) > 4
            else:
                ok = is_int(aid) and aid > 0
            if not ok:
                msg = "no asset id yet (create it in Creator Hub > Monetization)"
                (r.info if allow_todo else r.error)(where, msg)
        if typ == "product":
            grants = p.get("grants")
            if not isinstance(grants, dict) or not grants:
                r.error(where, "developer product without 'grants' (what does the player get?)")
            else:
                for cur, amount in grants.items():
                    if cur not in totals:
                        r.error(where, f"grants unknown currency '{cur}'")
                    elif not num(amount) or amount <= 0:
                        r.error(where, f"grants.{cur} must be > 0")
        if p.get("gates_core") and not p.get("free_path"):
            r.error(where, "gates a core feature but has no 'free_path': every core feature needs a free way to get it")
        if p.get("random"):
            if not p.get("odds_disclosed"):
                r.error(where, "paid random item without disclosed odds")
            if not p.get("policy_checked"):
                r.warn(where, "paid random item: check PolicyService per player and answer the questionnaire")
        if p.get("power") and spec.get("pvp"):
            r.warn(where, "sells power in a PvP game: pay-to-win drives free players away")
        if p.get("timer") and audience == "all_ages":
            r.warn(where, "countdown/limited-time pressure in an all-ages game: easy to read as a dark pattern for children")
        if typ == "pass" and p.get("grants"):
            r.warn(where, "passes are permanent perks; use a developer product for something consumable")
    return products


def check_ladder(products, totals, r):
    by_cur = {}
    for p in products:
        if p.get("type") == "product" and is_int(p.get("price")) and p["price"] > 0 and isinstance(p.get("grants"), dict):
            for cur, amount in p["grants"].items():
                if num(amount) and amount > 0 and cur in totals:
                    by_cur.setdefault(cur, []).append((p["price"], amount / p["price"], p["id"]))
    for cur, tiers in by_cur.items():
        tiers.sort()
        if len(tiers) < 3:
            r.info(f"packs {cur}", f"{len(tiers)} price point(s): 3-5 tiers with a visible 'best value' sell more")
        for (p1, v1, id1), (p2, v2, id2) in zip(tiers, tiers[1:]):
            if v2 + 1e-9 < v1:
                r.warn(f"packs {cur}", f"{id2} ({p2} R$) gives {v2:.2f} {cur}/R$, worse than {id1} ({p1} R$) at {v1:.2f}: bigger packs should be better value")
    prices = [p["price"] for p in products if is_int(p.get("price")) and p["price"] > 0]
    if prices and min(prices) > ENTRY_PRICE:
        r.warn("prices", f"cheapest item is {min(prices)} R$ (> {ENTRY_PRICE}): add an entry-price item, the first purchase is the hardest")


def estimate(spec, products, r):
    a = spec.get("assumptions", {})
    dau = a.get("dau")
    conv = a.get("payer_conversion")
    if not num(dau) or not num(conv):
        r.info("revenue", "no assumptions.dau / payer_conversion: revenue scenario skipped")
        return None
    if conv > HIGH_CONVERSION:
        r.warn("revenue", f"payer_conversion {conv:.0%} is optimistic: most games stay in low single digits")
    priced = [(p["price"], p.get("mix", 1)) for p in products if is_int(p.get("price")) and p["price"] > 0 and num(p.get("mix", 1)) and p.get("mix", 1) > 0]
    if not priced:
        return None
    weight = sum(m for _, m in priced)
    avg_price = sum(pr * m for pr, m in priced) / weight
    per_payer = a.get("purchases_per_payer_month", 2)
    usd = a.get("usd_per_robux", 0.0035)
    cut = a.get("platform_cut", 0.30)
    payers = dau * conv
    gross = payers * per_payer * avg_price
    net = gross * (1 - cut)
    result = {"payers_per_day": payers, "avg_price": avg_price, "gross_robux_month": gross, "net_robux_month": net, "net_usd_month": net * usd}
    r.info("revenue", f"{payers:.0f} payers x {per_payer} purchases/month x {avg_price:.0f} R$ avg = {gross:,.0f} R$ gross, "
           f"{net:,.0f} R$ after the {cut:.0%} cut, about ${net * usd:,.0f}/month at ${usd}/R$ (a scenario from your assumptions, not a forecast)")
    return result


def luau_string(s):
    return json.dumps(s, ensure_ascii=False)


def generate_luau(spec, products):
    lines = [
        "-- Generated by monetization_check.py from monetization.json. Edit the JSON and regenerate.",
        "-- Prices below are DEFAULTS for documentation: show players Products.GetPrice(...), never these numbers",
        "-- (Managed Pricing charges regional prices).",
        "local MarketplaceService = game:GetService(\"MarketplaceService\")",
        "",
        "local Products = {}",
        "",
    ]
    groups = [("Passes", "pass"), ("DevProducts", "product"), ("Subscriptions", "subscription")]
    for group, typ in groups:
        lines.append(f"Products.{group} = {{")
        for p in products:
            if p.get("type") != typ or not isinstance(p.get("id"), str):
                continue
            aid = p.get("asset_id")
            idv = luau_string(aid) if typ == "subscription" and isinstance(aid, str) else str(aid if is_int(aid) else 0)
            todo = "" if (is_int(aid) and aid > 0) or (isinstance(aid, str) and aid) else "  -- TODO: create in Creator Hub"
            parts = [f"Id = {idv}", f"Name = {luau_string(p.get('name', p['id']))}", f"DefaultPrice = {p.get('price', 0)}"]
            if typ == "product" and isinstance(p.get("grants"), dict):
                grants = ", ".join(f"{k} = {v}" for k, v in p["grants"].items())
                parts.append(f"Grants = {{ {grants} }}")
            lines.append(f"\t{p['id']} = {{ {', '.join(parts)} }},{todo}")
        lines.append("}")
        lines.append("")
    lines += [
        "local priceCache: { [string]: number } = {}",
        "",
        "-- Live price in Robux for the current region, or nil while it can't be read (hide the buy button then).",
        "-- kind: \"Passes\" | \"DevProducts\". Call from the client or server; results are cached.",
        "function Products.GetPrice(kind: string, name: string): number?",
        "\tlocal entry = (Products :: any)[kind] and (Products :: any)[kind][name]",
        "\tif not entry or entry.Id == 0 then",
        "\t\treturn nil",
        "\tend",
        "\tlocal key = `{kind}/{name}`",
        "\tif priceCache[key] then",
        "\t\treturn priceCache[key]",
        "\tend",
        "\tlocal infoType = if kind == \"Passes\" then Enum.InfoType.GamePass else Enum.InfoType.Product",
        "\tlocal ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, entry.Id, infoType)",
        "\tif not ok or type(info) ~= \"table\" or type(info.PriceInRobux) ~= \"number\" then",
        "\t\treturn nil",
        "\tend",
        "\tpriceCache[key] = info.PriceInRobux",
        "\treturn info.PriceInRobux",
        "end",
        "",
        "return Products",
        "",
    ]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("spec")
    ap.add_argument("-o", "--output", help="write the Luau catalog module here")
    ap.add_argument("--allow-todo", action="store_true", help="products without an asset id yet are info, not errors")
    ap.add_argument("--json", help="write the findings as JSON")
    args = ap.parse_args()

    try:
        with open(args.spec, encoding="utf-8") as f:
            spec = json.load(f)
    except (OSError, ValueError) as e:
        sys.exit(f"cannot read {args.spec}: {e}")
    if not isinstance(spec, dict):
        sys.exit("the spec must be a JSON object")

    r = Report()
    if spec.get("audience", "all_ages") not in AUDIENCES:
        r.error("audience", f"must be one of {sorted(AUDIENCES)}")
    totals = check_currencies(spec, r)
    products = check_products(spec, totals, r, args.allow_todo)
    if not products:
        r.error("products", "no products: nothing to sell")
    check_goals(spec, totals, r, products)
    check_ladder(products, totals, r)
    est = estimate(spec, products, r)

    for level, where, msg in r.items:
        print(f"{level}: {where}: {msg}")
    print(f"{r.count('error')} error(s), {r.count('warning')} warning(s)")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump({"findings": [dict(level=l, where=w, message=m) for l, w, m in r.items], "estimate": est}, f, indent=2)
    if args.output and r.count("error") == 0:
        with open(args.output, "w", encoding="utf-8", newline="\n") as f:
            f.write(generate_luau(spec, products))
        print(f"wrote {args.output}")
    elif args.output:
        print("not writing the module while there are errors")
    sys.exit(1 if r.count("error") else 0)


if __name__ == "__main__":
    main()
