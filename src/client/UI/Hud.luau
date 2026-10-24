--!strict
-- Always-visible HUD: stats bar, boost timers, menu buttons (left), BONK + LOCK (right),
-- and a banner for carrying / tutorial hints. Big buttons that work with touch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
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

local function pill(parent: Instance, name: string, icon: string, color: Color3, width: number, order: number)
	local frame = Theme.Frame({
		Name = name,
		Size = UDim2.fromOffset(width, 52),
		Color = Theme.Colors.Panel,
		Radius = 26,
		LayoutOrder = order,
		Parent = parent,
	})
	frame.BackgroundTransparency = 0.1
	local iconLabel = Theme.Text(frame, icon, { MaxSize = 30 })
	iconLabel.Size = UDim2.fromOffset(44, 44)
	iconLabel.Position = UDim2.fromOffset(6, 4)
	local value =
		Theme.Text(frame, "0", { Name = "Value", MaxSize = 30, Color = color, Align = Enum.TextXAlignment.Left })
	value.Size = UDim2.new(1, -60, 1, -8)
	value.Position = UDim2.fromOffset(52, 4)
	return frame, value
end

function Hud.Mount(screen: ScreenGui, actions: Actions)
	-- Top stack: stats bar, boost timers, banner and toasts share one UIScale so they never overlap.
	local stack = Instance.new("Frame")
	stack.Name = "TopStack"
	stack.BackgroundTransparency = 1
	stack.Size = UDim2.fromOffset(660, 420)
	stack.Position = UDim2.new(0.5, 0, 0, 4)
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Parent = screen
	Theme.List(stack, 6)
	Theme.AutoScale(stack)
	refs.TopStack = stack

	local top = Instance.new("Frame")
	top.Name = "TopBar"
	top.BackgroundTransparency = 1
	top.Size = UDim2.fromOffset(640, 56)
	top.LayoutOrder = 1
	top.Parent = stack
	Theme.List(top, 10, true)
	local speedPill, speedValue = pill(top, "Speed", "⚡", Theme.Colors.Gold, 250, 1)
	speedValue.Size = UDim2.new(1, -60, 0.62, -2)
	local perSecond = Theme.Text(
		speedPill,
		"+1/s",
		{ Name = "PerSecond", MaxSize = 18, Color = Theme.Colors.SubText, Align = Enum.TextXAlignment.Left }
	)
	perSecond.Size = UDim2.new(1, -60, 0.38, -2)
	perSecond.Position = UDim2.new(0, 52, 0.62, 0)
	local _, coinValue = pill(top, "Coins", "💰", Theme.Colors.Green, 200, 2)
	local _, gemValue = pill(top, "Gems", "💎", Theme.Colors.Gem, 160, 3)
	refs.Speed = speedValue
	refs.PerSecond = perSecond
	refs.Coins = coinValue
	refs.Gems = gemValue

	local boosts = Instance.new("Frame")
	boosts.Name = "Boosts"
	boosts.BackgroundTransparency = 1
	boosts.Size = UDim2.fromOffset(640, 28)
	boosts.LayoutOrder = 2
	boosts.Visible = false
	boosts.Parent = stack
	Theme.List(boosts, 8, true)
	refs.BoostsRow = boosts
	local boostInfo: { { Key: string, Text: string } } = {
		{ Key = "LuckPotion", Text = "🍀 Luck x2" },
		{ Key = "SpeedPotion", Text = "⚡ Speed x2" },
		{ Key = "ServerLuck", Text = "🌟 Server Luck x2" },
	}
	for index, info in boostInfo do
		local frame = Theme.Frame({
			Name = info.Key,
			Size = UDim2.fromOffset(200, 28),
			Color = Theme.Colors.Purple,
			Radius = 14,
			LayoutOrder = index,
			Parent = boosts,
		})
		frame.Visible = false
		local label = Theme.Text(frame, info.Text, { MaxSize = 18 })
		label.Size = UDim2.new(1, -10, 1, -4)
		label.Position = UDim2.fromOffset(5, 2)
		refs[info.Key] = { Frame = frame, Label = label, Text = info.Text }
	end

	local banner = Theme.Frame({
		Name = "Banner",
		Size = UDim2.fromOffset(600, 48),
		Color = Theme.Colors.Accent,
		Radius = 16,
		LayoutOrder = 3,
		Parent = stack,
	})
	banner.Visible = false
	local bannerText = Theme.Text(banner, "", { MaxSize = 24 })
	bannerText.Size = UDim2.new(1, -16, 1, -8)
	bannerText.Position = UDim2.fromOffset(8, 4)
	refs.Banner = banner
	refs.BannerText = bannerText

	-- Left menu: 2 columns so it stays above the mobile thumbstick area.
	local left = Instance.new("Frame")
	left.Name = "Menu"
	left.BackgroundTransparency = 1
	left.Size = UDim2.fromOffset(180, 290)
	left.Position = UDim2.fromOffset(8, 8)
	left.Parent = screen
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(86, 66)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = left
	Theme.AutoScale(left)
	local menu: { { Key: string, Text: string, Color: Color3 } } = {
		{ Key = "Shop", Text = "🛒\nSHOP", Color = Theme.Colors.Pink },
		{ Key = "Upgrades", Text = "⬆\nUPGRADE", Color = Theme.Colors.Green },
		{ Key = "Slimes", Text = "🎒\nSLIMES", Color = Theme.Colors.Blue },
		{ Key = "Index", Text = "📖\nINDEX", Color = Theme.Colors.Purple },
		{ Key = "Rebirth", Text = "♻\nREBIRTH", Color = Theme.Colors.Accent },
	}
	refs.MenuButtons = {}
	for index, item in menu do
		local button = Theme.Button(left, item.Text, item.Color, function()
			actions.OpenWindow(item.Key)
		end, { Name = item.Key, LayoutOrder = index, MaxText = 20 })
		refs.MenuButtons[item.Key] = button
	end
	local gift = Theme.Button(left, "🎁", Theme.Colors.Red, actions.ClaimGift, {
		Name = "Gift",
		LayoutOrder = 10,
		MaxText = 18,
	})
	refs.Gift = gift
	local daily = Theme.Button(left, "📅\nDAILY", Theme.Colors.Gold, actions.ClaimDaily, {
		Name = "Daily",
		LayoutOrder = 11,
		MaxText = 18,
	})
	refs.Daily = daily

	-- Right actions (above the mobile jump button)
	local right = Instance.new("Frame")
	right.Name = "Actions"
	right.BackgroundTransparency = 1
	right.Size = UDim2.fromOffset(130, 200)
	right.Position = UDim2.new(1, -10, 0.48, 0)
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Parent = screen
	Theme.List(right, 10, false, Enum.HorizontalAlignment.Right)
	Theme.AutoScale(right)
	local bonk = Theme.Button(right, "🔨\nBONK", Theme.Colors.Red, actions.Bonk, {
		Name = "Bonk",
		Size = UDim2.fromOffset(118, 118),
		LayoutOrder = 1,
		Radius = 59,
		MaxText = 30,
	})
	refs.Bonk = bonk
	local lock = Theme.Button(right, "🔒 LOCK", Theme.Colors.Blue, actions.Lock, {
		Name = "Lock",
		Size = UDim2.fromOffset(118, 64),
		LayoutOrder = 2,
		MaxText = 22,
	})
	refs.Lock = lock
