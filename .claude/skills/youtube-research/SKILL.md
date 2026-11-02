---
name: "youtube-research"
description: "Research YouTube tutorials to improve this repo's Roblox skills: search videos, pull full transcripts with tools/yt_research.py, verify claims against Roblox docs, and fold the findings into a skill's references with sources. Use when asked to learn from YouTube, tutorials or videos, 'poszukaj na youtube', or to improve/extend a skill (lighting, terrain, maps, scripting, UI, VFX...) with community know-how."
---

# YouTube research for the plugin

Development tool for this repo (not shipped in the plugin). Goal: turn what good tutorials teach into verified,
sourced guidance inside `plugins/roblox-studio/skills/<skill>/references/*.md`.

## Tool

```
pip install yt-dlp                       # once per session
python3 tools/yt_research.py search "roblox studio <topic>" -n 10 --details    # id, date, length, views, channel, title
python3 tools/yt_research.py transcript ID [ID...] -o "$SCRATCH/<topic>"      # one Markdown file per video
```

- Transcripts: header (title, channel, date, views, captions manual/auto), chapters, text in ~30 s paragraphs
  with `[mm:ss](url&t=..s)` deep links. Auto captions have no punctuation guarantees and mishear names
  ("vetri lighting" = volumetric): read for meaning.
- Write transcripts to the scratchpad or the git-ignored `research/` folder; never commit them (they are other
  people's words).
- Cloud IPs sometimes get "Sign in to confirm you're not a bot": `transcript` retries with back-off and waits
  `--sleep` seconds between videos; keep batches <= ~20, rerun SKIPs later. `youtube-transcript-api` is blocked
  from cloud IPs; yt-dlp is not (as of 2026-11).
- If youtube.com is unreachable, the environment's network policy must allow `youtube.com` and `www.youtube.com`
  (subtitles come from youtube.com too; `*.googlevideo.com` is only for video files). Perplexity search with `search_domain_filter:
  ["youtube.com"]` is a fallback that returns transcript excerpts.

## Process

1. **Scope**: which skill and which questions. Read that skill's SKILL.md and references first so research fills
   gaps instead of repeating what's there.
2. **Search wide**: 6-12 queries (beginner + advanced + per style/genre + "performance" + "mistakes"), `--details`
   for dates. Prefer recent (last ~2 years; Roblox changes fast), high views or known builders, and a mix of
   channels. Drop clickbait with no content and videos older than an API change (e.g. Lighting.Technology ->
   LightingStyle).
3. **Pull 10-20 transcripts** and read all of them in full.
4. **Extract**: steps/order of work, concrete values, tricks, warnings, contradictions. Count how many independent
   tutorials agree.
5. **Verify** against Roblox docs: `https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/`
   (`reference/engine/classes/<Class>.yaml`, guides like `environment/lighting.md`,
   `performance-optimization/improve.md`). Label each point: **[docs]** documented, **[tut xN]** consensus of N
   tutorials, **[unverified]** single claim not confirmed. Fix outdated advice (deprecated APIs) instead of copying it.
   When Studio MCP tools are connected, test risky claims in Studio.
6. **Write** `references/<topic>.md` in the skill: workflow, property meanings, techniques, presets credited to their
   tutorial, original example code (don't copy code from videos), performance, common mistakes, and a **Sources**
   list (channel, title, YYYY-MM, URL). Paraphrase; no long quotes.
7. **Wire it in**: link the reference from SKILL.md where the step happens; correct SKILL.md rules the research
   proved wrong; keep SKILL.md short.
8. **Ship**: bump `version` in `plugins/roblox-studio/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
   (equal), run `python3 tests/yt-research/test_yt_research.py` if the tool changed, commit with the topic and number
   of sources.
