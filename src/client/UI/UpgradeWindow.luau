--!strict
-- Coin upgrades: Speed Training, Pedestals, Incubators, Lock time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Theme = require(script.Parent.Theme)

local UpgradeWindow = {}

local LEVEL_FIELD = {
	Training = "TrainingLevel",
	Pedestals = "PedestalLevel",
	Incubators = "IncubatorLevel",
	Lock = "LockLevel",
}
local ICONS = { Training = "⚡", Pedestals = "🏛", Incubators = "🥚", Lock = "🔒" }

function UpgradeWindow.Create(screen: ScreenGui, ctx: any)
	local window = Theme.Window(screen, "Upgrades", Vector2.new(640, 470), ctx.Close)
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(1, 1)
	list.Parent = window.Content
	Theme.List(list, 10)

	local rows: { [string]: { Info: TextLabel, Button: TextButton } } = {}
	for index, kind in Config.UpgradeOrder do
		local def = (Config.Upgrades :: any)[kind]
		local frame = Theme.Frame({
			Name = kind,
			Size = UDim2.new(1, 0, 0, 80),
			Color = Theme.Colors.Panel,
			LayoutOrder = index,
			Parent = list,
		})
		local icon = Theme.Text(frame, ICONS[kind] or "", { MaxSize = 40 })
		icon.Size = UDim2.fromOffset(60, 60)
		icon.Position = UDim2.fromOffset(8, 10)
		local title = Theme.Text(frame, def.Name, { MaxSize = 26, Align = Enum.TextXAlignment.Left })
		title.Size = UDim2.new(1, -260, 0, 34)
		title.Position = UDim2.fromOffset(74, 6)
		local info = Theme.Text(frame, def.Description, { MaxSize = 18, Color = Theme.Colors.SubText, Align = Enum.TextXAlignment.Left })
		info.Size = UDim2.new(1, -260, 0, 30)
		info.Position = UDim2.fromOffset(74, 42)
		local button = Theme.Button(frame, "Buy", Theme.Colors.Green, function()
			ctx.Request("BuyUpgrade", kind)
		end, {
			Size = UDim2.fromOffset(170, 60),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			MaxText = 22,
		})
		rows[kind] = { Info = info, Button = button }
	end

	local nextZone = Theme.Text(list, "", { MaxSize = 20, Color = Theme.Colors.Gold, LayoutOrder = 99 })
	nextZone.Size = UDim2.new(1, 0, 0, 30)

	local function refresh(state: any)
		local data = state.Data
		for kind, rowRefs in rows do
			local def = (Config.Upgrades :: any)[kind]
			local level = data[LEVEL_FIELD[kind]]
			local cost = Formulas.UpgradeCost(kind, level)
			local detail = def.Description .. "  (Level " .. level .. "/" .. def.MaxLevel .. ")"
			if kind == "Training" then
				detail = "Now +" .. Format.Number(state.SpeedPerSecond or 1) .. " Speed/s  (Level " .. level .. ")"
			elseif kind == "Pedestals" then
				detail = Formulas.PedestalCount(level) .. " pedestals  (+1 per level)"
			elseif kind == "Incubators" then
				detail = (state.IncubatorCapacity or Formulas.IncubatorCount(level)) .. " incubators  (+1 per level)"
			elseif kind == "Lock" then
				detail = Format.Duration(Formulas.LockSeconds(level, state.Passes and state.Passes.VIP)) .. " lock  (+15s per level)"
			end
			rowRefs.Info.Text = detail
			if cost then
				Theme.SetButtonText(rowRefs.Button, "$" .. Format.Number(cost))
				Theme.SetButtonEnabled(rowRefs.Button, data.Coins >= cost, Theme.Colors.Green)
			else
				Theme.SetButtonText(rowRefs.Button, "MAX")
				Theme.SetButtonEnabled(rowRefs.Button, false, Theme.Colors.Green)
			end
		end
		local best = Formulas.BestZone(data.Speed, data.Rebirths)
		local zone = Config.Zones[best + 1]
		if zone then
			local need = "Next zone: " .. zone.Name .. " - need " .. Format.Number(zone.GateSpeed) .. " Speed"
			if zone.RebirthsRequired > data.Rebirths then
				need ..= " + " .. zone.RebirthsRequired .. " rebirths"
			end
			nextZone.Text = need
		else
			nextZone.Text = "All zones unlocked!"
		end
	end

	return { Window = window, Refresh = refresh }
end

return UpgradeWindow
