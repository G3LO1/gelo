--!nocheck
-- Lighting + post-processing presets for the styles in references/styles.md.
--
--   local LightingPresets = require(path.to.LightingPresets)   -- or paste into execute_luau
--   local report = LightingPresets.apply(game:GetService("Lighting"), "LowPoly")
--   print(report.set, report.skipped, report.removed)
--
-- apply() never stacks effects: it reuses the Bloom / Atmosphere / ColorCorrection / SunRays
-- already in Lighting (place templates ship with them), deletes duplicates of the same class,
-- and creates only what is missing. Sky is never touched. Properties the running environment
-- cannot write (for example LightingStyle on an old Studio) are listed in report.skipped
-- instead of throwing. Values are starting points: tune against screenshots.

local LightingPresets = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function hex(code)
	local r, g, b = string.match(code, "^#?(%x%x)(%x%x)(%x%x)$")
	return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
end

-- lighting: properties of Lighting; enums are given by name. effects: class -> properties.
-- strip: effect classes removed because the style wants none of them.
LightingPresets.Presets = {
	LowPoly = {
		description = "Soft faceted look: related swatches, gentle bloom, little haze.",
		lighting = {
			LightingStyle = "Soft",
			ClockTime = 14,
			Brightness = 2,
			Ambient = hex("#697A83"),
			OutdoorAmbient = hex("#A9C5C5"),
			ShadowSoftness = 0.35,
		},
		effects = {
			BloomEffect = { Intensity = 0.08, Size = 20, Threshold = 1.5 },
			Atmosphere = { Density = 0.12, Haze = 0.2 },
			SunRaysEffect = { Intensity = 0.05, Spread = 0.25 },
		},
	},
	Cartoon = {
		description = "Tycoon / obby / cartoon: bright, saturated, soft shadows.",
		lighting = {
			LightingStyle = "Soft",
			ClockTime = 14,
			Brightness = 2.5,
			Ambient = hex("#9AA6B6"),
			OutdoorAmbient = hex("#C8DDF0"),
		},
		effects = {
			ColorCorrectionEffect = { Saturation = 0.08 },
			BloomEffect = { Intensity = 0.12, Size = 24, Threshold = 1.6 },
			Atmosphere = { Density = 0.08 },
		},
	},
	Realistic = {
		description = "Daylight realism: prioritized lighting, restrained contrast.",
		lighting = {
			LightingStyle = "Realistic",
			PrioritizeLightingQuality = true,
			ClockTime = 14,
			Brightness = 2.2,
			ExposureCompensation = -0.1,
			ShadowSoftness = 0.35,
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 1,
			Ambient = rgb(55, 58, 62),
			OutdoorAmbient = rgb(118, 125, 132),
		},
		effects = {
			Atmosphere = { Density = 0.22, Haze = 0.8, Color = rgb(195, 210, 225) },
			ColorCorrectionEffect = { Contrast = 0.04, Saturation = -0.04 },
			BloomEffect = { Intensity = 0.12, Size = 18, Threshold = 1.8 },
		},
	},
	Horror = {
		description = "Horror / Backrooms: dim, sickly tint, readable without a flashlight.",
		lighting = {
			LightingStyle = "Realistic",
			PrioritizeLightingQuality = true,
			ClockTime = 0,
			Brightness = 1.4,
			Ambient = rgb(58, 53, 40),
			OutdoorAmbient = rgb(65, 61, 47),
		},
		effects = {
			Atmosphere = { Density = 0.12, Haze = 0.6, Color = rgb(196, 184, 135) },
			ColorCorrectionEffect = { Contrast = 0.04, Saturation = -0.12 },
			BloomEffect = { Intensity = 0.12, Size = 18, Threshold = 1.2 },
		},
	},
	Neon = {
		description = "Neon / cyberpunk / sci-fi: dark scene, accent lights, strong bloom.",
		lighting = {
			LightingStyle = "Realistic",
			PrioritizeLightingQuality = true,
			ClockTime = 1,
			Brightness = 1.5,
			Ambient = hex("#1A2030"),
			OutdoorAmbient = hex("#30304A"),
		},
		effects = {
			Atmosphere = { Density = 0.28, Haze = 1 },
			BloomEffect = { Intensity = 0.3, Size = 28, Threshold = 0.9 },
			ColorCorrectionEffect = { Contrast = 0.1 },
		},
	},
	GoldenHour = {
		description = "Fantasy / nature at golden hour: warm low sun, golden haze.",
		lighting = {
			LightingStyle = "Soft",
			ClockTime = 17,
			Brightness = 2,
			OutdoorAmbient = rgb(145, 125, 105),
		},
		effects = {
			Atmosphere = { Density = 0.28, Haze = 1.2, Color = rgb(215, 188, 145) },
			BloomEffect = { Intensity = 0.12, Size = 22, Threshold = 1.6 },
		},
	},
	Tropical = {
		description = "Tropical: bright, teal-green air.",
		lighting = { LightingStyle = "Soft", ClockTime = 13, Brightness = 2.4 },
		effects = {
			Atmosphere = { Density = 0.32, Haze = 1.6, Color = rgb(183, 224, 212) },
			BloomEffect = { Intensity = 0.1, Size = 22, Threshold = 1.6 },
		},
	},
	Snow = {
		description = "Snow / ice: cold, desaturated, early sun.",
		lighting = { LightingStyle = "Soft", ClockTime = 11, Brightness = 2.2 },
		effects = {
			Atmosphere = { Density = 0.3, Haze = 1.2, Color = rgb(215, 225, 235) },
			ColorCorrectionEffect = { Saturation = -0.12 },
		},
	},
	Desert = {
		description = "Desert: late sun, heavy sand haze.",
		lighting = { LightingStyle = "Soft", ClockTime = 15, Brightness = 2.4 },
		effects = {
			Atmosphere = { Density = 0.3, Haze = 2, Color = rgb(207, 174, 116) },
			BloomEffect = { Intensity = 0.1, Size = 22, Threshold = 1.7 },
		},
	},
	PostApoc = {
		description = "Post-apocalypse: dim, washed out, high contrast.",
		lighting = { LightingStyle = "Realistic", PrioritizeLightingQuality = true, ClockTime = 16, Brightness = 1.3 },
		effects = {
			Atmosphere = { Density = 0.3, Haze = 1.6, Color = rgb(170, 160, 140) },
			ColorCorrectionEffect = { Contrast = 0.14, Saturation = -0.35 },
		},
	},
	Retro = {
		description = "Classic / retro: flat gray ambient, no post-processing.",
		lighting = {
			LightingStyle = "Soft",
			ClockTime = 14,
			Brightness = 1.75,
			Ambient = rgb(120, 120, 120),
			OutdoorAmbient = rgb(120, 120, 120),
		},
		effects = {},
		strip = { "BloomEffect", "SunRaysEffect", "DepthOfFieldEffect", "ColorCorrectionEffect" },
	},
	PS1 = {
		description = "PS1: dark-ish, desaturated, light fog.",
		lighting = {
			LightingStyle = "Soft",
			ClockTime = 14,
			Brightness = 1,
			ExposureCompensation = -0.2,
		},
		effects = {
			ColorCorrectionEffect = { Saturation = -0.18 },
			Atmosphere = { Density = 0.2, Haze = 0 },
		},
		strip = { "BloomEffect", "SunRaysEffect", "DepthOfFieldEffect" },
	},
}

