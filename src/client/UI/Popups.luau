--!strict
-- Popups: hatch reveal (HatchReveal), offline earnings, the Royal Egg odds screen
-- (shown before any purchase) and the odds panel that appears near a nest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Odds = require(Shared.Odds)
local Theme = require(script.Parent.Theme)
local OddsView = require(script.Parent.OddsView)
local HatchReveal = require(script.Parent.HatchReveal)

local Popups = {}

local screen: ScreenGui? = nil
local topStack: Frame? = nil

function Popups.Mount(gui: ScreenGui, stack: Frame)
	screen = gui
	HatchReveal.Mount(gui)
	topStack = stack
end

-- Hatch reveal (see HatchReveal.luau) ---------------------------------------------
function Popups.Hatch(info: any)
	HatchReveal.Show(info)
end

-- Simple message popup -----------------------------------------------------------
function Popups.Message(title: string, text: string, color: Color3?)
	local gui = screen
	if not gui then
		return
	end
	local frame = Theme.Frame({
		Name = "MessagePopup",
		Size = UDim2.fromOffset(440, 240),
		Position = UDim2.fromScale(0.5, 0.48),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.Background,
		Radius = 20,
		Parent = gui,
	})
	frame.ZIndex = 20
	Theme.AutoScale(frame)
	local titleLabel = Theme.Text(frame, title, { MaxSize = 32, Color = color or Theme.Colors.Gold })
	titleLabel.Size = UDim2.new(1, -20, 0, 50)
	titleLabel.Position = UDim2.fromOffset(10, 10)
	local body = Theme.Text(frame, text, { MaxSize = 24 })
	body.Size = UDim2.new(1, -30, 0, 90)
	body.Position = UDim2.fromOffset(15, 64)
	Theme.Button(frame, "OK", Theme.Colors.Green, function()
		frame:Destroy()
	end, { Size = UDim2.fromOffset(160, 56), Position = UDim2.new(0.5, 0, 1, -14), AnchorPoint = Vector2.new(0.5, 1) })
end

-- Royal Egg odds (must be seen before buying) -------------------------------------
local royalFrame: Frame? = nil

