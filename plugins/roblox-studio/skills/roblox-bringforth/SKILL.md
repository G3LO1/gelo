---
name: "roblox-bringforth"
description: "Get 3D models and other assets into a Roblox game without downloading files or clicking through Studio's importer: Claude makes the assets itself (low-poly props, kit pieces, trees, rocks, chests, buildings from primitives with make_model.py, or in Blender through a Blender MCP server), checks them against Roblox limits (20,000 triangles per mesh, 20 MB, formats), uploads FBX/GLB models, images, audio and video through the Roblox Open Cloud Assets API with the API key from an environment variable, waits for the upload operation, and inserts the result into the open Studio place (Studio MCP, or the Bringforth Studio plugin that auto-imports every new upload). Use whenever someone wants to import or upload a model, mesh, texture, decal, sound or video to Roblox, go from Blender to Studio, generate props or assets for a map, or says 'wgraj model', 'zaimportuj z blendera', 'zrób assety', 'bringforth'."
---

# Roblox Bringforth

Goal: from "I need a crate / tree / tower" or a file from Blender to the model standing in the Studio place, with every step checked and nothing clicked in Creator Hub after the API key exists. Claude can make the assets itself: describe, build, look at the preview, fix, upload, insert.

Answer in the user's language; write file names, asset names and code in English.

## 1. Setup (once)
Check the key with `python3 <skill>/scripts/bringforth.py whoami` before anything else. If there is no key, give the user these steps and wait:

