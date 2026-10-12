--!strict
-- Incubators: eggs wait here until their hatch time (real time, so they also hatch while offline),
-- then the server rolls the slime with the player's current luck.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Odds = require(Shared.Odds)
local EggBuilder = require(Shared.EggBuilder)
local Validate = require(script.Parent.Parent.Logic.Validate)
local ProfileSchema = require(script.Parent.Parent.Logic.ProfileSchema)
local PlayerService = require(script.Parent.PlayerService)
local PlotService = require(script.Parent.PlotService)
local BoostService = require(script.Parent.BoostService)
local SlimeService = require(script.Parent.SlimeService)
local Network = require(script.Parent.Network)

local HatchService = {}

local rng = Random.new()
local function roll(): number
	return rng:NextNumber()
end

-- reserved[player][slot] = thief  (egg is being carried away by a thief right now)
local reserved: { [Player]: { [number]: Player? } } = {}
local eggModels: { [PlotService.PlotState]: { [number]: Model } } = {}
local fullWarned: { [Player]: boolean } = {}

function HatchService.Capacity(player: Player): number
	local session = PlayerService.Get(player)
	if not session then
		return 0
	end
	return Formulas.IncubatorCount(session.Data.IncubatorLevel, BoostService.HasPass(player, "ExtraIncubators"))
end

function HatchService.FreeSlot(player: Player): number?
	local session = PlayerService.Get(player)
	if not session then
		return nil
	end
	local used: { [number]: boolean } = {}
	for _, egg in session.Data.Eggs do
		used[egg.Slot] = true
	end
	for slot = 1, HatchService.Capacity(player) do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

function HatchService.GetEgg(player: Player, slot: number): (number?, ProfileSchema.EggRecord?)
	local session = PlayerService.Get(player)
	if not session then
		return nil, nil
	end
	for index, egg in session.Data.Eggs do
		if egg.Slot == slot then
			return index, egg
		end
	end
	return nil, nil
end

function HatchService.IsReserved(player: Player, slot: number): boolean
	local list = reserved[player]
	if not list then
		return false
	end
	return list[slot] ~= nil
end

function HatchService.Reserve(victim: Player, slot: number, thief: Player)
	reserved[victim] = reserved[victim] or {}
	reserved[victim][slot] = thief
	HatchService.RefreshVisuals(victim)
end

function HatchService.Unreserve(victim: Player, slot: number)
	local list = reserved[victim]
	if list then
		list[slot] = nil
	end
	HatchService.RefreshVisuals(victim)
end

