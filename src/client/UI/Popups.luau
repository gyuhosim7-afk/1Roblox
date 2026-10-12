--!strict
-- Popups: hatch reveal (3D slime in a viewport), offline earnings, the Royal Egg odds screen
-- (shown before any purchase) and the odds panel that appears near a nest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Odds = require(Shared.Odds)
local SlimeBuilder = require(Shared.SlimeBuilder)
local Theme = require(script.Parent.Theme)
local OddsView = require(script.Parent.OddsView)

local Popups = {}

local screen: ScreenGui? = nil
local hatchQueue: { any } = {}
local showingHatch = false

function Popups.Mount(gui: ScreenGui)
	screen = gui
end

-- Hatch reveal ------------------------------------------------------------------
local function showNextHatch()
	local gui = screen
	if showingHatch or #hatchQueue == 0 or not gui then
		return
	end
	showingHatch = true
	local info = table.remove(hatchQueue, 1)
	local def = Config.Slimes[info.Kind]
	if not def then
		showingHatch = false
		return
	end
	local rarityColor = Theme.Hex(Config.Rarities[def.Rarity].Color)

	local frame = Theme.Frame({
		Name = "HatchPopup",
		Size = UDim2.fromOffset(360, 400),
		Position = UDim2.fromScale(0.5, 0.48),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.Background,
		Radius = 24,
		Parent = gui,
	})
	Theme.AutoScale(frame)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rarityColor
		stroke.Thickness = 5
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromOffset(300, 230)
	viewport.Position = UDim2.fromOffset(30, 50)
	viewport.Ambient = Color3.fromRGB(200, 200, 200)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.Parent = frame
	local model = SlimeBuilder.Build(info.Kind, info.Mutation)
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local scale = SlimeBuilder.Scale(info.Kind)
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 2.2 * scale, -9 * scale), Vector3.new(0, 1.4 * scale, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local headline = if info.Source == "Royal" then "ROYAL HATCH!" else "HATCHED!"
	if info.New then
		headline = "NEW SLIME!"
	end
	local top = Theme.Text(frame, headline, { MaxSize = 34, Color = Theme.Colors.Gold })
	top.Size = UDim2.new(1, -20, 0, 44)
	top.Position = UDim2.fromOffset(10, 6)
	local mutationName = if info.Mutation ~= "None" then (Config.Mutations :: any)[info.Mutation].Name .. " " else ""
	local name = Theme.Text(frame, mutationName .. def.Name, { MaxSize = 30, Color = rarityColor })
	name.Size = UDim2.new(1, -20, 0, 40)
	name.Position = UDim2.fromOffset(10, 284)
	local detail = def.Rarity .. "  -  $" .. Format.Number(def.Income * (Config.Mutations :: any)[info.Mutation or "None"].Multiplier) .. "/s"
	if info.Gems and info.Gems > 0 then
		detail ..= "   +" .. info.Gems .. " 💎"
	end
	local sub = Theme.Text(frame, detail, { MaxSize = 22, Color = Theme.Colors.SubText })
	sub.Size = UDim2.new(1, -20, 0, 30)
	sub.Position = UDim2.fromOffset(10, 326)
	local tap = Theme.Text(frame, "tap to close", { MaxSize = 14, Color = Theme.Colors.SubText })
	tap.Size = UDim2.new(1, -20, 0, 20)
	tap.Position = UDim2.fromOffset(10, 368)

	local closeButton = Instance.new("TextButton")
	closeButton.BackgroundTransparency = 1
	closeButton.Text = ""
	closeButton.Size = UDim2.fromScale(1, 1)
	closeButton.ZIndex = 10
	closeButton.Parent = frame

	Theme.Play("Hatch", if Config.Rarities[def.Rarity].Order >= 4 then 0.8 else 0.4)
	local spin = RunService.RenderStepped:Connect(function(dt: number)
		model:PivotTo(model:GetPivot() * CFrame.Angles(0, dt * 1.2, 0))
	end)
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		spin:Disconnect()
		frame:Destroy()
		showingHatch = false
		showNextHatch()
	end
	closeButton.Activated:Connect(close)
	local uiScale = frame:FindFirstChildOfClass("UIScale")
	if uiScale then
		local target = uiScale.Scale
		uiScale.Scale = target * 0.3
		TweenService:Create(uiScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = target }):Play()
	end
	task.delay(if Config.Rarities[def.Rarity].Order >= 4 or info.New then 3.5 else 2.2, close)
end

function Popups.Hatch(info: any)
	table.insert(hatchQueue, info)
	showNextHatch()
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
	Theme.AutoScale(frame)
	local zone = Config.Zones[math.clamp(state.Data.BestZone, 1, #Config.Zones)]
	local luck = state.Luck or 1
	local title = Theme.Text(frame, "👑 Royal Egg - " .. zone.Name .. " slimes", { MaxSize = 28, Color = Theme.Colors.Gold })
	title.Size = UDim2.new(1, -70, 0, 44)
	title.Position = UDim2.fromOffset(10, 8)
	Theme.Button(frame, "X", Theme.Colors.Red, function()
		frame:Destroy()
		royalFrame = nil
	end, { Size = UDim2.fromOffset(46, 46), Position = UDim2.new(1, -8, 0, 8), AnchorPoint = Vector2.new(1, 0) })
	local info = Theme.Text(
		frame,
		"Rare or better guaranteed. " .. OddsView.LuckText(luck) .. ". " .. OddsView.Disclaimer,
		{ MaxSize = 15, Color = Theme.Colors.SubText }
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
	local gemButton = Theme.Button(row, "Buy " .. Config.GemShop.RoyalEgg .. " 💎", Theme.Colors.Blue, function()
		request("BuyWithGems", "RoyalEgg")
	end, { Size = UDim2.fromOffset(250, 58), LayoutOrder = 2 })
	Theme.SetButtonEnabled(gemButton, state.Data.Gems >= Config.GemShop.RoyalEgg, Theme.Colors.Blue)
end

-- Nest odds panel -------------------------------------------------------------------
local nestPanel: Frame? = nil
local nestPanelKey: string? = nil

function Popups.NestOdds(eggId: string?, state: any?)
	local gui = screen
	if not gui then
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
	local frame = Theme.Frame({
		Name = "NestOdds",
		Size = UDim2.fromOffset(330, 330),
		Position = UDim2.new(1, -150, 0, 70),
		AnchorPoint = Vector2.new(1, 0),
		Color = Theme.Colors.Background,
		Radius = 16,
		Parent = gui,
	})
	frame.BackgroundTransparency = 0.15
	Theme.AutoScale(frame)
	nestPanel = frame
	local title = Theme.Text(frame, egg.Name .. " odds", { MaxSize = 22, Color = Theme.Hex(egg.SpotColor) })
	title.Size = UDim2.new(1, -16, 0, 30)
	title.Position = UDim2.fromOffset(8, 4)
	local luckLabel = Theme.Text(frame, OddsView.LuckText(luck), { MaxSize = 13, Color = Theme.Colors.Gold })
	luckLabel.Size = UDim2.new(1, -16, 0, 18)
	luckLabel.Position = UDim2.fromOffset(8, 34)
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, -12, 1, -58)
	list.Position = UDim2.fromOffset(6, 54)
	list.Parent = frame
	Theme.List(list, 3)
	OddsView.Build(list, Odds.EggOdds(eggId, luck), Odds.MutationOdds(luck), state.Data.Discovered, 0)
end

return Popups
