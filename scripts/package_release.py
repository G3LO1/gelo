#!/usr/bin/env python3
"""Builds the release files for a tag (used by .github/workflows/release.yml; runs locally too).

    python3 scripts/package_release.py v0.10.0 out/

Writes to out/:
    gelo-chatgpt-pack-<tag>.zip   ChatGPT / Gemini / Claude.ai pack: instructions + knowledge files + START-HERE.md
    gelo-full-<tag>.md            everything in one file, for any LLM's system prompt
    gelo-skills-<tag>.zip         the skill folders, for .claude/skills or .agents/skills
    gelo-icon.png                 the plugin icon (e.g. the Custom GPT profile picture)
"""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "llm" / "dist"
SKILLS = ROOT / "plugins" / "roblox-studio" / "skills"
PLUGIN = ROOT / "plugins" / "roblox-studio" / ".claude-plugin" / "plugin.json"
ICON = PLUGIN.parent / "icon.png"

START_HERE = """# gelo {tag}: pack for ChatGPT, Gemini, Claude.ai and any LLM

Call it with `/gelo <task>` or `@gelo <task>`; `/gelo` alone shows the menu.

## ChatGPT (Custom GPT, then @gelo in any chat)
1. ChatGPT -> GPTs -> Create -> Configure. Name: gelo
2. Instructions: paste the whole of 1-instructions/gelo-instructions.md
3. Knowledge: upload every file from 2-knowledge/
4. Capabilities: Web Search and Code Interpreter on
5. Conversation starters: /gelo, /gelo idea , /gelo audit, /gelo launch
6. Profile picture: upload gelo-icon.png
7. Save. In any other ChatGPT chat (web), type @ and pick gelo.

## Gemini (Gem)
Gems -> New Gem: instructions from 1-instructions/gelo-instructions.md, knowledge files from 2-knowledge/.

## Claude.ai (Project)
Project instructions from 1-instructions/gelo-instructions.md, project knowledge from 2-knowledge/.

## Any other model (API, Open WebUI, LM Studio, Ollama, ...)
Large context (64k+ tokens): use gelo-full-{tag}.md from the release as the system prompt.
Otherwise: gelo-instructions.md as the system prompt, 2-knowledge/ as documents.

Scripts and assets the skills mention: https://github.com/G3LO1/gelo/tree/{tag}/plugins/roblox-studio/skills
More: https://github.com/G3LO1/gelo/blob/{tag}/llm/README.md
MIT License, (c) G3LO1.
"""


def add(zf: zipfile.ZipFile, path: Path, arcname: str) -> None:
    # Fixed timestamps and permissions so the same sources give the same archive.
    info = zipfile.ZipInfo(arcname, date_time=(2026, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = (0o755 if path.stat().st_mode & 0o111 else 0o644) << 16
    zf.writestr(info, path.read_bytes())


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    tag, out = sys.argv[1], Path(sys.argv[2])
    version = json.loads(PLUGIN.read_text(encoding="utf-8"))["version"]
    if tag != f"v{version}":
        print(f"ERROR: tag {tag} but plugin.json version is {version}", file=sys.stderr)
        return 1
    out.mkdir(parents=True, exist_ok=True)

    top = "gelo-chatgpt-pack"
    knowledge = sorted((DIST / "knowledge").glob("*.md"))
    if not knowledge:
        print("ERROR: llm/dist/knowledge is empty; run python3 llm/build.py", file=sys.stderr)
        return 1
    pack = out / f"{top}-{tag}.zip"
    with zipfile.ZipFile(pack, "w") as zf:
        info = zipfile.ZipInfo(f"{top}/START-HERE.md", date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        zf.writestr(info, START_HERE.format(tag=tag))
        add(zf, DIST / "gelo-instructions.md", f"{top}/1-instructions/gelo-instructions.md")
        for k in knowledge:
            add(zf, k, f"{top}/2-knowledge/{k.name}")
        add(zf, ICON, f"{top}/gelo-icon.png")
        add(zf, ROOT / "LICENSE", f"{top}/LICENSE")

    full = out / f"gelo-full-{tag}.md"
    full.write_bytes((DIST / "gelo-full.md").read_bytes())

    skills = out / f"gelo-skills-{tag}.zip"
    with zipfile.ZipFile(skills, "w") as zf:
        for p in sorted(SKILLS.rglob("*")):
            if p.is_file():
                add(zf, p, f"skills/{p.relative_to(SKILLS).as_posix()}")
        add(zf, ROOT / "LICENSE", "skills/LICENSE")

    icon = out / "gelo-icon.png"
    icon.write_bytes(ICON.read_bytes())

    for p in (pack, full, skills, icon):
        print(f"{p.name}  {p.stat().st_size:,} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
