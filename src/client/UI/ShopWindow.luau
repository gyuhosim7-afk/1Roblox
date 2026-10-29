--!strict
-- Shop: game passes, gem packs and boosts. Random items (Royal Egg) open an odds screen
-- before any purchase; luck items explain their exact effect. Hidden for restricted players.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Theme = require(script.Parent.Theme)

local ShopWindow = {}

local PASS_ICONS = {
	DoubleCoins = "💰",
	DoubleSpeed = "⚡",
	AutoCollect = "🧲",
	ExtraIncubators = "🥚",
	VIP = "👑",
	Lucky = "🍀",
	VIPTreadmill = "🏃",
}

function ShopWindow.Create(screen: ScreenGui, ctx: any)
	local window = Theme.Window(screen, "Shop", Vector2.new(840, 540), ctx.Close)
	local content = window.Content
	local tab = "Boosts"

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
	local tabButtons: { [string]: TextButton } = {}
	for order, info in { { "Boosts", "🚀 Boosts" }, { "Passes", "⭐ Passes" }, { "Gems", "💎 Gems" } } do
		tabButtons[info[1]] = Theme.Button(tabs, info[2], Theme.Colors.Pink, function()
			tab = info[1]
			if lastState then
				refresh(lastState)
			end
		end, { Size = UDim2.fromOffset(200, 42), LayoutOrder = order, MaxText = 20 })
	end

	local function makeGrid(): ScrollingFrame
		local scroll = Theme.Scroll(body)
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(255, 200)
		grid.CellPadding = UDim2.fromOffset(10, 10)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = scroll
		return scroll
	end

	local function itemCard(
		parent: Instance,
		order: number,
		icon: string,
		title: string,
		description: string,
		color: Color3
	): Frame
		local frame = Theme.Frame({
			Size = UDim2.fromOffset(255, 200),
			Color = Theme.Colors.Panel,
			LayoutOrder = order,
			Parent = parent,
		})
		local stroke = frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
		end
		local iconLabel = Theme.Text(frame, icon, { MaxSize = 36 })
		iconLabel.Size = UDim2.fromOffset(50, 46)
		iconLabel.Position = UDim2.fromOffset(6, 6)
		local titleLabel = Theme.Text(frame, title, { MaxSize = 22, Color = color, Align = Enum.TextXAlignment.Left })
		titleLabel.Size = UDim2.new(1, -66, 0, 46)
		titleLabel.Position = UDim2.fromOffset(58, 6)
		local desc = Theme.Text(frame, description, { MaxSize = 15, Color = Theme.Colors.SubText })
		desc.Size = UDim2.new(1, -16, 0, 74)
		desc.Position = UDim2.fromOffset(8, 54)
		return frame
	end

	local function buyRow(
		frame: Frame,
		buttons: { { text: string, color: Color3, onClick: () -> (), enabled: boolean? } }
	)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -12, 0, 54)
		row.Position = UDim2.new(0, 6, 1, -60)
		row.Parent = frame
		Theme.List(row, 6, true)
		local width = math.floor((243 - 6 * (#buttons - 1)) / #buttons)
		for order, b in buttons do
			local button = Theme.Button(
				row,
				b.text,
				b.color,
				b.onClick,
				{ Size = UDim2.fromOffset(width, 52), LayoutOrder = order, MaxText = 20 }
			)
			if b.enabled == false then
				Theme.SetButtonEnabled(button, false, b.color)
			end
		end
	end

	local function buildPasses(state: any)
		local scroll = makeGrid()
		for order, key in Config.PassOrder do
			local def = (Config.Passes :: any)[key]
			local hidden = def.RandomItemModifier and state.Restricted
			if not hidden then
				local owned = state.Passes and state.Passes[key]
				local frame =
					itemCard(scroll, order, PASS_ICONS[key] or "⭐", def.Name, def.Description, Theme.Colors.Accent)
				if owned then
					buyRow(frame, {
						{
							text = "OWNED ✔",
							color = Theme.Colors.Green,
							onClick = function() end,
							enabled = false,
						},
					})
				else
					local buttons = {
						{
							text = "R$ " .. def.Price,
							color = Theme.Colors.Green,
							onClick = function()
								ctx.Request("BuyPass", key)
							end,
						},
					}
					if def.RandomItemModifier then
						table.insert(buttons, {
							text = "View Odds",
							color = Theme.Colors.Purple,
							onClick = function()
								ctx.Open("Index")
							end,
						})
					end
					buyRow(frame, buttons)
				end
			end
		end
	end

	local function buildGems()
		local scroll = makeGrid()
		for order, key in { "Gems100", "Gems350", "Gems1000", "Gems2800" } do
			local def = (Config.Products :: any)[key]
			local bonus = math.floor((def.Gems / def.Price) / (100 / 49) * 100 - 100 + 0.5)
			local desc = "Use gems for potions, Royal Eggs and hatching eggs instantly."
			if bonus > 0 then
				desc = "+" .. bonus .. "% bonus gems!\n" .. desc
			end
			local frame = itemCard(scroll, order, "💎", def.Name, desc, Theme.Colors.Gem)
			buyRow(frame, {
				{
					text = "R$ " .. def.Price,
					color = Theme.Colors.Green,
					onClick = function()
						ctx.Request("BuyProduct", key)
					end,
				},
			})
		end
	end

	local function buildBoosts(state: any)
		local scroll = makeGrid()
		local restricted = state.Restricted
		local order = 0
		local function product(
			key: string,
			icon: string,
			description: string,
			gemItem: string?,
			color: Color3,
			extraButton: any?
		)
			local def = (Config.Products :: any)[key]
			order += 1
			local frame = itemCard(scroll, order, icon, def.Name, description, color)
			local buttons = {
				{
					text = "R$ " .. def.Price,
					color = Theme.Colors.Green,
					onClick = function()
						ctx.Request("BuyProduct", key)
					end,
				},
			}
			if gemItem then
				local cost = (Config.GemShop :: any)[gemItem]
				table.insert(buttons, {
					text = cost .. " 💎",
					color = Theme.Colors.Blue,
					onClick = function()
						ctx.Request("BuyWithGems", gemItem)
					end,
					enabled = state.Data.Gems >= cost,
				})
			end
			if extraButton then
				table.insert(buttons, extraButton)
			end
			buyRow(frame, buttons)
		end

		if not restricted then
			-- Random item: the odds screen must be seen before buying, so the card only opens it.
			order += 1
			local royal = Config.Products.RoyalEgg
			local frame = itemCard(
				scroll,
				order,
				"👑",
				royal.Name,
				"Hatch a Rare-or-better slime from your best zone instantly! Tap to see every outcome's odds first.",
				Theme.Colors.Gold
			)
			buyRow(frame, {
				{
					text = "See Odds & Buy",
					color = Theme.Colors.Gold,
					onClick = function()
						ctx.ShowRoyalOdds()
					end,
				},
			})
			product(
				"LuckPotion",
				"🍀",
				"Luck x"
					.. Config.Luck.PotionMultiplier
					.. " for 15 min: Rare+ slimes and mutations become "
					.. Config.Luck.PotionMultiplier
					.. "x more likely. Odds in the Index update live.",
				"LuckPotion",
				Theme.Colors.Green
			)
			product(
				"ServerLuck",
				"🌟",
				"Luck x" .. Config.Luck.ServerMultiplier .. " for EVERYONE in this server for 15 minutes!",
				nil,
				Theme.Colors.Pink,
				{
					text = "Odds",
					color = Theme.Colors.Purple,
					onClick = function()
						ctx.Open("Index")
					end,
				}
			)
		end
		product(
			"SpeedPotion",
			"⚡",
			"Speed gain x" .. Config.Boosts.SpeedPotionMultiplier .. " for 15 minutes.",
			"SpeedPotion",
			Theme.Colors.Gold
		)
		local income = state.IncomePerSecond or 0
		product(
			"CashSmall",
			"💵",
			"Get $" .. Format.Number(Formulas.CashPackCoins("CashSmall", income)) .. " now (15 min of your income).",
			nil,
			Theme.Colors.Green
		)
		product(
			"CashLarge",
			"💰",
			"Get $" .. Format.Number(Formulas.CashPackCoins("CashLarge", income)) .. " now (1 hour of your income).",
			nil,
			Theme.Colors.Green
		)
		product("InstantHatch", "⏩", "Hatch every egg in your incubators right now.", nil, Theme.Colors.Blue)
	end

	refresh = function(state: any)
		lastState = state
		Theme.Clear(body)
		for name, button in tabButtons do
			button.BackgroundColor3 = if name == tab then Theme.Colors.Pink else Theme.Colors.PanelLight
		end
		if tab == "Passes" then
			buildPasses(state)
		elseif tab == "Gems" then
			buildGems()
		else
			buildBoosts(state)
		end
	end

	return { Window = window, Refresh = refresh }
end

return ShopWindow
