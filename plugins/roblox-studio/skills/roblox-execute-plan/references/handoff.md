# Handoff to the next session

A new session starts with no memory of this one. The handoff is two things: an up-to-date `EXECUTION_STATE.md` and a
prompt the user pastes into the new session. Write both when the user asks, at the end of a milestone (if they chose
several sessions), or when the conversation has become heavy.

## 1. Bring the state up to date

- `tasks.csv`: every finished task has `status` = `done`. A task that is half done stays `todo`; write what is left in
  the "Notes for the next session" block.
- `EXECUTION_STATE.md` (from `assets/EXECUTION_STATE.template.md`): workflow, current milestone, last gate result,
  open decisions, branches still unmerged (A/C), last checkpoint copy and manifest (B/C), Rojo-managed paths (C).
- Commit both files (workflow A/C). In workflow B there is no repo requirement; save them next to the project.

## 2. Compute what comes next

```
python3 scripts/plan_waves.py tasks.csv --workflow <a|b|c> --next
```

Put the printed wave in the prompt, so the next session starts exactly there.

## 3. The prompt

Fill the placeholders from the real state; no placeholder may stay in the final text.

```
Continue the Roblox game from the production plan with the roblox-execute-plan skill.

Workflow: <A / B / C> (chosen already, don't ask again)
Read first: EXECUTION_STATE.md, tasks.csv, PRODUCTION_PLAN.md (milestone <M#> only)
Done: <count> of <total> tasks, milestone <M#> gate: <passed on <date> / not run yet>
Next wave:
<output of plan_waves.py --next>
Open decisions: <list, or "none">
Unmerged branches / pending sync: <list, or "none">
Careful with: <anything the next session could break: shared contract files, Rojo-managed paths, a task that
failed and why>
Start by checking the state matches this note (git status and branches; in B/C list_roblox_studios and the last
manifest), tell me about differences, then run the wave.
```

## 4. Tell the user

Show the prompt in a code block and name the files it relies on. Say plainly if something is not saved (uncommitted
changes, no checkpoint copy of the place) so the next session doesn't start on a false picture.