function LightingPresets.names()
	local list = {}
	for name in LightingPresets.Presets do
		table.insert(list, name)
	end
	table.sort(list)
	return list
end

local function setProperty(instance, property, value, report, label)
	local ok, err = pcall(function()
		if type(value) == "string" and property == "LightingStyle" then
			instance.LightingStyle = Enum.LightingStyle[value]
		else
			instance[property] = value
		end
	end)
	if ok then
		report.set += 1
	else
		table.insert(report.skipped, `{label}.{property}: {tostring(err)}`)
	end
end

function LightingPresets.apply(lighting, presetName)
	local preset = LightingPresets.Presets[presetName]
	if not preset then
		error(`unknown lighting preset "{presetName}". Available: {table.concat(LightingPresets.names(), ", ")}`, 2)
	end
	local report = { preset = presetName, set = 0, skipped = {}, removed = {}, created = {} }

	for property, value in preset.lighting do
		setProperty(lighting, property, value, report, "Lighting")
	end

	-- One instance per effect class: reuse the first, delete the rest.
	local function destroyExtras(className, keep)
		for _, child in lighting:GetChildren() do
			if child.ClassName == className and child ~= keep then
				table.insert(report.removed, `{className} "{child.Name}" (duplicate)`)
				child:Destroy()
			end
		end
	end

	for className, properties in preset.effects do
		local effect = lighting:FindFirstChildOfClass(className)
		if not effect then
			effect = Instance.new(className)
			effect.Parent = lighting
			table.insert(report.created, className)
		end
		destroyExtras(className, effect)
		for property, value in properties do
			setProperty(effect, property, value, report, className)
		end
	end

	for _, className in preset.strip or {} do
		for _, child in lighting:GetChildren() do
			if child.ClassName == className then
				table.insert(report.removed, `{className} "{child.Name}" (style wants none)`)
				child:Destroy()
			end
		end
	end
	return report
end

return LightingPresets
