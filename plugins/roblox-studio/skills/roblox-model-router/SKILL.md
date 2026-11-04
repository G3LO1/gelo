---
name: "roblox-model-router"
description: "Route the work of a Roblox project to the right AI model instead of running everything on the strongest one: a light model (Haiku-class) for searching, running the plugin's checkers, data conversion and boilerplate; a standard model (Sonnet-class) for Luau, UI, plans and fixes; a strong model (Opus-class) for design decisions, security/economy review and a final check of what the weaker models produced. Detects which models this user actually has (Claude Code settings, allowlists, pinned aliases, forced subagent model; Codex and Antigravity config) and re-checks the official docs at run time instead of trusting remembered model names. Ships three Claude Code subagents (roblox-scout, roblox-builder, roblox-reviewer). Use whenever a task is big enough to split (building a game system, a whole shop, an audit plus fixes, many files), when the user wants to save tokens or money, asks which model to use for what, wants a stronger model to verify the work, or says 'dobierz modele', 'oszczędzaj tokeny', 'niech opus sprawdzi', 'haiku do prostych rzeczy', 'zrób to taniej'."
---

# Roblox Model Router

Goal: cheap models do the mechanical work, mid models do the building, the strongest model decides the hard things and checks the result, so quality goes up while the strongest model's usage goes down. One rule above all: **a review is always done by a model at least one tier above the one that produced the work, and by one that did not write it.**

Answer in the user's language.

## 1. Find out what this user has (every time, model lists go stale)
```
python3 scripts/detect_models.py --project .
```
It prints the host (Claude Code / Codex / Antigravity), the tiers, pinned or blocked models and warnings. Then:
- **Claude Code**: use aliases (`haiku`, `sonnet`, `opus`, optionally `fable` for the hardest reviews), never hard-coded model ids: an alias resolves to the newest version this account and provider may use, and an `availableModels` allowlist substitutes a permitted one. Tell the user to check `/model` for the real list. If the report warns that `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` is set, or a tier is blocked, say so: routing is partly or fully ineffective and the user must change that setting for the plan to work.
- **Codex / Antigravity**: model names and delegation features differ and move fast. Do not rely on memory or on `references/hosts.md` alone: fetch the official docs listed in `docs_to_check` (WebFetch/WebSearch when available), ask the user to read out the models their picker shows, and build the tier table from that. Mark every row you could not verify.
Write the result as `MODEL_ROUTING.md` in the project (ask before overwriting): host, date checked, tier -> model table, source of each row, warnings.

## 2. Classify each task
| Tier | Work | Claude Code |
| --- | --- | --- |
| **Light** | find files/usages, read docs and logs, run scanners and validators and summarize them (`scan_luau.py`, `monetization_check.py`, `check_store_assets.py`, `anim_manifest.py`, `check.sh`), convert JSON/CSV/specs, generate boilerplate and fixtures, `tasks.csv` | `roblox-studio:roblox-scout` (haiku) |
| **Standard** | write Luau systems and controllers from the plan, build UI from a ui-spec, wire animations/VFX, map scripts, store copy, drafts of plans and specs, apply review fixes, write tests | `roblox-studio:roblox-builder` (sonnet) |
| **Strong** | idea verdicts, economy and pricing design, architecture and data model, security review of remotes/purchases/data saving, bugs that survived two attempts, the final review of anything lower tiers produced | `roblox-studio:roblox-reviewer` (opus) or the main session |
Do not delegate: a one-line answer, a single small edit, anything that needs the whole conversation's context, or a decision the user must make. Delegation has overhead; use it when the task is big, parallel, or mechanical enough to pay for it. Independent light tasks run in parallel.

## 3. The loop
1. **Plan** (strong or the main session): split the request into tasks with a tier each, acceptance criteria and the checks that prove them. Keep it short.
2. **Execute**: send each task to its tier with a self-contained brief (goal, files, constraints, exact commands to run, what to return). Workers do not see this conversation.
3. **Gate with tools first**: run the deterministic checks (scanners, validators, StyLua/Selene, tests) via the light tier. Failures go back to the builder before any review, because a strong model's time is for judgment, not for lint.
4. **Review** (one tier up): give the reviewer the requirements, the changed files or diff and the checker output, not the builder's explanation. It returns `VERDICT: PASS` or `VERDICT: FIX` with at most 5 prioritized findings.
5. **Fix and re-review**: the builder fixes only the listed findings; the reviewer checks only those and anything the fix touched. At most 2 rounds; a third failure means the task is mis-specified or too hard for that tier: escalate it to the strong tier or to the user instead of looping.
6. **Report**: what was done by which tier, what the reviewer found, checks run with results, what is NOT verified. Never say "reviewed" for work nobody reviewed.

Always send to the strong tier regardless of size: anything touching purchases, receipts, data saving, remotes that change money or progress, and anything that ships to all-ages players.

## 4. Fallbacks
- Plugin agents missing (skills installed with `install.sh` copy only skills): use the Agent tool with its `model` parameter (`haiku` / `sonnet` / `opus`) on a general-purpose agent and paste the role rules from `agents/*.md` into the brief.
- The user only has one model, or a tier is blocked: say so, run everything on it, and keep the separate review step by using a fresh context (a new subagent with the requirements and files, no history). It is a weaker check than a stronger model; tell the user.
- No subagents in the host (Codex/Antigravity without them): work in stages and ask the user to switch the model between stages; do the review in a new conversation on the stronger model with the requirements, the files and the checker output.

## 5. Report
- Detected host and models (with what could not be verified), the tier table, and `MODEL_ROUTING.md`.
- The task list with the tier of each, the review verdicts and rounds, and the savings logic in plain words (do not invent token or money numbers).
- What needs a human: changing a forced subagent model or allowlist, enabling the plugin agents, picking models in Codex/Antigravity.

## Hand-off
Use with any other skill: the router decides who runs `roblox-luau-codegen`, `roblox-ui-designer`, `roblox-security-perf-audit` etc.; the skills themselves stay unchanged. `roblox-security-perf-audit` and the strong reviewer together are the pre-launch gate.
