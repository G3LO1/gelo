#!/usr/bin/env python3
"""Detects which AI coding host is running and which models this user can route work to.

Usage: detect_models.py [--host claude-code|codex|antigravity] [--project DIR] [--json]

Reads only local configuration (never the network, never secrets):
  Claude Code : ~/.claude/settings.json, <project>/.claude/settings.json, settings.local.json,
                /etc/claude-code/managed-settings.json, plus the environment
                (ANTHROPIC_MODEL, ANTHROPIC_DEFAULT_*_MODEL, CLAUDE_CODE_SUBAGENT_MODEL[_FORCE]).
  Codex       : $CODEX_HOME/config.toml or ~/.codex/config.toml
  Antigravity : ~/.gemini/antigravity, <project>/.agent
Prints a JSON report: host, tiers (light/standard/strong -> alias or model), what the user has pinned or
restricted, warnings that make routing ineffective, and which official docs to check at run time.
Model names change often: Claude Code aliases (haiku/sonnet/opus/fable) resolve to the newest version the
user may use, so they are preferred over any hard-coded model id. Exit code 0 always (it is a report).
"""

import argparse
import json
import os
import re
import sys

FAMILIES = ["haiku", "sonnet", "opus", "fable"]
CLAUDE_DOCS = [
    "https://code.claude.com/docs/en/model-config",
    "https://code.claude.com/docs/en/sub-agents",
]
CODEX_DOCS = ["https://developers.openai.com/codex (search: subagents / custom agents, config.toml model, skills)"]
ANTIGRAVITY_DOCS = ["https://antigravity.google/docs (search: skills, agents, model selection)"]


