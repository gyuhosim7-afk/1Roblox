--!strict
-- Slime inventory: adding (hatching), pedestal display, coin income into the base bank,
-- collecting coins at the pad, selling and locking slimes.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Build = require(Shared.Build)
local SlimeBuilder = require(Shared.SlimeBuilder)
local MapLayout = require(Shared.MapLayout)
local Validate = require(script.Parent.Parent.Logic.Validate)
local ProfileSchema = require(script.Parent.Parent.Logic.ProfileSchema)
local SlimeInventory = require(script.Parent.Parent.Logic.SlimeInventory)
local PlayerService = require(script.Parent.PlayerService)
local PlotService = require(script.Parent.PlotService)
local BoostService = require(script.Parent.BoostService)
local Network = require(script.Parent.Network)

local SlimeService = {}

local pedestalModels: { [PlotService.PlotState]: { [number]: { Id: string, Model: Model } } } = {}

local function pedestalCount(session: PlayerService.Session): number
	return Formulas.PedestalCount(session.Data.PedestalLevel)
end

function SlimeService.IncomePerSecond(player: Player): number
	local session = PlayerService.Get(player)
	if not session then
		return 0
	end
	return SlimeInventory.Income(session.Data.Slimes, pedestalCount(session)) * BoostService.GetCoinMultiplier(player)
end

function SlimeService.IsFull(player: Player): boolean
	local session = PlayerService.Get(player)
	return session ~= nil and #session.Data.Slimes >= Config.Base.MaxSlimes
end

local function makeLabel(model: Model, kind: string, mutation: string)
	local def = Config.Slimes[kind]
	local body = model.PrimaryPart
	if not def or not body then
		return
	end
	local mutationName = if mutation ~= "None" then (Config.Mutations :: any)[mutation].Name .. " " else ""
	local text = mutationName .. def.Name .. "\n$" .. Format.Number(Formulas.SlimeIncome(kind, mutation)) .. "/s"
	local gui = Build.Billboard(body, text, UDim2.fromScale(6, 1.8), Vector3.new(0, 2.6 * SlimeBuilder.Scale(kind), 0), 45)
	local label = gui:FindFirstChild("Label") :: TextLabel
	label.TextColor3 = Build.Hex(Config.Rarities[def.Rarity].Color)
end

-- Rebuilds pedestal models for a player's plot to show their best slimes.
function SlimeService.Arrange(player: Player)
	local session = PlayerService.Get(player)
	local plot = PlotService.Get(player)
	if not session or not plot then
		return
	end
	local chosen = SlimeInventory.PedestalSlimes(session.Data.Slimes, pedestalCount(session))
	local models = pedestalModels[plot] or {}
	pedestalModels[plot] = models
	for slotIndex, slot in plot.Pedestals do
		local slime = chosen[slotIndex]
		local existing = models[slotIndex]
		if existing and (not slime or existing.Id ~= slime.Id) then
			existing.Model:Destroy()
			models[slotIndex] = nil
			existing = nil
		end
		if slime and not existing then
			local model = SlimeBuilder.Build(slime.Kind, slime.Mutation)
			model.Name = "Slime_" .. slime.Id
			model:PivotTo(slot.Anchor)
			makeLabel(model, slime.Kind, slime.Mutation)
			model:SetAttribute("OwnerUserId", player.UserId)
			model:SetAttribute("SlimeId", slime.Id)
			model:AddTag("PedestalSlime")
			model.Parent = plot.Model
			models[slotIndex] = { Id = slime.Id, Model = model }
		end
	end
end

local function clearPlot(plot: PlotService.PlotState)
	local models = pedestalModels[plot]
	if models then
		for _, entry in models do
			entry.Model:Destroy()
		end
	end
	pedestalModels[plot] = nil
end

-- Adds a slime to the player's inventory. Handles first-discovery gem rewards.
-- Returns the new record, or nil if the inventory is full (force = paid items may exceed the cap).
function SlimeService.AddSlime(
	player: Player,
	kind: string,
	mutation: string,
	source: string?,
	force: boolean?
): ProfileSchema.SlimeRecord?
	local session = PlayerService.Get(player)
	local def = Config.Slimes[kind]
	if not session or not def then
		return nil
	end
	local data = session.Data
	if #data.Slimes >= Config.Base.MaxSlimes and not force then
		return nil
	end
	local record: ProfileSchema.SlimeRecord = {
		Id = ProfileSchema.NextSlimeId(data),
		Kind = kind,
		Mutation = mutation,
		Locked = false,
	}
	table.insert(data.Slimes, record)

	local isNew = not data.Discovered[kind]
	local gems = 0
	if isNew then
		data.Discovered[kind] = true
		gems = Config.Rarities[def.Rarity].DiscoveryGems
		data.Gems += gems
	end
	if mutation ~= "None" then
		data.Discovered[kind .. "_" .. mutation] = true
	end

	SlimeService.Arrange(player)
	PlayerService.MarkDirty(player, true)
	Network.Effect(player, "Hatch", {
		Kind = kind,
		Mutation = mutation,
		New = isNew,
		Gems = gems,
		Source = source or "Hatch",
		Id = record.Id,
	})
	local order = Config.Rarities[def.Rarity].Order
	local mutationName = if mutation ~= "None" then (Config.Mutations :: any)[mutation].Name .. " " else ""
	if order >= 5 or mutation == "Rainbow" then
		Network.NotifyAll(player.DisplayName .. " hatched a " .. mutationName .. def.Name .. "!", "rare")
	end
	return record