end

-- Container under the banner for small info panels (e.g. nest odds).
function Hud.TopStack(): Frame
	return refs.TopStack
end

function Hud.Update(state: any)
	local data = state.Data
	refs.Speed.Text = Format.Number(math.floor(data.Speed))
	refs.PerSecond.Text = "+" .. Format.Number(state.SpeedPerSecond or 1) .. "/s"
	refs.Coins.Text = Format.Number(math.floor(data.Coins))
	refs.Gems.Text = Format.Number(math.floor(data.Gems))
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
		Theme.SetButtonText(refs.Lock, "🔒 " .. Format.Clock(lockedUntil - now))
		refs.Lock.BackgroundColor3 = Theme.Colors.Green
	else
		Theme.SetButtonText(refs.Lock, "🔓 LOCK")
		refs.Lock.BackgroundColor3 = Theme.Colors.Blue
	end

	-- Gift / daily
	local giftReady = (state.GiftReadyAt or 0) - now
	Theme.SetButtonText(refs.Gift, if giftReady <= 0 then "🎁 CLAIM!" else "🎁 " .. Format.Clock(giftReady))
	refs.Gift.BackgroundColor3 = if giftReady <= 0 then Theme.Colors.Red else Theme.Colors.PanelLight
	local daily = state.Daily
	refs.Daily.Visible = daily ~= nil and daily.Available == true
end

-- Banner priority: carrying > tutorial.
function Hud.SetBanner(text: string?, color: Color3?)
	refs.Banner.Visible = text ~= nil
	if text then
		refs.BannerText.Text = text
		refs.Banner.BackgroundColor3 = color or Theme.Colors.Accent
	end
end

function Hud.FlashButton(name: string)
	local button = refs.MenuButtons and refs.MenuButtons[name]
	if button then
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if (os.clock() % 0.8) < 0.4 then Theme.Colors.Gold else Theme.Colors.Stroke
			stroke.Thickness = if (os.clock() % 0.8) < 0.4 then 5 else 3
		end
	end
end

function Hud.BonkCooldown(fraction: number)
	local button = refs.Bonk
	if button then
		button.BackgroundColor3 = if fraction >= 1 then Theme.Colors.Red else Theme.Colors.Disabled
	end
end

local _ = Config

return Hud
