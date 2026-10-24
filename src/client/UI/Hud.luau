--!strict
-- Always-visible HUD in the style of big simulator games:
--   left: coin/gem counters and a grid of chunky icon tiles (Shop wide on top)
--   top: outlined tip / carrying banner and boost timers
--   bottom: speed counter with a progress bar toward the next zone gate
--   right: round BONK button and LOCK button
-- Everything is big enough to tap on a phone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Theme = require(script.Parent.Theme)

local Hud = {}

export type Actions = {
	OpenWindow: (name: string) -> (),
	Bonk: () -> (),
	Lock: () -> (),
	ClaimGift: () -> (),
	ClaimDaily: () -> (),
}

local refs: { [string]: any } = {}

-- Dark rounded counter with a big icon hanging off its left edge.
local function counter(parent: Instance, name: string, icon: string, color: Color3, order: number): TextLabel
	local frame = Theme.Frame({
		Name = name,
		Size = UDim2.fromOffset(196, 44),
		Color = Color3.fromRGB(20, 18, 38),
		Transparency = 0.25,
		Radius = 22,
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.Icon(frame, icon, UDim2.fromOffset(54, 54), UDim2.new(0, -8, 0.5, 0), Vector2.new(0, 0.5))
	local value = Theme.Text(frame, "0", {
		Name = "Value",
		MaxSize = 30,
		Color = color,
		Align = Enum.TextXAlignment.Left,
		StrokeThickness = 3,
	})
	value.Size = UDim2.new(1, -60, 1, -6)
	value.Position = UDim2.fromOffset(52, 3)
	return value
end

-- Square menu tile: big icon on top, outlined label at the bottom.
local function tile(
	parent: Instance,
	key: string,
	label: string,
	icon: string,
	color: Color3,
	onClick: () -> (),
	order: number
)
	local button = Theme.Button(parent, "", color, onClick, { Name = key, LayoutOrder = order, Radius = 16 })
	Theme.Icon(button, icon, UDim2.fromScale(0.8, 0.7), UDim2.new(0.5, 0, 0, 2), Vector2.new(0.5, 0))
	local text = button:FindFirstChild("Label") :: TextLabel
	text.Text = label
	text.Size = UDim2.new(1, -6, 0, 24)
	text.Position = UDim2.new(0, 3, 1, -27)
	text.ZIndex = 3
	local constraint = text:FindFirstChildOfClass("UITextSizeConstraint")
	if constraint then
		constraint.MaxTextSize = 20
	end
	return button
end

function Hud.Mount(screen: ScreenGui, actions: Actions)
	-- Top center: banner, boosts, and room for small panels (nest odds). One UIScale for all.
	local stack = Instance.new("Frame")
	stack.Name = "TopStack"
	stack.BackgroundTransparency = 1
	stack.Size = UDim2.fromOffset(600, 420)
	stack.Position = UDim2.new(0.5, 0, 0, 4)
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Parent = screen
	Theme.List(stack, 6)
	Theme.AutoScale(stack)
	refs.TopStack = stack

	local banner = Theme.Frame({
		Name = "Banner",
		Size = UDim2.fromOffset(600, 46),
		Color = Theme.Colors.Accent,
		Radius = 16,
		LayoutOrder = 1,
		Parent = stack,
	})
	banner.Visible = false
	local bannerText = Theme.Text(banner, "", { MaxSize = 28, StrokeThickness = 3 })
	bannerText.Size = UDim2.new(1, -16, 1, -6)
	bannerText.Position = UDim2.fromOffset(8, 3)
	refs.Banner = banner
	refs.BannerStroke = banner:FindFirstChildOfClass("UIStroke")
	refs.BannerText = bannerText

	local boosts = Instance.new("Frame")
	boosts.Name = "Boosts"
	boosts.BackgroundTransparency = 1
	boosts.Size = UDim2.fromOffset(600, 30)
	boosts.LayoutOrder = 2
	boosts.Visible = false
	boosts.Parent = stack
	Theme.List(boosts, 8, true)
	refs.BoostsRow = boosts
	local boostInfo: { { Key: string, Text: string, Color: Color3 } } = {
		{ Key = "LuckPotion", Text = "🍀 Luck x2", Color = Theme.Colors.Green },
		{ Key = "SpeedPotion", Text = "⚡ Speed x2", Color = Theme.Colors.Blue },
		{ Key = "ServerLuck", Text = "🌟 Server Luck x2", Color = Theme.Colors.Purple },
	}
	for index, info in boostInfo do
		local frame = Theme.Frame({
			Name = info.Key,
			Size = UDim2.fromOffset(190, 30),
			Color = info.Color,
			Radius = 15,
			LayoutOrder = index,
			Parent = boosts,
		})
		frame.Visible = false
		local label = Theme.Text(frame, info.Text, { MaxSize = 18, StrokeThickness = 2 })
		label.Size = UDim2.new(1, -10, 1, -4)
		label.Position = UDim2.fromOffset(5, 2)
		refs[info.Key] = { Frame = frame, Label = label, Text = info.Text }
	end

	-- Left: counters + menu tiles.
	local left = Instance.new("Frame")
	left.Name = "Menu"
	left.BackgroundTransparency = 1
	left.Size = UDim2.fromOffset(212, 360)
	left.Position = UDim2.fromOffset(14, 6)
	left.Parent = screen
	Theme.List(left, 8, false, Enum.HorizontalAlignment.Left)
	Theme.AutoScale(left)

	local counters = Instance.new("Frame")
	counters.Name = "Currency"
	counters.BackgroundTransparency = 1
	counters.Size = UDim2.fromOffset(212, 96)
	counters.LayoutOrder = 1
	counters.Parent = left
	local counterList = Theme.List(counters, 8, false, Enum.HorizontalAlignment.Left)
	counterList.Padding = UDim.new(0, 8)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.Parent = counters
	refs.Coins = counter(counters, "Coins", "Coins", Theme.Colors.Gold, 1)
	refs.Gems = counter(counters, "Gems", "Gems", Theme.Colors.Gem, 2)

	refs.MenuButtons = {}
	local shop = tile(left, "Shop", "SHOP", "Shop", Theme.Colors.Gold, function()
		actions.OpenWindow("Shop")
	end, 2)
	shop.Size = UDim2.fromOffset(204, 64)
	refs.MenuButtons.Shop = shop

	local grid = Instance.new("Frame")
	grid.Name = "Tiles"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromOffset(212, 170)
	grid.LayoutOrder = 3
	grid.Parent = left
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(98, 74)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	local tiles: { { Key: string, Text: string, Icon: string, Color: Color3 } } = {
		{ Key = "Rebirth", Text = "REBIRTH", Icon = "Rebirth", Color = Color3.fromRGB(235, 64, 72) },
		{ Key = "Upgrades", Text = "UPGRADES", Icon = "Upgrade", Color = Color3.fromRGB(70, 200, 90) },
		{ Key = "Slimes", Text = "SLIMES", Icon = "Slime", Color = Color3.fromRGB(60, 150, 255) },
		{ Key = "Index", Text = "INDEX", Icon = "Index", Color = Color3.fromRGB(160, 92, 255) },
	}
	for index, item in tiles do
		refs.MenuButtons[item.Key] = tile(grid, item.Key, item.Text, item.Icon, item.Color, function()
			actions.OpenWindow(item.Key)
		end, index)
	end
	refs.RebirthBadge = Theme.Badge(refs.MenuButtons.Rebirth, "0%")
	local rebirthBadge = refs.RebirthBadge.Parent :: Frame
	rebirthBadge.Size = UDim2.fromOffset(52, 26)
	rebirthBadge.BackgroundColor3 = Color3.fromRGB(40, 36, 70)

	-- Top right: free rewards (kept off the left side so the phone thumbstick stays clear)
	local rewards = Instance.new("Frame")
	rewards.Name = "Rewards"
	rewards.BackgroundTransparency = 1
	rewards.Size = UDim2.fromOffset(196, 80)
	rewards.Position = UDim2.new(1, -12, 0, 6)
	rewards.AnchorPoint = Vector2.new(1, 0)
	rewards.Parent = screen
	local rewardList = Theme.List(rewards, 8, true, Enum.HorizontalAlignment.Right)
	rewardList.SortOrder = Enum.SortOrder.LayoutOrder
	Theme.AutoScale(rewards)
	refs.Gift = tile(rewards, "Gift", "GIFT", "Gift", Color3.fromRGB(255, 120, 200), actions.ClaimGift, 2)
	refs.Gift.Size = UDim2.fromOffset(92, 78)
	refs.GiftBadge = Theme.Badge(refs.Gift, "!")
	refs.Daily = tile(rewards, "Daily", "DAILY", "Egg", Color3.fromRGB(255, 160, 40), actions.ClaimDaily, 1)
	refs.Daily.Size = UDim2.fromOffset(92, 78)
	refs.DailyBadge = Theme.Badge(refs.Daily, "1")

	-- Bottom center: speed + progress to the next gate.
	local bottom = Instance.new("Frame")
	bottom.Name = "SpeedBar"
	bottom.BackgroundTransparency = 1
	bottom.Size = UDim2.fromOffset(440, 96)
	bottom.Position = UDim2.new(0.5, 0, 1, -8)
	bottom.AnchorPoint = Vector2.new(0.5, 1)
	bottom.Parent = screen
	Theme.AutoScale(bottom)
	refs.SpeedBar = bottom

	local speedRow = Instance.new("Frame")
	speedRow.Name = "Speed"
	speedRow.BackgroundTransparency = 1
	speedRow.Size = UDim2.new(1, 0, 0, 48)
	speedRow.Parent = bottom
	Theme.Icon(speedRow, "Speed", UDim2.fromOffset(58, 58), UDim2.new(0.5, -112, 0.5, -2), Vector2.new(0.5, 0.5))
	local speedValue = Theme.Text(speedRow, "0", {
		Name = "Value",
		MaxSize = 40,
		Color = Theme.Colors.Gold,
		Align = Enum.TextXAlignment.Left,
		StrokeThickness = 3.5,
	})
	speedValue.Size = UDim2.new(0, 170, 1, 0)
	speedValue.Position = UDim2.new(0.5, -80, 0, 0)
	local perSecond = Theme.Text(speedRow, "+1/s", {
		Name = "PerSecond",
		MaxSize = 22,
		Color = Color3.fromRGB(150, 255, 140),
		Align = Enum.TextXAlignment.Left,
		StrokeThickness = 2.5,
	})
	perSecond.Size = UDim2.fromOffset(110, 26)
	perSecond.Position = UDim2.new(0.5, 70, 0.5, -6)
	refs.Speed = speedValue
	refs.PerSecond = perSecond

	local bar = Theme.Frame({
		Name = "Bar",
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		Color = Color3.fromRGB(235, 238, 250),
		Radius = 12,
		Parent = bottom,
	})
	local barStroke = bar:FindFirstChildOfClass("UIStroke")
	if barStroke then
		barStroke.Thickness = 4
		barStroke.Color = Theme.Colors.Outline
	end
	local fill = Theme.Frame({
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		Color = Color3.fromRGB(255, 214, 40),
		Radius = 12,
		Stroke = false,
		Parent = bar,
	})
	Theme.Gradient(fill, Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 170, 60))
	local barLeft = Theme.Text(bar, "NEXT ZONE", {
		Name = "Goal",
		MaxSize = 24,
		Align = Enum.TextXAlignment.Left,
		StrokeThickness = 3,
	})
	barLeft.Size = UDim2.new(0.62, -12, 1, -6)
	barLeft.Position = UDim2.fromOffset(12, 3)
	barLeft.ZIndex = 3
	local barRight = Theme.Text(bar, "0/0", {
		Name = "Progress",
		MaxSize = 24,
		Align = Enum.TextXAlignment.Right,
		StrokeThickness = 3,
	})
	barRight.Size = UDim2.new(0.38, -12, 1, -6)
	barRight.Position = UDim2.new(0.62, 0, 0, 3)
	barRight.ZIndex = 3
	refs.BarFill = fill
	refs.BarGoal = barLeft
	refs.BarProgress = barRight

	-- Right: actions (above the mobile jump button)
	local right = Instance.new("Frame")
	right.Name = "Actions"
	right.BackgroundTransparency = 1
	right.Size = UDim2.fromOffset(130, 214)
	right.Position = UDim2.new(1, -12, 0.5, 0)
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Parent = screen
	Theme.List(right, 10, false, Enum.HorizontalAlignment.Right)
	Theme.AutoScale(right)
	local bonk = Theme.Button(right, "BONK", Theme.Colors.Red, actions.Bonk, {
		Name = "Bonk",
		Size = UDim2.fromOffset(122, 122),
		LayoutOrder = 1,
		Radius = 61,
		MaxText = 26,
	})
	Theme.Icon(bonk, "Bonk", UDim2.fromScale(0.62, 0.62), UDim2.fromScale(0.5, 0.08), Vector2.new(0.5, 0))
	local bonkLabel = bonk:FindFirstChild("Label") :: TextLabel
	bonkLabel.Size = UDim2.new(1, -12, 0, 30)
	bonkLabel.Position = UDim2.new(0, 6, 1, -40)
	bonkLabel.ZIndex = 3
	refs.Bonk = bonk
	local lock = Theme.Button(right, "LOCK", Theme.Colors.Blue, actions.Lock, {
		Name = "Lock",
		Size = UDim2.fromOffset(122, 64),
		LayoutOrder = 2,
		MaxText = 22,
	})
	Theme.Icon(lock, "Lock", UDim2.fromOffset(48, 48), UDim2.new(0, 4, 0.5, 0), Vector2.new(0, 0.5))
	local lockLabel = lock:FindFirstChild("Label") :: TextLabel
	lockLabel.Size = UDim2.new(1, -56, 1, -10)
	lockLabel.Position = UDim2.fromOffset(50, 5)
	refs.Lock = lock
end

-- Container under the banner for small info panels (e.g. nest odds).
function Hud.TopStack(): Frame
	return refs.TopStack
end

-- The next zone gate the player has not opened yet: (zone, need speed, need rebirths) or nil.
local function nextGoal(data: any): (Config.ZoneDef?, number, number)
	for index, zone in Config.Zones do
		if not Formulas.ZoneUnlocked(index, data.Speed, data.Rebirths) then
			return zone, zone.GateSpeed, zone.RebirthsRequired
		end
	end
	return nil, 0, 0
end

function Hud.Update(state: any)
	local data = state.Data
	refs.Speed.Text = Format.Number(math.floor(data.Speed))
	refs.PerSecond.Text = "+" .. Format.Number(state.SpeedPerSecond or 1) .. "/s"
	refs.Coins.Text = Format.Number(math.floor(data.Coins))
	refs.Gems.Text = Format.Number(math.floor(data.Gems))

	local zone, needSpeed, needRebirths = nextGoal(data)
	local fraction = 1
	if zone and data.Speed < needSpeed then
		fraction = data.Speed / math.max(needSpeed, 1)
		refs.BarGoal.Text = "NEXT: " .. string.upper(zone.Name)
		refs.BarProgress.Text = Format.Number(math.floor(data.Speed)) .. "/" .. Format.Number(needSpeed)
	elseif zone then
		fraction = data.Rebirths / math.max(needRebirths, 1)
		refs.BarGoal.Text = "NEXT: " .. string.upper(zone.Name)
		refs.BarProgress.Text = data.Rebirths .. "/" .. needRebirths .. " REBIRTHS"
	else
		refs.BarGoal.Text = "ALL ZONES OPEN!"
		refs.BarProgress.Text = "MAX"
	end
	TweenService:Create(refs.BarFill, TweenInfo.new(0.3), { Size = UDim2.fromScale(math.clamp(fraction, 0.02, 1), 1) })
		:Play()

	local reqSpeed, reqCoins = Formulas.RebirthRequirement(data.Rebirths)
	local progress = math.min(data.Speed / reqSpeed, data.Coins / reqCoins, 1)
	refs.RebirthBadge.Text = math.floor(progress * 100) .. "%"
end

function Hud.UpdateTimers(state: any, now: number)
	local data = state.Data
	local timers: { [string]: number } = {
		LuckPotion = data.Potions.Luck,
		SpeedPotion = data.Potions.Speed,
		ServerLuck = state.ServerLuckEndsAt or 0,
	}
	local anyBoost = false
	for key, endsAt in timers do
		local ref = refs[key]
		local remaining = endsAt - now
		ref.Frame.Visible = remaining > 0
		if remaining > 0 then
			anyBoost = true
			ref.Label.Text = ref.Text .. "  " .. Format.Clock(remaining)
		end
	end
	refs.BoostsRow.Visible = anyBoost

	-- Lock button
	local lockedUntil = state.LockedUntil or 0
	if lockedUntil > now then
		Theme.SetButtonText(refs.Lock, Format.Clock(lockedUntil - now))
		refs.Lock.BackgroundColor3 = Theme.Colors.Green
	else
		Theme.SetButtonText(refs.Lock, "LOCK")
		refs.Lock.BackgroundColor3 = Theme.Colors.Blue
	end

	-- Gift / daily
	local giftReady = (state.GiftReadyAt or 0) - now
	Theme.SetButtonText(refs.Gift, if giftReady <= 0 then "CLAIM!" else Format.Clock(giftReady))
	refs.GiftBadge.Parent.Visible = giftReady <= 0
	local daily = state.Daily
	refs.Daily.Visible = daily ~= nil and daily.Available == true
end

-- Tips show as big outlined text; carrying an egg shows a colored box.
function Hud.SetBanner(text: string?, color: Color3?)
	refs.Banner.Visible = text ~= nil
	if text then
		refs.BannerText.Text = text
		local boxed = color ~= Theme.Colors.Blue
		refs.Banner.BackgroundColor3 = color or Theme.Colors.Accent
		refs.Banner.BackgroundTransparency = if boxed then 0 else 1
		refs.BannerStroke.Enabled = boxed
	end
end

function Hud.FlashButton(name: string)
	local button = refs.MenuButtons and refs.MenuButtons[name]
	if button then
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			local on = (os.clock() % 0.8) < 0.4
			stroke.Color = if on then Theme.Colors.Gold else Theme.Colors.Outline
			stroke.Thickness = if on then 6 else 3.5
		end
	end
end

function Hud.BonkCooldown(fraction: number)
	local button = refs.Bonk
	if button then
		button.BackgroundColor3 = if fraction >= 1 then Theme.Colors.Red else Theme.Colors.Disabled
	end
end

return Hud
