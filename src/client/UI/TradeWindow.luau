--!strict
-- Trading: pick a player to send a request, answer incoming requests, and the trade screen
-- (your offer, their offer, your slimes to add, Accept -> Confirm). The server decides everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Theme = require(script.Parent.Theme)
local SlimeIcon = require(script.Parent.SlimeIcon)

local TradeWindow = {}

local function slimeName(slime: any): string
	local def = Config.Slimes[slime.Kind]
	local mutation = if slime.Mutation ~= "None" then (Config.Mutations :: any)[slime.Mutation].Name .. " " else ""
	return mutation .. (if def then def.Name else slime.Kind)
end

local function rarityColor(slime: any): Color3
	local def = Config.Slimes[slime.Kind]
	return if def then Theme.Hex(Config.Rarities[def.Rarity].Color) else Theme.Colors.Text
end

local function totalIncome(list: { any }): number
	local total = 0
	for _, slime in list do
		total += Formulas.SlimeIncome(slime.Kind, slime.Mutation)
	end
	return total
end

-- Small slime card; onClick = nil makes it display-only.
local function card(parent: Instance, slime: any, order: number, onClick: (() -> ())?)
	local frame = Theme.Frame({
		Name = slime.Id,
		Size = UDim2.fromOffset(96, 118),
		Color = Theme.Colors.Panel,
		LayoutOrder = order,
		Parent = parent,
	})
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rarityColor(slime)
	end
	local icon = SlimeIcon.Create(frame, slime.Kind, slime.Mutation, 52)
	icon.Position = UDim2.new(0.5, -26, 0, 2)
	local name = Theme.Text(frame, slimeName(slime), { MaxSize = 13, Color = rarityColor(slime) })
	name.Size = UDim2.new(1, -6, 0, 30)
	name.Position = UDim2.fromOffset(3, 54)
	local income = Theme.Text(
		frame,
		"$" .. Format.Number(Formulas.SlimeIncome(slime.Kind, slime.Mutation)) .. "/s",
		{ MaxSize = 13, Color = Theme.Colors.Green }
	)
	income.Size = UDim2.new(1, -6, 0, 16)
	income.Position = UDim2.fromOffset(3, 84)
	if onClick then
		local button = Instance.new("TextButton")
		button.Name = "Tap"
		button.BackgroundTransparency = 1
		button.Text = ""
		button.Size = UDim2.fromScale(1, 1)
		button.ZIndex = 5
		button.Activated:Connect(function()
			Theme.Play("Click", 0.4)
			onClick()
		end)
		button.Parent = frame
	end
	return frame
end

local function grid(parent: Instance, size: UDim2, position: UDim2): ScrollingFrame
	local scroll = Theme.Scroll(parent, size, position)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(96, 118)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	return scroll
end

