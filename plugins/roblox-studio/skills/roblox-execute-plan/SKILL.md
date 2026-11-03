---
name: "roblox-execute-plan"
description: "Carry out a Roblox game's production plan (PRODUCTION_PLAN.md / tasks.csv) task by task, in waves, with the execution mode that fits how the creator works: A) Rojo and files (parallel agents in separate git worktrees), B) Studio only through MCP (one agent writes to Studio at a time, checkpoints per milestone), C) mixed (parallel file lane plus serial Studio lane with sync points). Splits work between several agents, continues across sessions with a handoff prompt, runs quality gates (StyLua, Selene, Lune tests, the security/perf audit) before moving on, and resumes from saved progress. Use after the production plan exists, or whenever someone wants to implement, execute, build or ship the plan, run it with several agents in parallel, do it in phases or in several sessions, continue where the last session stopped, or says 'wdróż plan', 'zrób grę z planu', 'zrób to na kilku agentach', 'rozbij na sesje', 'kontynuuj od miejsca, gdzie skończyliśmy'."
---

# Roblox Execute Plan

Goal: turn `PRODUCTION_PLAN.md` + `tasks.csv` into a working game without agents overwriting each other, without losing progress between sessions and without moving on while the last milestone is broken. How much can safely run in parallel depends on **where the game lives**, so the first thing this skill does is ask.

Answer in the user's language. Task IDs, file names and commands stay as they are.

## 1. Inputs
- `PRODUCTION_PLAN.md` and `tasks.csv` from `roblox-game-production-plan`. No plan: offer to make one first (one line), don't improvise a backlog.
- `tasks.csv` needs the columns `id,discipline,task,owner,size,priority,milestone,depends_on,surface,status`. If `surface` or `status` is missing (older plans), add them yourself: `surface` = `file` for scripts, data, specs and other things that live in the repo, `studio` for anything written straight into the place (map, models, UI built in Studio); `status` = `todo`. Tell the user what you assumed.
- `EXECUTION_STATE.md` in the project root: if it exists this is a **resume**, read it and skip the question in step 2.

## 2. Ask how the game is built (once)
One AskUserQuestion, recommended option first, saved in `EXECUTION_STATE.md` so it is not asked again:

1. **A: Rojo and files**: code and data live in the repo, synced to Studio with Rojo. Parallel agents are safe.
2. **B: Studio only (MCP)**: everything is built straight in the open place. Only one agent may write to Studio at a time.
3. **C: Mixed**: code in files with Rojo, map/models/UI built in Studio.

If the project has a `default.project.json` and the user is unsure, recommend A or C, and say which parts would be Studio-only. If Roblox Studio MCP tools are not connected, A is the only workflow that works without them; say so before the user picks B or C.

Then ask once whether they want to **spread the work over several sessions** (handoff after each milestone) or finish in one. Default: one session per milestone when the milestone has more than ~10 tasks.

## 3. The loop
Repeat until the plan is done or the user stops:

1. **Read state**: `tasks.csv`, `EXECUTION_STATE.md`. Tasks with `status` = `done` are finished.
2. **Get the next wave**:
   ```
   python3 scripts/plan_waves.py tasks.csv --workflow a|b|c --next
   ```
   (`--json` for machine-readable output, `--milestone M2` for one milestone, no `--next` for the whole plan). It stops with `ERROR:` lines on a broken plan (dependency cycle, unknown id, a task depending on a later milestone, missing `surface` for C): fix `tasks.csv` first, don't work around it. Show the wave to the user in one short table.
3. **Execute the wave** exactly as the workflow file says: [A](references/workflow-a-rojo.md), [B](references/workflow-b-studio.md), [C](references/workflow-c-hybrid.md). Read only the file for the chosen workflow.
4. **Per task**: implement with the matching skill of this plugin (`roblox-luau-codegen` for code, `roblox-ui-designer` for UI, `roblox-animation-vfx` for animation and effects, `roblox-map-builder` for the map), then check it against the task's description before marking it `done`. A task is done when it works, not when the file exists.
5. **Gate at the end of every milestone** (and after any wave that touched shared modules): the workflow file lists the gate. Red means fix it before the next wave; never mark tasks `done` to get past a gate.
6. **Save progress**: update `status` in `tasks.csv` and the milestone block in `EXECUTION_STATE.md` (template: `assets/EXECUTION_STATE.template.md`).
7. **Hand off** when the user asks, when the milestone ends and they chose several sessions, or when the conversation has become heavy: write the next-session prompt with [handoff.md](references/handoff.md).

## 4. Rules that hold in every workflow
- **One writer per file, one writer per place.** Agents in parallel get disjoint files (separate worktrees) and never touch the live Studio place; the Studio lane is always serial. Shared contract files (`Config`, `Net`, the data tables in `src/shared`) are changed by one task at a time; if two tasks in one wave both need them, run those two one after another.
- **Give each agent everything it needs**: the task row, the relevant lines of the plan, the paths it owns, the gate commands and what it must not touch. Agents don't see this conversation.
- **Never skip or loosen a test, a linter rule or an audit finding to get green.** Report it and ask.
- **Destructive Studio operations** (deleting or replacing instances, `execute_luau` that changes many parts, publishing) need the user's go-ahead each time; read-only inspection never does.
- **Report honestly**: which tasks are done, which failed or were skipped and why, what the gate printed.
- **Scope**: this skill runs the plan; it doesn't redesign it. If a task turns out wrong or too big, stop, tell the user, and change the plan together.
