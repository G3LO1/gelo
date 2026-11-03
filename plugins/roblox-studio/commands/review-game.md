---
description: Read the current state of any Roblox game project and rate it with a scorecard, verdict and a ranked list of what to improve
argument-hint: "[project-folder] [--previous reviews/last.json]"
---

Review the Roblox game at `$ARGUMENTS` (the current folder if empty) with the `roblox-game-reviewer` skill:

1. Read the current state with `collect_state.py` from that skill (never score from memory), and run the
   `roblox-security-perf-audit` scanner, the project's tests and a Studio MCP playtest when they are available.
2. Score the 8 criteria with evidence, write `review.json` (or `reviews/<date>.json`), and run `review_score.py`
   (with `--previous` if an earlier review exists, so the report shows what changed).
3. Reply in the user's language with the scorecard, blockers, what works, the ranked improvements (each routed to
   the skill that fixes it), how you checked, and the next 2 weeks.

Ask at most one multiple-choice question, and only if the stage or goal of the game is unknown and changes the verdict.
