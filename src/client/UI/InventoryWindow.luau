--!strict
-- Slime storage: best slimes go on pedestals automatically; here you can lock or sell slimes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Theme = require(script.Parent.Theme)
local SlimeIcon = require(script.Parent.SlimeIcon)

local InventoryWindow = {}

function InventoryWindow.Create(screen: ScreenGui, ctx: any)
	local window = Theme.Window(screen, "Slimes", Vector2.new(820, 520), ctx.Close)
	local content = window.Content

	local topRow = Instance.new("Frame")
	topRow.BackgroundTransparency = 1
	topRow.Size = UDim2.new(1, 0, 0, 50)
	topRow.Parent = content
	local count = Theme.Text(topRow, "0/100", { MaxSize = 24, Align = Enum.TextXAlignment.Left })
	count.Size = UDim2.fromScale(0.3, 1)
	local sellButtons = Instance.new("Frame")
	sellButtons.BackgroundTransparency = 1
	sellButtons.Size = UDim2.fromScale(0.7, 1)
	sellButtons.Position = UDim2.fromScale(0.3, 0)
	sellButtons.Parent = topRow
	local layout = Theme.List(sellButtons, 8, true, Enum.HorizontalAlignment.Right)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	local sellOptions: { { Max: number, Text: string } } = {
		{ Max = 1, Text = "Sell Commons" },
		{ Max = 2, Text = "Sell Uncommon-" },
		{ Max = 3, Text = "Sell Rare-" },
	}
	for order, info in sellOptions do
		Theme.Button(sellButtons, info.Text, Theme.Colors.Red, function()
			ctx.Request("SellAllBelow", info.Max)
		end, { Size = UDim2.fromOffset(170, 44), LayoutOrder = order, MaxText = 18 })
	end

	local hint = Theme.Text(
		content,
		"Your best slimes stand on pedestals and earn coins. Locked slimes are never sold.",
		{ MaxSize = 16, Color = Theme.Colors.SubText }
	)
	hint.Size = UDim2.new(1, 0, 0, 22)
	hint.Position = UDim2.fromOffset(0, 52)

	local scroll = Theme.Scroll(content, UDim2.new(1, 0, 1, -80), UDim2.fromOffset(0, 80))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(148, 196)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	local function card(slime: any, order: number, onPedestal: boolean)
		local def = Config.Slimes[slime.Kind]
		if not def then
			return
		end
		local frame = Theme.Frame({
			Name = slime.Id,
			Size = UDim2.fromOffset(148, 196),
			Color = Theme.Colors.Panel,
			LayoutOrder = order,
			Parent = scroll,
		})
		local stroke = frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Theme.Hex(Config.Rarities[def.Rarity].Color)
		end
		local icon = SlimeIcon.Create(frame, slime.Kind, slime.Mutation, 64)
		icon.Position = UDim2.new(0.5, -32, 0, 4)
		local mutationName = if slime.Mutation ~= "None" then (Config.Mutations :: any)[slime.Mutation].Name .. " " else ""
		local name = Theme.Text(frame, mutationName .. def.Name, {
			MaxSize = 16,
			Color = Theme.Hex(Config.Rarities[def.Rarity].Color),
		})
		name.Size = UDim2.new(1, -8, 0, 34)
		name.Position = UDim2.fromOffset(4, 68)
		local income = Theme.Text(frame, "$" .. Format.Number(Formulas.SlimeIncome(slime.Kind, slime.Mutation)) .. "/s", {
			MaxSize = 16,
			Color = Theme.Colors.Green,
		})
		income.Size = UDim2.new(1, -8, 0, 20)
		income.Position = UDim2.fromOffset(4, 102)
		if onPedestal then
			local badge = Theme.Text(frame, "ON PEDESTAL", { MaxSize = 12, Color = Theme.Colors.Gold })
			badge.Size = UDim2.new(1, -8, 0, 14)
			badge.Position = UDim2.fromOffset(4, 122)
		end
		Theme.Button(frame, if slime.Locked then "🔒" else "🔓", Theme.Colors.PanelLight, function()
			ctx.Request("LockSlime", slime.Id)
		end, { Size = UDim2.fromOffset(42, 46), Position = UDim2.fromOffset(6, 142), MaxText = 20 })
		local sell = Theme.Button(frame, "Sell $" .. Format.Number(Formulas.SellPrice(slime.Kind, slime.Mutation)), Theme.Colors.Red, function()
			ctx.Request("SellSlime", slime.Id)
		end, { Size = UDim2.fromOffset(90, 46), Position = UDim2.fromOffset(52, 142), MaxText = 14 })
		if slime.Locked then
			Theme.SetButtonEnabled(sell, false, Theme.Colors.Red)
		end
	end

	local function refresh(state: any)
		local data = state.Data
		count.Text = "Slimes: " .. #data.Slimes .. "/" .. Config.Base.MaxSlimes
		Theme.Clear(scroll)
		local onPedestal: { [string]: boolean } = {}
		for _, id in state.PedestalIds or {} do
			onPedestal[id] = true
		end
		local sorted: { any } = table.clone(data.Slimes)
		table.sort(sorted, function(a, b)
			return Formulas.SlimeIncome(a.Kind, a.Mutation) > Formulas.SlimeIncome(b.Kind, b.Mutation)
		end)
		for index, slime in sorted do
			card(slime, index, onPedestal[slime.Id] == true)
		end
		if #sorted == 0 then
			local empty = Theme.Text(scroll, "No slimes yet! Steal an egg from the Meadow and bring it home.", {
				MaxSize = 22,
				Color = Theme.Colors.SubText,
			})
			empty.Size = UDim2.fromOffset(600, 60)
		end
	end

	return { Window = window, Refresh = refresh }
end

return InventoryWindow