-- Shows eggs in the incubators of a player's plot and publishes timers as attributes
-- (the client renders countdowns from HatchAt, so we don't replicate text every second).
function HatchService.RefreshVisuals(player: Player)
	local session = PlayerService.Get(player)
	local plot = PlotService.Get(player)
	if not session or not plot then
		return
	end
	local models = eggModels[plot] or {}
	eggModels[plot] = models
	local bySlot: { [number]: ProfileSchema.EggRecord } = {}
	for _, egg in session.Data.Eggs do
		bySlot[egg.Slot] = egg
	end
	for _, slot in plot.Incubators do
		local egg = bySlot[slot.Index]
		local isReserved = HatchService.IsReserved(player, slot.Index)
		local model = models[slot.Index]
		local wanted = if egg and not isReserved then egg.Egg else nil
		if model and model:GetAttribute("Egg") ~= wanted then
			model:Destroy()
			models[slot.Index] = nil
			model = nil
		end
		if wanted and not model then
			local newModel = EggBuilder.Build(wanted, 0.9)
			newModel:PivotTo(slot.Anchor * CFrame.new(0, -0.9, 0))
			newModel.Parent = plot.Model
			models[slot.Index] = newModel
		end
		slot.Part:SetAttribute("Egg", if egg then egg.Egg else "")
		slot.Part:SetAttribute("HatchAt", if egg then egg.HatchAt else 0)
		slot.Part:SetAttribute("Reserved", isReserved)
		slot.Part:SetAttribute("OwnerUserId", player.UserId)
		if slot.Label then
			slot.Label.Text = if egg then Config.Eggs[egg.Egg].Name else ""
		end
	end
end

local function clearPlot(plot: PlotService.PlotState)
	local models = eggModels[plot]
	if models then
		for _, model in models do
			model:Destroy()
		end
	end
	eggModels[plot] = nil
	for _, slot in plot.Incubators do
		slot.Part:SetAttribute("Egg", "")
		slot.Part:SetAttribute("HatchAt", 0)
		slot.Part:SetAttribute("Reserved", false)
		slot.Part:SetAttribute("OwnerUserId", 0)
		if slot.Label then
			slot.Label.Text = ""
		end
	end
end

-- Puts an egg into the first free incubator. Returns the slot or nil if full.
function HatchService.AddEgg(player: Player, eggId: string): number?
	local session = PlayerService.Get(player)
	local def = Config.Eggs[eggId]
	if not session or not def then
		return nil
	end
	local slot = HatchService.FreeSlot(player)
	if not slot then
		return nil
	end
	local now = os.time()
	table.insert(session.Data.Eggs, { Slot = slot, Egg = eggId, HatchAt = now + def.HatchSeconds, Duration = def.HatchSeconds })
	HatchService.RefreshVisuals(player)
	PlayerService.MarkDirty(player, true)
	return slot
end

-- Removes an egg (e.g. it was stolen). Returns the removed record.
function HatchService.RemoveEgg(player: Player, slot: number): ProfileSchema.EggRecord?
	local session = PlayerService.Get(player)
	local index, egg = HatchService.GetEgg(player, slot)
	if not session or not index then
		return nil
	end
	table.remove(session.Data.Eggs, index)
	local list = reserved[player]
	if list then
		list[slot] = nil
	end
	HatchService.RefreshVisuals(player)
	PlayerService.MarkDirty(player, true)
	return egg
end

function HatchService.Hatch(player: Player, slot: number): boolean
	local session = PlayerService.Get(player)
	local index, egg = HatchService.GetEgg(player, slot)
	if not session or not index or not egg then
		return false
	end
	if HatchService.IsReserved(player, slot) then
		return false
	end
	if SlimeService.IsFull(player) then
		if not fullWarned[player] then
			fullWarned[player] = true
			Network.Notify(player, "Your slime storage is full! Sell some slimes to keep hatching.", "error")
		end
		return false
	end
	fullWarned[player] = nil
	local luck = BoostService.GetLuck(player)
	local kind, mutation = Odds.Roll(egg.Egg, luck, roll)
	table.remove(session.Data.Eggs, index)
	session.Data.Stats.EggsHatched += 1
	SlimeService.AddSlime(player, kind, mutation, "Hatch")
	HatchService.RefreshVisuals(player)
	PlayerService.AdvanceTutorial(player, 3)
	return true
end

function HatchService.Tick()
	local now = os.time()
	for _, session in PlayerService.All() do
		local due = {}
		for _, egg in session.Data.Eggs do
			if egg.HatchAt <= now then
				table.insert(due, egg.Slot)
			end
		end
		for _, slot in due do
			HatchService.Hatch(session.Player, slot)
		end
	end
end

-- Makes every egg (not being stolen) ready right now.
function HatchService.HatchAllNow(player: Player): number
	local session = PlayerService.Get(player)
	if not session then
		return 0
	end
	local now = os.time()
	local count = 0
	for _, egg in session.Data.Eggs do
		if not HatchService.IsReserved(player, egg.Slot) and egg.HatchAt > now then
			egg.HatchAt = now
			count += 1
		end
	end
	HatchService.RefreshVisuals(player)
	PlayerService.MarkDirty(player, true)
	return count
end

local function skip(player: Player, payload: any): (boolean, string?)
	local session = PlayerService.Get(player)
	local slot = Validate.Integer(payload, 1, 16)
	if not session or not slot then
		return false, "Bad request"
	end
	local _, egg = HatchService.GetEgg(player, slot)
	if not egg then
		return false, "No egg there"
	end
	if HatchService.IsReserved(player, slot) then
		return false, "Someone is stealing that egg!"
	end
	local remaining = egg.HatchAt - os.time()
	local cost = Formulas.SkipCost(remaining)
	if cost <= 0 then
		HatchService.Hatch(player, slot)
		return true
	end
	if session.Data.Gems < cost then
		return false, "You need " .. cost .. " gems"
	end
	session.Data.Gems -= cost
	egg.HatchAt = os.time()
	HatchService.Hatch(player, slot)
	PlayerService.MarkDirty(player, true)
	return true, "Hatched for " .. cost .. " gems"
end

function HatchService.Init()
	Network.Handle("SkipHatch", skip)
	PlayerService.RegisterState("IncubatorCapacity", function(session)
		return HatchService.Capacity(session.Player)
	end)
	PlayerService.RegisterState("ReservedSlots", function(session)
		local list = {}
		local slots: { [number]: Player? } = reserved[session.Player] or {}
		for slot in slots do
			table.insert(list, slot)
		end
		return list
	end)
end

function HatchService.Start()
	PlotService.PlotAssigned:Connect(function(player: Player)
		HatchService.RefreshVisuals(player)
	end)
	PlotService.PlotReleased:Connect(function(player: Player, plot: PlotService.PlotState)
		clearPlot(plot)
		reserved[player] = nil
		fullWarned[player] = nil
	end)
	BoostService.PassesChanged:Connect(function(player: Player)
		HatchService.RefreshVisuals(player)
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			HatchService.Tick()
		end
	end)
end

return HatchService
