#!/usr/bin/env bash
# Tests for the roblox-execute-plan wave planner (plan_waves.py): the three workflows, resume, broken plans
# and the Undead Eats production plan. Needs python3 only. Run from the repo root:
#   bash tests/roblox-execute-plan/run.sh
set -u
exec python3 tests/roblox-execute-plan/test_waves.py