def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def read_text(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def home():
    return os.path.expanduser("~")


def merge_claude_settings(project):
    paths = [
        ("user", os.path.join(home(), ".claude", "settings.json")),
        ("project", os.path.join(project, ".claude", "settings.json")),
        ("local", os.path.join(project, ".claude", "settings.local.json")),
        ("managed", "/etc/claude-code/managed-settings.json"),
    ]
    merged, env, sources = {}, {}, []
    for label, path in paths:  # later wins: user < project < local < managed
        data = read_json(path)
        if not data:
            continue
        sources.append(label)
        env.update({k: str(v) for k, v in (data.get("env") or {}).items() if isinstance(data.get("env"), dict)})
        for key in ("model", "availableModels", "enforceAvailableModels", "deniedModels"):
            if key in data:
                merged[key] = data[key]
    return merged, env, sources


def family_allowed(family, allowed, denied):
    """True when an alias of this family is permitted by availableModels/deniedModels."""
    def hit(entry, fam):
        e = str(entry).lower()
        return e == fam or f"-{fam}" in e or e.startswith(fam)
    if any(hit(d, family) for d in denied or []):
        return False
    if not allowed:
        return True
    return any(hit(a, family) for a in allowed)


def claude_report(project):
    settings, senv, sources = merge_claude_settings(project)
    env = dict(senv)
    env.update({k: v for k, v in os.environ.items() if k.startswith(("ANTHROPIC_", "CLAUDE_CODE_"))})
    warnings, tiers = [], {}
    allowed = settings.get("availableModels") if isinstance(settings.get("availableModels"), list) else None
    denied = settings.get("deniedModels") if isinstance(settings.get("deniedModels"), list) else None
    main = env.get("ANTHROPIC_MODEL") or settings.get("model") or env.get("ANTHROPIC_DEFAULT_MODEL")
    force = env.get("CLAUDE_CODE_SUBAGENT_MODEL_FORCE") in ("1", "true", "True")
    sub = env.get("CLAUDE_CODE_SUBAGENT_MODEL")

    for tier, family in (("light", "haiku"), ("standard", "sonnet"), ("strong", "opus")):
        pin = env.get(f"ANTHROPIC_DEFAULT_{family.upper()}_MODEL")
        ok = family_allowed(family, allowed, denied)
        entry = {"alias": family, "pinned_to": pin, "allowed": ok}
        if not ok:
            entry["note"] = "blocked by availableModels/deniedModels: the alias moves to the newest permitted model of that family or falls back to the main model"
            warnings.append(f"{tier} tier ({family}) is not permitted for this user; routing to it is replaced by another model")
        if main and family in str(main).lower():
            entry["note"] = (entry.get("note", "") + " subagents of this family run on the main conversation's exact model").strip()
        tiers[tier] = entry
    fable = {"alias": "fable", "pinned_to": env.get("ANTHROPIC_DEFAULT_FABLE_MODEL"), "allowed": family_allowed("fable", allowed, denied),
             "note": "optional top tier for the hardest reviews; only if the user's provider offers it (check /model)"}
    if force and sub:
        warnings.append(f"CLAUDE_CODE_SUBAGENT_MODEL_FORCE is set ({sub}): every subagent runs on that model, so tier routing has no effect")
    elif sub:
        warnings.append(f"CLAUDE_CODE_SUBAGENT_MODEL={sub}: default for subagents without their own model (the plugin agents set their own)")
    if not sources:
        warnings.append("no Claude Code settings found: aliases resolve to the provider defaults")
    return {
        "host": "claude-code",
        "settings_read": sources,
        "main_model": main,
        "tiers": tiers,
        "optional_top_tier": fable,
        "available_models_setting": allowed,
        "denied_models_setting": denied,
        "subagent_model_env": sub,
        "subagent_model_forced": force,
        "how_to_delegate": "Agent tool with subagent_type roblox-studio:roblox-scout (light), roblox-studio:roblox-builder (standard), roblox-studio:roblox-reviewer (strong); "
                           "without the plugin agents use the Agent tool's model parameter (haiku|sonnet|opus) on a general-purpose agent",
        "verify_in_session": "run /model to see the exact models this account can use",
        "docs_to_check": CLAUDE_DOCS,
        "warnings": warnings,
    }


def toml_top_level(text):
    """Tiny reader for top-level `key = "string"` pairs and [section] names (no dependency on tomllib)."""
    keys, sections, current = {}, [], None
    for line in text.splitlines():
        s = line.strip()
        m = re.match(r"^\[([^\]]+)\]$", s)
        if m:
            current = m.group(1)
            sections.append(current)
            continue
        m = re.match(r'^([A-Za-z0-9_]+)\s*=\s*"([^"]*)"', s)
        if m and current is None:
            keys[m.group(1)] = m.group(2)
    return keys, sections


def codex_report(project):
    base = os.environ.get("CODEX_HOME") or os.path.join(home(), ".codex")
    path = os.path.join(base, "config.toml")
    text = read_text(path)
    warnings = []
    keys, sections = ({}, [])
    if text is None:
        warnings.append(f"no Codex config at {path}")
    else:
        keys, sections = toml_top_level(text)
    project_agents = os.path.isdir(os.path.join(project, ".codex", "agents"))
    return {
        "host": "codex",
        "config_read": path if text is not None else None,
        "main_model": keys.get("model"),
        "profiles_and_sections": sections,
        "project_has_custom_agents_dir": project_agents,
        "tiers": {t: {"alias": None, "note": "model names are not detectable here: ask the user which models their Codex shows, and check the official docs"} for t in ("light", "standard", "strong")},
        "how_to_delegate": "unverified: custom agents/subagents with their own model, if the installed Codex version supports them; otherwise ask the user to switch model per step",
        "verify_in_session": "ask the user to open Codex's model picker and list the models; never assume names from memory",
        "docs_to_check": CODEX_DOCS,
        "warnings": warnings,
    }


def antigravity_report(project):
    g = os.path.join(home(), ".gemini", "antigravity")
    return {
        "host": "antigravity",
        "global_dir_found": os.path.isdir(g),
        "project_agent_dir_found": os.path.isdir(os.path.join(project, ".agent")),
        "main_model": None,
        "tiers": {t: {"alias": None, "note": "model names are not detectable here: ask the user which models Antigravity offers, and check the official docs"} for t in ("light", "standard", "strong")},
        "how_to_delegate": "unverified: Antigravity picks the model in its UI per conversation/agent; ask the user to switch the model per step and run the review in a new conversation on the stronger model",
        "verify_in_session": "ask the user to open Antigravity's model selector and list the models; never assume names from memory",
        "docs_to_check": ANTIGRAVITY_DOCS,
        "warnings": [],
    }


def detect_host(project):
    if os.environ.get("CLAUDECODE") or os.environ.get("CLAUDE_CODE_ENTRYPOINT"):
        return "claude-code"
    if os.environ.get("CODEX_HOME") or os.path.exists(os.path.join(home(), ".codex", "config.toml")):
        return "codex"
    if os.path.isdir(os.path.join(home(), ".gemini", "antigravity")) or os.path.isdir(os.path.join(project, ".agent")):
        return "antigravity"
    return "claude-code" if os.path.isdir(os.path.join(home(), ".claude")) or os.path.isdir(os.path.join(project, ".claude")) else "unknown"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", choices=["claude-code", "codex", "antigravity"])
    ap.add_argument("--project", default=os.getcwd())
    ap.add_argument("--json", action="store_true", help="JSON only (default also prints a summary)")
    args = ap.parse_args()
    project = os.path.abspath(args.project)
    host = args.host or detect_host(project)
    builders = {"claude-code": claude_report, "codex": codex_report, "antigravity": antigravity_report}
    report = builders[host](project) if host in builders else {"host": "unknown", "warnings": ["host not detected: pass --host"], "tiers": {}}
    print(json.dumps(report, indent=2))
    if not args.json:
        print(f"\nhost: {report['host']}; main model: {report.get('main_model')}", file=sys.stderr)
        for w in report["warnings"]:
            print(f"warning: {w}", file=sys.stderr)


if __name__ == "__main__":
    main()