function Popups.RoyalOdds(state: any, request: (string, any?) -> ())
	local gui = screen
	if not gui then
		return
	end
	if royalFrame then
		royalFrame:Destroy()
	end
	local frame = Theme.Frame({
		Name = "RoyalOdds",
		Size = UDim2.fromOffset(560, 520),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.Background,
		Radius = 20,
		Parent = gui,
	})
	royalFrame = frame
	frame.ZIndex = 20
	Theme.AutoScale(frame)
	local zone = Config.Zones[math.clamp(state.Data.BestZone, 1, #Config.Zones)]
	local luck = state.Luck or 1
	local title =
		Theme.Text(frame, "Royal Egg - " .. zone.Name .. " slimes", { MaxSize = 28, Color = Theme.Colors.Gold })
	title.Size = UDim2.new(1, -70, 0, 44)
	title.Position = UDim2.fromOffset(10, 8)
	Theme.Button(frame, "X", Theme.Colors.Red, function()
		frame:Destroy()
		royalFrame = nil
	end, { Size = UDim2.fromOffset(46, 46), Position = UDim2.new(1, -8, 0, 8), AnchorPoint = Vector2.new(1, 0) })
	local info = Theme.Text(
		frame,
		"Rare or better guaranteed. " .. OddsView.LuckText(luck) .. ". " .. OddsView.Disclaimer,
		{ MaxSize = 18, Color = Theme.Colors.SubText }
	)
	info.Size = UDim2.new(1, -20, 0, 40)
	info.Position = UDim2.fromOffset(10, 52)
	local list = Theme.Scroll(frame, UDim2.new(1, -20, 1, -170), UDim2.fromOffset(10, 96))
	Theme.List(list, 5)
	OddsView.Build(
		list,
		Odds.RoyalOdds(state.Data.BestZone, luck),
		Odds.MutationOdds(luck, Config.RoyalEgg.MutationLuckBonus),
		nil,
		0
	)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -20, 0, 60)
	row.Position = UDim2.new(0, 10, 1, -66)
	row.Parent = frame
	Theme.List(row, 10, true)
	Theme.Button(row, "Buy R$ " .. Config.Products.RoyalEgg.Price, Theme.Colors.Green, function()
		request("BuyProduct", "RoyalEgg")
	end, { Size = UDim2.fromOffset(250, 58), LayoutOrder = 1 })
	local gemButton = Theme.Button(row, "Buy " .. Config.GemShop.RoyalEgg .. " Gems", Theme.Colors.Blue, function()
		request("BuyWithGems", "RoyalEgg")
	end, { Size = UDim2.fromOffset(250, 58), LayoutOrder = 2 })
	Theme.SetButtonEnabled(gemButton, state.Data.Gems >= Config.GemShop.RoyalEgg, Theme.Colors.Blue)
end

-- Nest odds panel (sits in the HUD's top stack, two compact columns) -----------------------
local nestPanel: Frame? = nil
local nestPanelKey: string? = nil

function Popups.NestOdds(eggId: string?, state: any?)
	local stack = topStack
	if not stack then
		return
	end
	local luck = if state then state.Luck or 1 else 1
	local key = if eggId then eggId .. "@" .. tostring(luck) else nil
	if key == nestPanelKey then
		return
	end
	nestPanelKey = key
	if nestPanel then
		nestPanel:Destroy()
		nestPanel = nil
	end
	if not eggId or not state then
		return
	end
	local egg = Config.Eggs[eggId]
	local entries = Odds.EggOdds(eggId, luck)
	local rows = math.ceil(#entries / 2) + 1
	local frame = Theme.Frame({
		Name = "NestOdds",
		Size = UDim2.fromOffset(600, 34 + rows * 26),
		Color = Theme.Colors.Background,
		Radius = 14,
		LayoutOrder = 4,
		Parent = stack,
	})
	frame.BackgroundTransparency = 0.15
	nestPanel = frame
	local title =
		Theme.Text(frame, egg.Name .. " odds" .. (if luck > 1 then "  (Luck x" .. Format.Number(luck) .. ")" else ""), {
			MaxSize = 18,
			Color = Theme.Hex(egg.SpotColor),
		})
	title.Size = UDim2.new(1, -16, 0, 26)
	title.Position = UDim2.fromOffset(8, 4)
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, -12, 1, -34)
	grid.Position = UDim2.fromOffset(6, 30)
	grid.Parent = frame
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(290, 24)
	layout.CellPadding = UDim2.fromOffset(6, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for index, entry in entries do
		local def = Config.Slimes[entry.Slime]
		local known = state.Data.Discovered[entry.Slime] == true
		local cell = Theme.Text(
			grid,
			(if known then def.Name else "???") .. " (" .. def.Rarity .. "): " .. Format.Percent(entry.Chance),
			{
				MaxSize = 16,
				Color = Theme.Hex(Config.Rarities[def.Rarity].Color),
				Align = Enum.TextXAlignment.Left,
				LayoutOrder = index,
			}
		)
		cell.Size = UDim2.fromOffset(290, 24)
	end
	local mutations = {}
	for _, m in Odds.MutationOdds(luck) do
		if m.Mutation ~= "None" then
			table.insert(mutations, (Config.Mutations :: any)[m.Mutation].Name .. " " .. Format.Percent(m.Chance))
		end
	end
	local mutationCell = Theme.Text(grid, "Mutations: " .. table.concat(mutations, ", "), {
		MaxSize = 16,
		Color = Theme.Colors.Gold,
		Align = Enum.TextXAlignment.Left,
		LayoutOrder = 99,
	})
	mutationCell.Size = UDim2.fromOffset(290, 24)
end

return Popups