end

function SlimeService.Collect(player: Player): number
	local session = PlayerService.Get(player)
	if not session then
		return 0
	end
	local amount = math.floor(session.Data.Bank)
	if amount < 1 then
		return 0
	end
	session.Data.Bank -= amount
	session.Data.Coins += amount
	PlayerService.MarkDirty(player, false)
	Network.Effect(player, "Collect", { Amount = amount })
	PlayerService.AdvanceTutorial(player, 4)
	return amount
end

local function updateBankLabel(player: Player, session: PlayerService.Session)
	local plot = PlotService.Get(player)
	if plot then
		plot.BankLabel.Text = "COLLECT\n$" .. Format.Number(math.floor(session.Data.Bank))
	end
end

function SlimeService.Tick(dt: number)
	for _, session in PlayerService.All() do
		local player = session.Player
		local income = SlimeService.IncomePerSecond(player)
		if income > 0 then
			session.Data.Bank += income * dt
			if BoostService.HasPass(player, "AutoCollect") then
				local amount = math.floor(session.Data.Bank)
				session.Data.Bank -= amount
				session.Data.Coins += amount
			end
			PlayerService.MarkDirty(player, false)
		end
		updateBankLabel(player, session)
	end
end

-- Collect when the owner stands on their pad.
function SlimeService.CheckPads()
	local pad = MapLayout.PlotLocal.CollectPad
	for _, session in PlayerService.All() do
		local player = session.Player
		local plot = PlotService.Get(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if plot and root then
			local lx, lz = MapLayout.WorldToPlot(plot.Layout, root.Position.X, root.Position.Z)
			local dy = root.Position.Y
			if math.abs(lx - pad.X) <= pad.Size / 2 + 1 and math.abs(lz - pad.Z) <= pad.Size / 2 + 1 and dy < 10 then
				if SlimeService.Collect(player) > 0 then
					updateBankLabel(player, session)
				end
			end
		end
	end
end

local function sell(player: Player, payload: any): (boolean, string?)
	local session = PlayerService.Get(player)
	local id = Validate.String(payload, 16)
	if not session or not id then
		return false, "Bad request"
	end
	local index, slime = SlimeInventory.Find(session.Data.Slimes, id)
	if not index or not slime then
		return false, "Slime not found"
	end
	if slime.Locked then
		return false, "Unlock this slime first"
	end
	local price = Formulas.SellPrice(slime.Kind, slime.Mutation)
	table.remove(session.Data.Slimes, index)
	session.Data.Coins += price
	SlimeService.Arrange(player)
	PlayerService.MarkDirty(player, true)
	return true, "Sold for $" .. Format.Number(price)
end

local function sellAllBelow(player: Player, payload: any): (boolean, string?)
	local session = PlayerService.Get(player)
	local maxOrder = Validate.Integer(payload, 1, #Config.RarityOrder)
	if not session or not maxOrder then
		return false, "Bad request"
	end
	local toSell = SlimeInventory.SellableBelow(session.Data.Slimes, pedestalCount(session), maxOrder)
	if #toSell == 0 then
		return false, "Nothing to sell"
	end
	local sellIds: { [string]: boolean } = {}
	local total = 0
	for _, slime in toSell do
		sellIds[slime.Id] = true
		total += Formulas.SellPrice(slime.Kind, slime.Mutation)
	end
	local kept = {}
	for _, slime in session.Data.Slimes do
		if not sellIds[slime.Id] then
			table.insert(kept, slime)
		end
	end
	session.Data.Slimes = kept
	session.Data.Coins += total
	SlimeService.Arrange(player)
	PlayerService.MarkDirty(player, true)
	return true, "Sold " .. #toSell .. " slimes for $" .. Format.Number(total)
end

local function toggleLock(player: Player, payload: any): (boolean, string?)
	local session = PlayerService.Get(player)
	local id = Validate.String(payload, 16)
	if not session or not id then
		return false, "Bad request"
	end
	local _, slime = SlimeInventory.Find(session.Data.Slimes, id)
	if not slime then
		return false, "Slime not found"
	end
	slime.Locked = not slime.Locked
	PlayerService.MarkDirty(player, true)
	return true, if slime.Locked then "Locked" else "Unlocked"
end

function SlimeService.Init()
	Network.Handle("SellSlime", sell)
	Network.Handle("SellAllBelow", sellAllBelow)
	Network.Handle("LockSlime", toggleLock)
	PlayerService.RegisterState("IncomePerSecond", function(session)
		return SlimeService.IncomePerSecond(session.Player)
	end)
	PlayerService.RegisterState("PedestalIds", function(session)
		local ids = {}
		for _, slime in SlimeInventory.PedestalSlimes(session.Data.Slimes, pedestalCount(session)) do
			table.insert(ids, slime.Id)
		end
		return ids
	end)
end

function SlimeService.Start()
	PlotService.PlotAssigned:Connect(function(player: Player)
		SlimeService.Arrange(player)
	end)
	PlotService.PlotReleased:Connect(function(_player: Player, plot: PlotService.PlotState)
		clearPlot(plot)
	end)
	BoostService.PassesChanged:Connect(function(player: Player)
		PlayerService.MarkDirty(player, true)
	end)
	task.spawn(function()
		while true do
			local dt = task.wait(1)
			SlimeService.Tick(math.min(dt, 3))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			SlimeService.CheckPads()
		end
	end)
end

return SlimeService
