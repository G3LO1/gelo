# Workflow C: mixed (files + Studio)

Code, data and specs live in the repo (Rojo); the map, models and UI are built in the open place. Two lanes:

```
python3 scripts/plan_waves.py tasks.csv --workflow c --next
```

Each wave comes back as:
- `file_lane`: `surface` = `file` tasks. Run them in parallel exactly like [workflow A](workflow-a-rojo.md) (worktrees,
  one branch per task, merge one at a time, quick gate after each merge).
- `studio_lane`: `surface` = `studio` tasks. Run them serially with the rules of [workflow B](workflow-b-studio.md)
  (single writer, ask before destructive operations).
- `sync_points`: `{"task": "MAP-02", "after": ["SYS-01"]}` means the Studio task needs the output of those file
  tasks to be **in the place** first.

The two lanes of one wave run at the same time: the file lane in worktrees, the Studio lane in the open place.
The lanes never touch the same thing, because the file lane writes only to the repo and the Studio lane only to
instances that are not Rojo-managed.

## Who owns what in the place

Rojo owns the paths in `default.project.json` (typically `ReplicatedStorage.Shared`, `ServerScriptService.Server`,
`StarterPlayer...`). **The Studio lane must not edit those**, and Rojo must not overwrite the map, models and
Studio-built UI. Write the split into `EXECUTION_STATE.md` at the start (list the Rojo-managed paths) and check
every Studio task against it. UI built from `ui-spec.json` goes to `StarterGui` and is Studio-owned.

## Sync points

Before starting a task that has a sync point:
1. The file tasks in `after` are merged and passed the quick gate.
2. Sync the repo into the place (Rojo serve + connect from Studio, or the user's usual sync) and read back that the
   scripts the Studio task needs exist in the place.
3. Then run the Studio task.

If the sync can't be done by you (Rojo plugin not connected), tell the user exactly what to click and wait; don't
paste the code into the place by hand, because the next Rojo sync would overwrite it.

## Gate (end of every milestone)

Both gates: the file gate of workflow A (quick gate, tests, `scan_luau.py --fail-on high`, `rojo build`) and the
Studio gate of workflow B (checkpoint copy and manifest, `audit_studio.luau`, playtest of the milestone's exit
criterion). Passing one is not enough.

## Resume

State: git (`tasks.csv`, `EXECUTION_STATE.md`, `exec/*` branches) plus the last Studio manifest. Check both as in
A and B, then `plan_waves.py --next`.