function TradeWindow.Create(screen: ScreenGui, ctx: any)
	local window = Theme.Window(screen, "Trade", Vector2.new(880, 560), function()
		ctx.Close()
	end)
	local content = window.Content

	-- Lobby (not trading): players to ask -----------------------------------------------
	local lobby = Instance.new("Frame")
	lobby.Name = "Lobby"
	lobby.BackgroundTransparency = 1
	lobby.Size = UDim2.fromScale(1, 1)
	lobby.Parent = content
	local lobbyHint = Theme.Text(
		lobby,
		"Pick a player to trade slimes with. Both of you must Accept, then Confirm.",
		{ MaxSize = 18, Color = Theme.Colors.SubText }
	)
	lobbyHint.Size = UDim2.new(1, 0, 0, 26)
	local playerList = Theme.Scroll(lobby, UDim2.new(1, 0, 1, -34), UDim2.fromOffset(0, 34))
	Theme.List(playerList, 8)

	-- Trade screen ----------------------------------------------------------------------
	local tradeFrame = Instance.new("Frame")
	tradeFrame.Name = "TradeScreen"
	tradeFrame.BackgroundTransparency = 1
	tradeFrame.Size = UDim2.fromScale(1, 1)
	tradeFrame.Visible = false
	tradeFrame.Parent = content

	local function column(title: string, x: number)
		local header = Theme.Text(tradeFrame, title, { MaxSize = 20, Align = Enum.TextXAlignment.Left })
		header.Size = UDim2.new(0.5, -8, 0, 26)
		header.Position = UDim2.new(x, if x > 0 then 8 else 0, 0, 0)
		local box = Theme.Frame({
			Name = "Box",
			Size = UDim2.new(0.5, -8, 0, 194),
			Position = UDim2.new(x, if x > 0 then 8 else 0, 0, 28),
			Color = Theme.Colors.Background,
			Transparency = 0.2,
			Parent = tradeFrame,
		})
		local items = grid(box, UDim2.new(1, -12, 1, -12), UDim2.fromOffset(6, 6))
		local status = Theme.Text(tradeFrame, "", { MaxSize = 16, Align = Enum.TextXAlignment.Left })
		status.Size = UDim2.new(0.5, -8, 0, 22)
		status.Position = UDim2.new(x, if x > 0 then 8 else 0, 0, 224)
		return header, items, status
	end
	local myHeader, myItems, myStatus = column("Your offer", 0)
	local theirHeader, theirItems, theirStatus = column("Their offer", 0.5)
	local _ = myHeader

	local pickHint = Theme.Text(
		tradeFrame,
		"Tap your slimes below to add them. Tap an offered slime to take it back.",
		{ MaxSize = 15, Color = Theme.Colors.SubText }
	)
	pickHint.Size = UDim2.new(1, 0, 0, 20)
	pickHint.Position = UDim2.fromOffset(0, 248)
	local mine = grid(tradeFrame, UDim2.new(1, -200, 1, -272), UDim2.fromOffset(0, 270))

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(0, 190, 1, -272)
	buttons.Position = UDim2.new(1, -190, 0, 270)
	buttons.Parent = tradeFrame
	Theme.List(buttons, 10)
	local acceptButton = Theme.Button(buttons, "Accept", Theme.Colors.Green, function() end, {
		Size = UDim2.fromOffset(184, 64),
		LayoutOrder = 1,
	})
	local cancelButton = Theme.Button(buttons, "Cancel", Theme.Colors.Red, function()
		ctx.Request("TradeCancel")
	end, { Size = UDim2.fromOffset(184, 54), LayoutOrder = 2 })
	local _ = cancelButton

	-- Incoming request banner (shown even when the window is closed) ------------------------
	local banner = Theme.Frame({
		Name = "TradeRequest",
		Size = UDim2.fromOffset(460, 70),
		Position = UDim2.new(0.5, 0, 0, 96),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = Theme.Colors.Window,
		Parent = screen,
	})
	banner.Visible = false
	banner.ZIndex = 20
	Theme.AutoScale(banner)
	local bannerText = Theme.Text(banner, "", { MaxSize = 20, Align = Enum.TextXAlignment.Left })
	bannerText.Size = UDim2.new(1, -230, 1, -10)
	bannerText.Position = UDim2.fromOffset(12, 5)
	local bannerFrom: number? = nil
	Theme.Button(banner, "Accept", Theme.Colors.Green, function()
		if bannerFrom then
			ctx.Request("TradeRespond", { From = bannerFrom, Accept = true })
		end
	end, { Size = UDim2.fromOffset(104, 52), Position = UDim2.new(1, -218, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	Theme.Button(banner, "No", Theme.Colors.Red, function()
		if bannerFrom then
			ctx.Request("TradeRespond", { From = bannerFrom, Accept = false })
		end
	end, { Size = UDim2.fromOffset(100, 52), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) })

	local current: any = nil -- latest state.Trade
	local confirmAt = 0 -- os.clock() when Confirm unlocks (local estimate)
	local lastTradeId: number? = nil

	local function updateAcceptButton()
		local trade = current
		if not trade then
			return
		end
		if trade.Phase == "Confirm" then
			local left = math.ceil(confirmAt - os.clock())
			if trade.MeConfirmed then
				Theme.SetButtonText(acceptButton, "Waiting...")
				Theme.SetButtonEnabled(acceptButton, false, Theme.Colors.Gold)
			elseif left > 0 then
				Theme.SetButtonText(acceptButton, "Confirm (" .. left .. ")")
				Theme.SetButtonEnabled(acceptButton, false, Theme.Colors.Gold)
			else
				Theme.SetButtonText(acceptButton, "CONFIRM")
				Theme.SetButtonEnabled(acceptButton, true, Theme.Colors.Gold)
			end
		else
			Theme.SetButtonText(acceptButton, if trade.MeAccepted then "Unaccept" else "Accept")
			Theme.SetButtonEnabled(
				acceptButton,
				true,
				if trade.MeAccepted then Theme.Colors.PanelLight else Theme.Colors.Green
			)
		end
	end

	acceptButton.Activated:Connect(function()
		local trade = current
		if not trade then
			return
		end
		if trade.Phase == "Confirm" then
			if not trade.MeConfirmed and os.clock() >= confirmAt then
				ctx.Request("TradeConfirm")
			end
		else
			ctx.Request("TradeAccept", not trade.MeAccepted)
		end
	end)

	local function refreshLobby(state: any)
		Theme.Clear(playerList)
		if state.CanTrade == false then
			local text = Theme.Text(playerList, "Trading isn't available for your account.", {
				MaxSize = 22,
				Color = Theme.Colors.SubText,
			})
			text.Size = UDim2.new(1, 0, 0, 50)
			return
		end
		local others = {}
		for _, other in Players:GetPlayers() do
			if other ~= Players.LocalPlayer then
				table.insert(others, other)
			end
		end
		if #others == 0 then
			local text = Theme.Text(playerList, "No one else is here yet. Invite a friend!", {
				MaxSize = 22,
				Color = Theme.Colors.SubText,
			})
			text.Size = UDim2.new(1, 0, 0, 50)
			return
		end
		for order, other in others do
			local row = Theme.Frame({
				Name = tostring(other.UserId),
				Size = UDim2.new(1, -16, 0, 64),
				Color = Theme.Colors.Panel,
				LayoutOrder = order,
				Parent = playerList,
			})
			local name = Theme.Text(row, other.DisplayName .. '  <font size="14">@' .. other.Name .. "</font>", {
				MaxSize = 22,
				Align = Enum.TextXAlignment.Left,
			})
			name.Size = UDim2.new(1, -200, 1, -12)
			name.Position = UDim2.fromOffset(12, 6)
			Theme.Button(row, "Trade", Theme.Colors.Blue, function()
				ctx.Request("TradeRequest", other.UserId)
			end, {
				Size = UDim2.fromOffset(150, 48),
				Position = UDim2.new(1, -10, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
			})
		end
	end

	local function refreshTrade(state: any)
		local trade = state.Trade
		Theme.Clear(myItems)
		Theme.Clear(theirItems)
		Theme.Clear(mine)
		theirHeader.Text = trade.Partner .. "'s offer"
		local offered: { [string]: boolean } = {}
		local myIds: { string } = {}
		for _, slime in trade.Mine do
			offered[slime.Id] = true
			table.insert(myIds, slime.Id)
		end
		local editable = trade.Phase == "Offer"
		for order, slime in trade.Mine do
			card(
				myItems,
				slime,
				order,
				if editable
					then function()
						local ids = {}
						for _, id in myIds do
							if id ~= slime.Id then
								table.insert(ids, id)
							end
						end
						ctx.Request("TradeSetOffer", ids)
					end
					else nil
			)
		end
		for order, slime in trade.Theirs do
			card(theirItems, slime, order, nil)
		end
		local function statusText(list: { any }, accepted: boolean, confirmed: boolean): string
			local mark = if confirmed then "  ✅ Confirmed" elseif accepted then "  ✔ Accepted" else ""
			return #list
				.. "/"
				.. Config.Trading.MaxItems
				.. "  ·  $"
				.. Format.Number(totalIncome(list))
				.. "/s"
				.. mark
		end
		myStatus.Text = statusText(trade.Mine, trade.MeAccepted, trade.MeConfirmed)
		theirStatus.Text = statusText(trade.Theirs, trade.ThemAccepted, trade.ThemConfirmed)
		myStatus.TextColor3 = if trade.MeAccepted then Theme.Colors.Green else Theme.Colors.Text
		theirStatus.TextColor3 = if trade.ThemAccepted then Theme.Colors.Green else Theme.Colors.Text

		pickHint.Text = if editable
			then "Tap your slimes below to add them. Tap an offered slime to take it back."
			else "Offers are locked. Check them carefully, then press CONFIRM. Cancel if anything is wrong!"
		pickHint.TextColor3 = if editable then Theme.Colors.SubText else Theme.Colors.Gold

		-- my slimes to add (best first); locked ones can't be traded
		local sorted: { any } = table.clone(state.Data.Slimes)
		table.sort(sorted, function(a, b)
			return Formulas.SlimeIncome(a.Kind, a.Mutation) > Formulas.SlimeIncome(b.Kind, b.Mutation)
		end)
		local order = 0
		for _, slime in sorted do
			if not offered[slime.Id] then
				order += 1
				local canAdd = editable and not slime.Locked and #myIds < Config.Trading.MaxItems
				local frame = card(
					mine,
					slime,
					order,
					if canAdd
						then function()
							local ids = table.clone(myIds)
							table.insert(ids, slime.Id)
							ctx.Request("TradeSetOffer", ids)
						end
						else nil
				)
				if slime.Locked or not editable then
					frame.BackgroundColor3 = Theme.Colors.Disabled
				end
				if slime.Locked then
					local lock = Theme.Text(frame, "🔒", { MaxSize = 20 })
					lock.Size = UDim2.fromOffset(26, 26)
					lock.Position = UDim2.fromOffset(2, 2)
				end
			end
		end
		updateAcceptButton()
	end

	local function refresh(state: any)
		local trade = state.Trade
		current = trade
		lobby.Visible = trade == nil
		tradeFrame.Visible = trade ~= nil
		if trade then
			confirmAt = os.clock() + (trade.ConfirmIn or 0)
			refreshTrade(state)
		else
			refreshLobby(state)
		end
	end

	-- Called on every full state, even while the window is closed.
	local function onState(state: any)
		local trade = state.Trade
		-- a new trade opens the window for both players
		if trade and trade.Id ~= lastTradeId then
			lastTradeId = trade.Id
			ctx.Open("Trade", true)
		elseif not trade and lastTradeId then
			lastTradeId = nil
		end
		current = trade
		local requests = state.TradeRequests or {}
		local first = requests[1]
		if first and not trade then
			bannerFrom = first.UserId
			bannerText.Text = "🤝 <b>" .. first.Name .. "</b> wants to trade!"
			banner.Visible = true
		else
			bannerFrom = nil
			banner.Visible = false
		end
	end

	task.spawn(function()
		while true do
			task.wait(0.25)
			if tradeFrame.Visible and window.Frame.Visible then
				updateAcceptButton()
			end
		end
	end)

	Players.PlayerAdded:Connect(function()
		if lobby.Visible and window.Frame.Visible and ctx.State() then
			refreshLobby(ctx.State())
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if lobby.Visible and window.Frame.Visible and ctx.State() then
				refreshLobby(ctx.State())
			end
		end)
	end)

	return { Window = window, Refresh = refresh, OnState = onState }
end

return TradeWindow
