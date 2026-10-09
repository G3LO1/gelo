-- Client entry point: Init() then Start() on every module in Controllers.

local controllers = {}
for _, module in script.Controllers:GetChildren() do
	if module:IsA("ModuleScript") then
		controllers[module.Name] = require(module)
	end
end

for name, controller in controllers do
	if controller.Init then
		local ok, err = pcall(controller.Init)
		if not ok then
			warn(`[Client] {name}.Init failed: {err}`)
		end
	end
end

for _, controller in controllers do
	if controller.Start then
		task.spawn(controller.Start)
	end
end
