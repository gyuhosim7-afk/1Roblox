--!strict
-- Renders hatch odds (every outcome with its %), used by the Index, the Royal Egg purchase
-- screen and the nest panel. Always shows the player's real odds including active luck.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Odds = require(Shared.Odds)
local Theme = require(script.Parent.Theme)

local OddsView = {}

OddsView.Disclaimer = "Probabilities are rounded; the total of displayed probabilities may not equal 100%."

local function row(parent: Instance, left: string, right: string, color: Color3, order: number, height: number?)
	local frame = Instance.new("Frame")
	frame.Name = "Row"
	frame.BackgroundColor3 = Theme.Colors.PanelLight
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, -8, 0, height or 30)
	frame.LayoutOrder = order
	Theme.Corner(frame, 8)
	local leftLabel = Theme.Text(frame, left, { MaxSize = 20, Color = color, Align = Enum.TextXAlignment.Left })
	leftLabel.Size = UDim2.new(0.68, -8, 1, -4)
	leftLabel.Position = UDim2.fromOffset(8, 2)
	local rightLabel = Theme.Text(frame, right, { MaxSize = 20, Align = Enum.TextXAlignment.Right })
	rightLabel.Size = UDim2.new(0.32, -8, 1, -4)
	rightLabel.Position = UDim2.new(0.68, 0, 0, 2)
	frame.Parent = parent
	return frame
end

-- Adds rows for every slime outcome and the mutation chances. Returns the next layout order.
function OddsView.Build(
	parent: Instance,
	entries: { Odds.Entry },
	mutations: { Odds.MutationEntry },
	discovered: { [string]: boolean }?,
	startOrder: number?
): number
	local order = startOrder or 0
	for _, entry in entries do
		order += 1
		local def = Config.Slimes[entry.Slime]
		local known = discovered == nil or discovered[entry.Slime] == true
		local name = if known then def.Name else "???"
		local rarityColor = Theme.Hex(Config.Rarities[def.Rarity].Color)
		row(parent, name .. "  <font size=\"14\">" .. def.Rarity .. "</font>", Format.Percent(entry.Chance), rarityColor, order)
	end
	order += 1
	local mutationText = {}
	for _, m in mutations do
		if m.Mutation ~= "None" then
			local mdef = (Config.Mutations :: any)[m.Mutation]
			table.insert(mutationText, mdef.Name .. " x" .. mdef.Multiplier .. ": " .. Format.Percent(m.Chance))
		end
	end
	row(parent, "Mutations  " .. table.concat(mutationText, "   "), "", Theme.Colors.Gold, order, 30)
	return order
end

function OddsView.LuckText(luck: number): string
	if luck <= 1 then
		return "Your luck: x1"
	end
	return "Your luck: x" .. Format.Number(luck) .. " (Rare+ slimes and mutations are more likely)"
end

return OddsView
