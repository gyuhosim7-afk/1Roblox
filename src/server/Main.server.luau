--!strict
-- Server entry point: initialises then starts every service in dependency order.

local Services = script.Parent:WaitForChild("Services")

local ORDER = {
	"DataService",
	"Network",
	"PlayerService",
	"BoostService",
	"MapService",
	"PlotService",
	"SpeedService",
	"SlimeService",
	"HatchService",
	"EggService",
	"GuardService",
	"UpgradeService",
	"StealService",
}

local loaded = {}
for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	if module then
		loaded[name] = (require :: any)(module)
	else
		warn("[Main] Missing service " .. name)
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if service and service.Init then
		service.Init()
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if service and service.Start then
		service.Start()
	end
end

print("[Main] Server started: " .. #ORDER .. " services")