1. [create.roblox.com](https://create.roblox.com) > **All tools** > **Open Cloud** > **API Keys** > **Create API Key** (for a group game: the group's API Keys page, the key must be owned by the group that owns the game).
2. Access permissions: **assets**: Read + Write. Add **asset-permissions**: Write too if images, audio or meshes will be used in an experience owned by another creator (`grant`). Monetization keys can be the same key (`game-passes`, `developer-products`, see `roblox-monetization`).
3. Optional: IP allowlist, expiration date. Roblox also auto-expires keys unused for 60 days; `whoami` and every upload warn when the key expires within 14 days.
4. **Save & Generate Key**, then store it outside the code: copy `assets/env.example` to `.env` in the game folder, fill `ROBLOX_API_KEY` (and `ROBLOX_CREATOR_GROUP_ID` for group games), make sure `.gitignore` has `.env`. Or an environment variable (`setx ROBLOX_API_KEY "..."` on Windows, `export` in `~/.zshrc`).

Never ask for the key in the chat, never echo it, never write it into files you create or commit, never put it in Luau. If the user pastes a key anyway, don't repeat it: tell them to delete it in Creator Hub and make a new one.

## 2. Make or collect the assets
Pick the route by what exists:

- **Files from the user** (`.fbx`, `.glb`, `.gltf`, `.rbxm`, `.png`, `.mp3`...): go to step 3. `.obj`, `.blend`, `.stl`, `.dae` are not accepted by Open Cloud: convert in Blender (MCP or the user) to glTF Binary or FBX.
- **Blender MCP connected** (tools with `blender` in the name): model, clean up and export there following `../roblox-animation-vfx/references/blender.md` (units None = 1 stud, applied transforms, one material per mesh, at most 20,000 triangles per mesh, Decimate when over), then run `../roblox-animation-vfx/scripts/blender_check.py` (mode model, `EXPORT_PATH` set) through the code tool so it exports only a clean scene.
- **Claude builds it** (no Blender, or simple stylized props): write a spec and run `scripts/make_model.py spec.json -o models/Name.glb --preview previews/Name.png`. Read `references/modeling.md` first (spec format, proportions in studs, style recipes, kit grid). Then **open the preview image and judge it** (silhouette, proportions, floating or buried parts, colors against the game's palette); fix the spec and rebuild until it looks right. Examples: `assets/examples/lowpoly_tree.json`, `treasure_chest.json`.
- **Textures, decals, icons**: an image generation tool or skill if the session has one (e.g. `codex-image`), Pillow for simple procedural textures; keep them at most 1024x1024.
- **Studio's own generators** (`generate_mesh`, `generate_material` and similar Studio MCP tools) are fine for one-off pieces; they don't need this upload step.

Plan a map's assets as a **kit** (pieces on the map grid, reused many times) and hand the list to `roblox-map-builder`; don't make a unique mesh for everything.

## 3. Check
`python3 <skill>/scripts/bringforth.py check <files...>`: format, 20 MB per file, glTF/GLB parsed (triangles per mesh against 20,000, materials per mesh, external buffers), images under 8000 px (warns above 1024), FBX header (triangles of FBX are checked in Blender with `blender_check.py`), audio/video quotas. Fix every ERROR.

## 4. Upload
```
python3 <skill>/scripts/bringforth.py upload models/*.glb textures/*.png --luau src/shared/Assets.luau
```
- Models (FBX, glTF, GLB, RBXM) upload as **Model** assets (Roblox stores them as packages); images as **Decal** by default (`--type Image` for a plain image asset), audio as **Audio**, video as **Video**.
- Creator: `--group` / `--user`, else `ROBLOX_CREATOR_GROUP_ID` / `ROBLOX_CREATOR_USER_ID`, else the key's owner. It must be whoever owns the game, or the asset can't be used there without `grant`.
- `--max-price 0` (default) refuses any upload fee; raise it only when the user agrees to pay.
- The upload is a long-running operation: the script polls it, prints the asset ID, version and moderation state, and records it in `bringforth.lock.json` (commit it, no secrets). Re-running skips unchanged files; a changed **FBX** becomes a new version of the same asset ID (copies already in the place stay as they are; the plugin inserts the new version); a changed GLB/image becomes a new asset (Open Cloud only updates FBX content), so prefer FBX for models that will keep changing.
- `--luau` writes `Assets.luau` (`Assets.Models.Tree = 123`, `Assets.Images.Lava = "rbxassetid://..."`) for scripts.
- Errors explain themselves (401 key, 403 permission or creator, 400 rejected file or fee); API details in `references/open-cloud-assets.md`.

## 5. Into the place
- **Studio MCP connected**: insert directly (the `insert_asset` tool, or run `game:GetService("InsertService"):LoadAsset(id)` and parent the children to `Workspace.Map.Props`), then screen-capture and adjust scale/position/CollisionFidelity.
- **Bringforth Studio plugin** (auto import, no MCP needed): `bringforth.py install-plugin` once (Windows/macOS; `--dir` elsewhere), restart Studio, run `bringforth.py serve` in the game folder and press **Auto import** in the Bringforth toolbar: every new model upload (and new FBX version) is inserted in front of the camera, into `Workspace.Map.Props` when it exists, selected, as one undo step. **Import latest** inserts the newest one on demand. Studio asks once to allow HTTP requests to 127.0.0.1: allow it. The feed is local only and shows asset IDs and names, nothing secret.
- **Neither**: give the user the printed `LoadAsset` line for the command bar, or Toolbox > Inventory > My Packages.
- Assets of one creator used in another creator's experience (user-owned decal in a group game): `bringforth.py grant <file or id> --universe <universeId>` (asset-permissions write).

After inserting: check the scale against a 5-stud-tall avatar (if the importer scaled a glTF differently, set `unitsPerStud` in the spec once for the whole project, see `references/modeling.md`), anchor static props, set CollisionFidelity (Box/Hull for props, Precise only where needed), and keep static meshes reused rather than duplicated as unique uploads.

## 6. Verify and report
1. `check` clean before upload; the second `upload` run reports SKIP for everything unchanged.
2. In Studio (MCP or the user): the model appears, looks like the preview, right size, no console errors. Never claim it is in the place unless an insert ran.
3. Report: a table of assets (file, type, asset ID, version, moderation), where they were inserted, previews of models Claude made, what is still pending (moderation, `grant`, real textures).
