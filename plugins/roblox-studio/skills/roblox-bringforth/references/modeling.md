# Making assets with make_model.py

`make_model.py` turns a JSON list of primitives into a GLB. It suits low-poly and cartoon props, kit pieces and simple buildings; organic shapes, characters and anything that needs sculpting or textures belong in Blender (MCP) or the Studio generators.

## Spec
```json
{
  "name": "LampPost",
  "pivot": "bottom",
  "unitsPerStud": 1,
  "parts": [
    { "name": "base", "shape": "cylinder", "size": [1.6, 0.4, 1.6], "position": [0, 0.2, 0], "segments": 8, "color": "#3a3d45", "material": "metal" },
    { "name": "pole", "shape": "cylinder", "size": [0.4, 9, 0.4], "position": [0, 4.9, 0], "segments": 6, "color": "#3a3d45", "material": "metal" },
    { "name": "lamp", "shape": "box", "size": [1.2, 1, 1.2], "position": [0, 9.9, 0], "color": "#ffd27a", "material": "neon" }
  ]
}
```
- Units are studs, Y up; `position` is the part's center, `rotation` degrees XYZ (X applied first).
- `pivot`: `bottom` (default, the model's origin is the center of its footprint, on the ground: easiest to place), `center`, or `origin` (keep the spec's coordinates, for kit pieces that must snap to a grid corner).
- Shapes: `box`, `wedge` (slope rises toward -Z), `pyramid`, `cylinder`, `cone`, `sphere`, `ring` (`thickness`). `segments` 3-48: 6-8 reads low-poly, 12-16 round.
- Materials: `plastic`, `wood`, `stone`, `fabric`, `metal`, `glass` (transparent), `neon` (emissive). Parts with the same color + material merge into one mesh (one MeshPart): use few colors.
- `unitsPerStud`: leave 1. If the first upload of the project comes in at the wrong size, measure the factor in Studio once and set it in every spec, rather than rescaling each model by hand.
- Output: GLB with flat normals (hard edges), planar UVs (one tile per 4 studs, so MaterialVariants and textures map sensibly), one material per mesh, checked against 20,000 triangles per mesh. Tested in Blender: imports with the same triangle count and size, passes `blender_check.py`, closed shells.

## Look before uploading
Always render `--preview` and look at the image: it is a 3/4 view from the front-right. Check:
- silhouette reads at a glance (it will often be seen small, on a phone);
- parts touch or overlap a little: nothing floats, nothing sinks so far it disappears;
- proportions against a 5-stud-tall avatar: doors 7-8 studs high and 4-5 wide, steps 1 stud, tables 3, chairs 2, fences 3-4;
- 2-4 colors per prop from the game's palette, one accent color.
Fix the spec and render again. Two or three rounds are normal.

## Style recipes
- **Low-poly nature**: trees as a trunk cylinder (segments 6-7) + 2-3 stacked cones rotated 22.5° from each other; rocks as spheres with segments 5-6 and uneven sizes, slightly sunk into the ground; bushes as 2-3 overlapping low spheres.
- **Cartoon props**: chunky proportions (thicker legs, bigger heads), rounded tops with cylinders turned 90°, metal bands and rims as thin boxes 0.1-0.2 studs proud of the surface, one neon accent (gem, lamp, button).
- **Buildings / kit pieces**: walls 1 stud thick on a 4-stud grid (`pivot: origin`, corner at 0,0,0), window holes made by building the wall from boxes around the opening, roofs as wedges or pyramids, trim as thin boxes in a darker shade.
- **Sci-fi / neon**: dark metal bodies, neon strips as thin boxes, hexagonal cylinders (segments 6).

## Budgets
- Triangles: props usually 50-2,000, hero pieces up to ~10,000; the limit is 20,000 per mesh, but draw calls matter more: few colors (= few meshes), and reuse one uploaded asset many times in the map instead of uploading variants.
- One upload per distinct piece: a kit of 10-20 pieces builds a whole area (`roblox-map-builder`).
