# Workflow A: Rojo and files

Everything lives in the repo. Parallel agents are safe as long as they own different files.

```
python3 scripts/plan_waves.py tasks.csv --workflow a --next
```

Each wave comes back as `sub_waves`: groups of tasks that can run at the same time. Tasks of the same discipline are
in different sub-waves on purpose (they usually edit the same files); the script also prints a `WARNING` naming them.

## Running a wave

1. **Prepare**: make sure the working tree is clean and on the integration branch. One branch per sub-wave task:
   `exec/<task-id>`. Create each agent's checkout with `isolation: "worktree"` on the Agent tool (or
   `git worktree add ../wt-<task-id> -b exec/<task-id>`), never let two agents share a directory.
2. **Brief each agent** with: the task row from `tasks.csv`, the plan lines about it, the paths it may create or edit,
   the contract files it may only read (`src/shared/Config.luau`, `Net.luau`, `Guard.luau`, data tables), the
   conventions from `roblox-luau-codegen` (`-- Plan: SYS-03` header, `Init()` / `Start()`), and the gate commands below.
   Start all agents of the sub-wave in one message so they run together, in the background.
3. **Collect**: when an agent finishes, read its diff yourself before merging. It stays on its branch until the
   task is checked against its description.
4. **Merge one at a time** into the integration branch, in the order of the wave. After each merge run the quick gate.
   Conflict in a contract file: resolve by hand, keep both additions, and re-run the gate; don't let an agent "win".
5. **Next sub-wave** starts from the merged result, so it sees the earlier work.

Tasks run **in order, not in parallel**, when two of them in the same wave both change a shared contract file
(adding remotes to `Net`, new fields in `Config.DefaultData`): the later one rebases on the earlier.

## Gates

Quick gate, after every merge:

```
bash <roblox-luau-codegen skill folder>/scripts/check.sh <project-folder> src
```

(StyLua + Selene; tools that aren't installed are skipped, so say so if none ran). If the project has Lune tests, run them too.

Milestone gate, at the end of every milestone:
- the quick gate and all project tests;
- `python3 <roblox-security-perf-audit skill folder>/scripts/scan_luau.py src --fail-on high`;
- `rojo build -o place.rbxl` succeeds. When Studio MCP is connected, sync and playtest the milestone's exit criterion
  from `PRODUCTION_PLAN.md` (e.g. "10+ minutes of the core loop without prompts"), otherwise ask the user to.

## Optional: one task = one PR

If the user wants review per task, each `exec/<task-id>` branch becomes a pull request instead of a local merge, in
wave order, each rebased on the integration branch. Open PRs only when the user asks for them.

## Resume

State is in git: `tasks.csv` (`status`), `EXECUTION_STATE.md` and the `exec/*` branches. Before starting, list unmerged
`exec/*` branches: finish or discard them (ask), then run `plan_waves.py --next` again.
