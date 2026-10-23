--!strict
-- In Studio only: checks that the game started correctly and prints PASS/FAIL lines to Output,
-- plus reminders for things the owner still has to set up (pass/product ids).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Odds = require(Shared.Odds)
local MapLayout = require(Shared.MapLayout)
local MapService = require(script.Parent.MapService)
local PlotService = require(script.Parent.PlotService)

local SelfTest = {}

export type Result = { Name: string, Ok: boolean, Detail: string? }

function SelfTest.Run(): { Result }
	local results: { Result } = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(results, { Name = name, Ok = ok, Detail = detail })
	end

	check("Map built", Workspace:FindFirstChild("Map") ~= nil)
	check("8 plots", #PlotService.All() == Config.MaxPlayers, tostring(#PlotService.All()))
	local nestCount = 0
	for _, zone in Config.Zones do
		nestCount += zone.Nests
	end
	check("Nests", #MapService.Nests == nestCount, #MapService.Nests .. "/" .. nestCount)
	check("Speed gates", #MapService.Gates == #Config.Zones - 1, tostring(#MapService.Gates))
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	check("Remotes", remotes ~= nil and remotes:FindFirstChild("Request") ~= nil)

	local oddsOk = true
	for eggId in Config.Eggs do
		local total = 0
		for _, entry in Odds.EggOdds(eggId, 1) do
			total += entry.Chance
		end
		if math.abs(total - 1) > 1e-6 then
			oddsOk = false
		end
	end
	check("Egg odds sum to 100%", oddsOk)
	check("Zone layout", #MapLayout.Zones == #Config.Zones)
	return results
end

local function missingIds(): { string }
	local missing = {}
	for _, key in Config.PassOrder do
		if (Config.Passes :: any)[key].Id == 0 then
			table.insert(missing, "Pass " .. key)
		end
	end
	for _, key in Config.ProductOrder do
		if (Config.Products :: any)[key].Id == 0 then
			table.insert(missing, "Product " .. key)
		end
	end
	return missing
end

function SelfTest.Init() end

function SelfTest.Start()
	if not RunService:IsStudio() then
		return
	end
	task.defer(function()
		local failed = 0
		for _, result in SelfTest.Run() do
			if result.Ok then
				print("[SelfTest] PASS " .. result.Name)
			else
				failed += 1
				warn("[SelfTest] FAIL " .. result.Name .. (if result.Detail then " (" .. result.Detail .. ")" else ""))
			end
		end
		print(string.format("[SelfTest] %s - %d failed", if failed == 0 then "ALL PASS" else "PROBLEMS FOUND", failed))
		local missing = missingIds()
		if #missing > 0 then
			print("[SelfTest] Not created yet (purchases are simulated in Studio): " .. table.concat(missing, ", "))
		end
	end)
end

return SelfTest
