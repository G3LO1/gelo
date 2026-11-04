# Island recipe (low-poly island ~200x200, verified in Studio)

- Island on Terrain: delete Baseplate, FillBlock in 4-stud columns; height = radial falloff + big Gaussian hill + 2 octaves math.noise; irregular coast radius via noise on angle; materials by height/slope: Sand beach, Rock steep, Grass top, Ground along the path.
- Water: ocean ring strips PLUS a Sand seabed underneath, else hard seam at the coast.
- Faceted canopy: MANY small/medium rotated cubes in an ellipsoid, 3-4 green shades, lowest mass below the widest point. One huge cube = blocky; thin stack = lollipop. Trunk = crossed blocks + root buttresses, pivot at base, bury 0.5-1 stud.
- Scatter: raycast Terrain, Grass only, Normal.Y >= ~0.78-0.86, min spacing ~8, exclude path/landmark/spawn, grove centers. First pass is usually too sparse: do a denser second pass. Target ~75 trees / 26 rocks / 19 bushes per 200x200.
- Spawn: search the flattest spot (minimise height spread across pad corners), re-screenshot to confirm it sits flush.
- Screenshots: use player-height cameras outside canopy blocks.
- Final checks that worked: 0 unanchored parts, Pathfinding Success spawn->goal, playtest with clean console.

The scatter step is `assets/Scatter.luau` (seeded, slope/spacing/exclusion aware); the final checks are `scripts/validate_map.luau`.
