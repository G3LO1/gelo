-- Server entry point: creates remotes, then runs Init() on every module in Services
-- (no yielding; own state and registrations only), then Start() on each (events, loops).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

Net.setup()

local services = {}
for _, module in script.Services:GetChildren() do
	if module:IsA("ModuleScript") then
		services[module.Name] = require(module)
	end
end

for name, service in services do
	if service.Init then
		local ok, err = pcall(service.Init)
		if not ok then
			warn(`[Server] {name}.Init failed: {err}`)
		end
	end
end

for _, service in services do
	if service.Start then
		task.spawn(service.Start)
	end
end
