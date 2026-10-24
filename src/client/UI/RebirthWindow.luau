--!strict
-- Rebirth: shows requirements with progress bars, what you keep, what resets, and the reward.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Theme = require(script.Parent.Theme)

local RebirthWindow = {}

local function progressBar(parent: Instance, order: number): (Frame, TextLabel)
	local bar = Theme.Frame({
		Size = UDim2.new(1, -20, 0, 40),
		Color = Theme.Colors.PanelLight,
		Radius = 20,
		LayoutOrder = order,
		Parent = parent,
	})
	local fill = Theme.Frame({
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		Color = Theme.Colors.Green,
		Radius = 20,
		Stroke = false,
		Parent = bar,
	})
	local label = Theme.Text(bar, "", { MaxSize = 22 })
	label.Size = UDim2.new(1, -10, 1, -6)
	label.Position = UDim2.fromOffset(5, 3)
	label.ZIndex = 3
	return fill, label
end

function RebirthWindow.Create(screen: ScreenGui, ctx: any)
	local window = Theme.Window(screen, "Rebirth", Vector2.new(600, 500), ctx.Close)
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(1, 1)
	list.Parent = window.Content
	Theme.List(list, 10)

	local title = Theme.Text(list, "", { MaxSize = 26, Color = Theme.Colors.Gold, LayoutOrder = 1 })
	title.Size = UDim2.new(1, 0, 0, 34)
	local speedFill, speedLabel = progressBar(list, 2)
	local coinFill, coinLabel = progressBar(list, 3)
	local reward = Theme.Text(list, "", { MaxSize = 20, Color = Theme.Colors.Green, LayoutOrder = 4 })
	reward.Size = UDim2.new(1, -20, 0, 60)
	local keep = Theme.Text(
		list,
		"Resets: Speed, Coins, Speed Training.\nKeeps: Slimes, Gems, Pedestals, Incubators, Lock upgrades.",
		{ MaxSize = 17, Color = Theme.Colors.SubText, LayoutOrder = 5 }
	)
	keep.Size = UDim2.new(1, -20, 0, 50)
	local button = Theme.Button(list, "♻ REBIRTH", Theme.Colors.Accent, function()
		ctx.Request("Rebirth")
	end, { Size = UDim2.fromOffset(300, 70), LayoutOrder = 6, MaxText = 32 })

	local function refresh(state: any)
		local data = state.Data
		local speedReq, coinReq = Formulas.RebirthRequirement(data.Rebirths)
		title.Text = "Rebirth " .. (data.Rebirths + 1)
		local speedFraction = math.clamp(data.Speed / speedReq, 0, 1)
		local coinFraction = math.clamp(data.Coins / coinReq, 0, 1)
		speedFill.Size = UDim2.fromScale(speedFraction, 1)
		coinFill.Size = UDim2.fromScale(coinFraction, 1)
		speedLabel.Text = "⚡ "
			.. Format.Number(math.floor(data.Speed))
			.. " / "
			.. Format.Number(speedReq)
			.. " Speed"
		coinLabel.Text = "💰 $" .. Format.Number(math.floor(data.Coins)) .. " / $" .. Format.Number(coinReq)
		local nextRebirths = data.Rebirths + 1
		reward.Text = "Reward: Speed gain +"
			.. math.floor(Config.Rebirth.SpeedBonusPerRebirth * 100 * nextRebirths)
			.. "%, Coins +"
			.. math.floor(Config.Rebirth.CoinBonusPerRebirth * 100 * nextRebirths)
			.. "% (total), +"
			.. Config.Rebirth.GemReward
			.. " 💎"
		Theme.SetButtonEnabled(button, speedFraction >= 1 and coinFraction >= 1, Theme.Colors.Accent)
	end

	return { Window = window, Refresh = refresh }
end

return RebirthWindow
