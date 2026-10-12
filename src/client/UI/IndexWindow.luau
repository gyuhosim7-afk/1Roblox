--!strict
-- Index: every egg's odds (with the player's current luck) and the Slimedex collection.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Odds = require(Shared.Odds)
local Theme = require(script.Parent.Theme)
local OddsView = require(script.Parent.OddsView)
local SlimeIcon = require(script.Parent.SlimeIcon)

local IndexWindow = {}

function IndexWindow.Create(screen: ScreenGui, ctx: any)
	local window = Theme.Window(screen, "Index & Odds", Vector2.new(820, 540), ctx.Close)
	local content = window.Content
	local tab = "Eggs"

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, 0, 0, 46)
	tabs.Parent = content
	Theme.List(tabs, 10, true)

	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 1, -54)
	body.Position = UDim2.fromOffset(0, 54)
	body.Parent = content

	local lastState: any = nil
	local refresh: (any) -> ()

	local eggsButton = Theme.Button(tabs, "🥚 Eggs & Odds", Theme.Colors.Purple, function()
		tab = "Eggs"
		if lastState then
			refresh(lastState)
		end
	end, { Size = UDim2.fromOffset(220, 42), LayoutOrder = 1, MaxText = 20 })
	local dexButton = Theme.Button(tabs, "📖 Slimedex", Theme.Colors.Blue, function()
		tab = "Dex"
		if lastState then
			refresh(lastState)
		end
	end, { Size = UDim2.fromOffset(220, 42), LayoutOrder = 2, MaxText = 20 })

	local function buildEggs(state: any)
		local scroll = Theme.Scroll(body)
		Theme.List(scroll, 6)
		local luck = state.Luck or 1
		local header = Theme.Text(scroll, OddsView.LuckText(luck), { MaxSize = 20, Color = Theme.Colors.Gold, LayoutOrder = 0 })
		header.Size = UDim2.new(1, -8, 0, 28)
		local disclaimer = Theme.Text(scroll, OddsView.Disclaimer, { MaxSize = 14, Color = Theme.Colors.SubText, LayoutOrder = 1 })
		disclaimer.Size = UDim2.new(1, -8, 0, 20)
		local order = 2
		for zoneIndex, zone in Config.Zones do
			local egg = Config.Eggs[zone.Egg]
			order += 1
			local unlocked = zoneIndex <= state.Data.BestZone
			local title = Theme.Text(
				scroll,
				egg.Name .. "  -  " .. zone.Name .. (if unlocked then "" else "  (need " .. Format.Number(zone.GateSpeed) .. " Speed)"),
				{ MaxSize = 22, Color = Theme.Hex(egg.SpotColor), LayoutOrder = order, Align = Enum.TextXAlignment.Left }
			)
			title.Size = UDim2.new(1, -8, 0, 32)
			order = OddsView.Build(scroll, Odds.EggOdds(zone.Egg, luck), Odds.MutationOdds(luck), state.Data.Discovered, order)
		end
	end

	local function buildDex(state: any)
		local scroll = Theme.Scroll(body)
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(120, 150)
		grid.CellPadding = UDim2.fromOffset(8, 8)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = scroll
		local order = 0
		local found, total = 0, 0
		for _, eggId in Config.EggOrder do
			for _, entry in Config.Eggs[eggId].Pool do
				order += 1
				total += 1
				local def = Config.Slimes[entry.Slime]
				local known = state.Data.Discovered[entry.Slime] == true
				if known then
					found += 1
				end
				local frame = Theme.Frame({
					Size = UDim2.fromOffset(120, 150),
					Color = Theme.Colors.Panel,
					LayoutOrder = order,
					Parent = scroll,
				})
				local stroke = frame:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = Theme.Hex(Config.Rarities[def.Rarity].Color)
				end
				local icon = SlimeIcon.Create(frame, entry.Slime, nil, 64, not known)
				icon.Position = UDim2.new(0.5, -32, 0, 6)
				local name = Theme.Text(frame, if known then def.Name else "???", {
					MaxSize = 15,
					Color = Theme.Hex(Config.Rarities[def.Rarity].Color),
				})
				name.Size = UDim2.new(1, -8, 0, 36)
				name.Position = UDim2.fromOffset(4, 72)
				local reward = Theme.Text(
					frame,
					if known then "$" .. Format.Number(def.Income) .. "/s" else "+" .. Config.Rarities[def.Rarity].DiscoveryGems .. " 💎",
					{ MaxSize = 14, Color = if known then Theme.Colors.Green else Theme.Colors.Gem }
				)
				reward.Size = UDim2.new(1, -8, 0, 20)
				reward.Position = UDim2.fromOffset(4, 110)
			end
		end
		window.Title.Text = "Index & Odds  (" .. found .. "/" .. total .. ")"
	end

	refresh = function(state: any)
		lastState = state
		Theme.Clear(body)
		eggsButton.BackgroundColor3 = if tab == "Eggs" then Theme.Colors.Purple else Theme.Colors.PanelLight
		dexButton.BackgroundColor3 = if tab == "Dex" then Theme.Colors.Blue else Theme.Colors.PanelLight
		if tab == "Eggs" then
			buildEggs(state)
		else
			buildDex(state)
		end
	end

	return {
		Window = window,
		Refresh = refresh,
		ShowTab = function(name: string)
			tab = name
		end,
	}
end

return IndexWindow
