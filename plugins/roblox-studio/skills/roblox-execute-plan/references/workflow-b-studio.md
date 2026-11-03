# Workflow B: Studio only (MCP)

The place is the project. Two agents writing to the same place at the same time corrupt each other's work and
Studio state is not in git, so this workflow is serial where it writes and parallel only where it prepares.

```
python3 scripts/plan_waves.py tasks.csv --workflow b --next
```

Each wave comes back as:
- `prepare_parallel`: tasks that don't write to the place (`surface` = `file`): specs, `ui-spec.json`, scripts drafted as
  text, audits that only read. Safe to give to parallel agents. If `tasks.csv` has no `surface` column, everything is in the queue.
- `studio_queue`: tasks that write to the place, **in order, one at a time**.

## The single-writer rule

- At any moment exactly one agent (or you) may call Studio tools that change the place. Run the queue yourself or
  hand a task to **one** subagent and wait for it; never start two.
- Preparation agents never call Studio write tools. They may read (`list_roblox_studios`, tree and script reads) so
  the specs match the real place.
- Start of every session: `list_roblox_studios`, confirm with the user that it is the right place, and read the
  current tree of the containers the wave touches. Don't trust what the previous session remembers.

## Safe vs needs the user's go-ahead

Safe without asking: reading, listing, running read-only audits (`audit_studio.luau`), creating new instances in a
folder the task owns, playtests that don't save anything.

Ask first, every time: deleting or replacing instances, `execute_luau` that changes many parts at once, anything
outside the folders the task owns, publishing. Say what will change and how many instances it touches.

## Running the queue

For each task in `studio_queue`, in order:
1. Read the task, check its dependencies are `done`, read what already exists in the place for it.
2. Do it with the matching skill (`roblox-map-builder`, `roblox-ui-designer` build script, `roblox-luau-codegen`
   straight-into-Studio delivery, `roblox-animation-vfx`).
3. Look at the result in the place (tree read-back or a short playtest), then mark it `done`.

Run the `prepare_parallel` tasks of the *next* wave while the queue is working only if they truly don't write; their
output (a spec file, a script as text) is applied later by the queue.

## Checkpoint at the end of every milestone

Studio state isn't in git, so write the state down:
1. Ask the user to save a copy of the place (File > Save to File As, e.g. `checkpoints/M1.rbxl`), and name it in `EXECUTION_STATE.md`. Without a saved copy the milestone can't be rolled back.
2. Write a **manifest**: use `execute_luau` (read-only) to list the top-level containers you built into (e.g. `Workspace.Map`, `ReplicatedStorage.Shared`, `ServerScriptService`, `StarterGui`) with each child's name and class and script count, and save it as `checkpoints/M1-manifest.txt`. The next session compares it to the live place before starting.

## Gate

- Run `scripts/audit_studio.luau` of `roblox-security-perf-audit` with `execute_luau` in Edit mode and fix what the milestone introduced.
- Playtest the exit criterion of the milestone from `PRODUCTION_PLAN.md`. Without a working playtest the gate is not passed; ask the user to playtest and report.

## Resume

Read `EXECUTION_STATE.md`, confirm the place is the same one (name, then compare against the last manifest), and say
about any difference before continuing. Then `plan_waves.py --next`.
