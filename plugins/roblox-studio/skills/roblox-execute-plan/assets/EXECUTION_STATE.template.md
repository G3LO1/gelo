# Execution state

Updated by the `roblox-execute-plan` skill after every wave. Read this first when resuming.

## Setup
- Workflow: <A Rojo and files / B Studio only / C mixed>
- Sessions: <one session / one session per milestone>
- Place (B, C): <place name and id>
- Rojo-managed paths (C): <e.g. ReplicatedStorage.Shared, ServerScriptService.Server, StarterPlayer.StarterPlayerScripts.Client>
- Integration branch (A, C): <branch>

## Progress
- Current milestone: <M1>
- Done: <n> of <total> tasks (see `status` in tasks.csv)
- Last gate: <milestone, date, passed / failed and what>

## Milestones
| Milestone | Status | Gate | Checkpoint copy (B, C) | Manifest (B, C) |
| --- | --- | --- | --- | --- |
| M1 | <todo / in progress / done> | <passed / failed / not run> | <checkpoints/M1.rbxl> | <checkpoints/M1-manifest.txt> |

## Open decisions
- <none>

## Unmerged branches / pending sync
- <none>

## Notes for the next session
- <what is half done, what could break, what failed and why>
