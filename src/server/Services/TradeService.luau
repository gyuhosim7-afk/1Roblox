--!strict
-- Player <-> player slime trades (Adopt Me style), decided only on the server.
--   1. A asks B ("TradeRequest"); B accepts or declines ("TradeRespond").
--   2. Both put up to Config.Trading.MaxItems slimes on the table ("TradeSetOffer").
--      Any change clears both accepts.
--   3. Both press Accept ("TradeAccept") -> offers freeze, Confirm unlocks after ConfirmDelay.
--   4. Both press Confirm ("TradeConfirm") -> items are checked again and swapped, both saved.
-- Either side can cancel at any time ("TradeCancel"); leaving the game cancels too.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Validate = require(script.Parent.Parent.Logic.Validate)
local ProfileSchema = require(script.Parent.Parent.Logic.ProfileSchema)
local SlimeInventory = require(script.Parent.Parent.Logic.SlimeInventory)
local PlayerService = require(script.Parent.PlayerService)
local DataService = require(script.Parent.DataService)
local SlimeService = require(script.Parent.SlimeService)
local MonetizationService = require(script.Parent.MonetizationService)
local Network = require(script.Parent.Network)

local TradeService = {}

type Trade = {
	Id: number,
	Players: { Player }, -- exactly two
	Offers: { [Player]: { string } }, -- slime ids, in the order they were added
	Accepted: { [Player]: boolean },
	Confirmed: { [Player]: boolean },
	Phase: string, -- "Offer" | "Confirm"
	ConfirmAt: number, -- os.clock() when Confirm starts to work
}

local trades: { [Player]: Trade } = {}
local requests: { [Player]: { [Player]: number } } = {} -- [target][from] = expires (os.clock)
local lastAsked: { [Player]: { [Player]: number } } = {} -- [from][target] = os.clock
local nextTradeId = 0

local function partnerOf(trade: Trade, player: Player): Player
	return if trade.Players[1] == player then trade.Players[2] else trade.Players[1]
end

local function markBoth(trade: Trade)
	for _, player in trade.Players do
		PlayerService.MarkDirty(player, true)
	end
end

local function canTrade(player: Player): (boolean, string?)
	if not PlayerService.Get(player) then
		return false, "Still loading..."
	end
	if not MonetizationService.CanTrade(player) then
		return false, "Trading isn't available for this account."
	end
	return true, nil
end

local function resetAccepts(trade: Trade)
	trade.Phase = "Offer"
	trade.Accepted = {}
	trade.Confirmed = {}
end

local function endTrade(trade: Trade, message: string?, kind: string?)
	for _, player in trade.Players do
		if trades[player] == trade then
			trades[player] = nil
		end
		if message and player.Parent then
			Network.Notify(player, message, kind)
		end
		PlayerService.MarkDirty(player, true)
	end
end

-- Drops offered ids the player no longer owns (sold, or locked since). Returns true if any changed.
local function pruneOffer(trade: Trade, player: Player): boolean
	local session = PlayerService.Get(player)
	local offer = trade.Offers[player]
	if not session then
		return false
	end
	local kept = {}
	for _, id in offer do
		local _, slime = SlimeInventory.Find(session.Data.Slimes, id)
		if slime and not slime.Locked then
			table.insert(kept, id)
		end
	end
	if #kept == #offer then
		return false
	end
	trade.Offers[player] = kept
	return true
end

local function record(slime: ProfileSchema.SlimeRecord): string
	return slime.Kind .. "/" .. slime.Mutation
end

local function logTrade(data: ProfileSchema.Data, partner: Player, gave: { string }, got: { string })
	table.insert(data.TradeLog, {
		With = partner.Name,
		UserId = partner.UserId,
		Gave = gave,
		Got = got,
		At = os.time(),
	})
	while #data.TradeLog > Config.Trading.LogSize do
		table.remove(data.TradeLog, 1)
	end
	data.Stats.Trades += 1
end

-- Checks everything again and swaps the slimes. Returns an error message if it can't.
local function execute(trade: Trade): string?
	local a, b = trade.Players[1], trade.Players[2]
	local sa, sb = PlayerService.Get(a), PlayerService.Get(b)
	if not sa or not sb then
		return "The other player left."
	end
	local offerA, offerB = trade.Offers[a], trade.Offers[b]
	if #offerA == 0 and #offerB == 0 then
		return "The trade is empty."
	end
	-- every offered slime must still be owned and unlocked
	local function collect(data: ProfileSchema.Data, ids: { string }): { ProfileSchema.SlimeRecord }?
		local list = {}
		for _, id in ids do
			local _, slime = SlimeInventory.Find(data.Slimes, id)
			if not slime or slime.Locked then
				return nil
			end
			table.insert(list, slime)
		end
		return list
	end
	local giveA, giveB = collect(sa.Data, offerA), collect(sb.Data, offerB)
	if not giveA or not giveB then
		return "A slime in the trade is gone or locked."
	end
	local max = Config.Base.MaxSlimes
	if #sa.Data.Slimes - #giveA + #giveB > max then
		return a.DisplayName .. " has no room for more slimes."
	end
	if #sb.Data.Slimes - #giveB + #giveA > max then
		return b.DisplayName .. " has no room for more slimes."
	end

	-- swap (new ids in the receiver's numbering; traded slimes arrive unlocked)
	local function move(
		from: ProfileSchema.Data,
		to: ProfileSchema.Data,
		list: { ProfileSchema.SlimeRecord }
	): { string }
		local names = {}
		for _, slime in list do
			local index = SlimeInventory.Find(from.Slimes, slime.Id)
			if index then
				table.remove(from.Slimes, index)
			end
			table.insert(to.Slimes, {
				Id = ProfileSchema.NextSlimeId(to),
				Kind = slime.Kind,
				Mutation = slime.Mutation,
				Locked = false,
			})
			-- traded slimes fill the Index, but discovery gems only come from hatching
			to.Discovered[slime.Kind] = true
			if slime.Mutation ~= "None" then
				to.Discovered[slime.Kind .. "_" .. slime.Mutation] = true
			end
			table.insert(names, record(slime))
		end
		return names
	end
	local namesA = move(sa.Data, sb.Data, giveA)
	local namesB = move(sb.Data, sa.Data, giveB)
	logTrade(sa.Data, b, namesA, namesB)
	logTrade(sb.Data, a, namesB, namesA)

	for _, player in trade.Players do
		SlimeService.Arrange(player)
		Network.Effect(player, "TradeDone", nil)
		-- save right away so a server crash can't undo half a trade
		task.spawn(DataService.SaveAsync, player)
	end
	return nil
end

-- Requests ---------------------------------------------------------------------------
function TradeService.Request(player: Player, payload: any): (boolean, string?)
	local userId = Validate.Integer(payload, 1, 2 ^ 53)
	local target = if userId then Players:GetPlayerByUserId(userId) else nil
	if not target or target == player then
		return false, "Player not found"
	end
	local ok, why = canTrade(player)
	if not ok then
		return false, why
	end
	if not PlayerService.Get(target) or not MonetizationService.CanTrade(target) then
		return false, target.DisplayName .. " can't trade right now."
	end
	if trades[player] then
		return false, "Finish your current trade first."
	end
	if trades[target] then
		return false, target.DisplayName .. " is already trading."
	end
	local now = os.clock()
	local asked = lastAsked[player] or {}
	lastAsked[player] = asked
	if asked[target] and now - asked[target] < Config.Trading.RequestCooldown then
		return false, "Wait a moment before asking again."
	end
	asked[target] = now
	local incoming = requests[target] or {}
	requests[target] = incoming
	incoming[player] = now + Config.Trading.RequestSeconds
	Network.Notify(target, player.DisplayName .. " wants to trade!", "info")
	PlayerService.MarkDirty(target, true)
	return true, "Trade request sent to " .. target.DisplayName
end

function TradeService.Respond(player: Player, payload: any): (boolean, string?)
	if type(payload) ~= "table" then
		return false, "Bad request"
	end
	local userId = Validate.Integer(payload.From, 1, 2 ^ 53)
	local accept = Validate.Boolean(payload.Accept)
	local from = if userId then Players:GetPlayerByUserId(userId) else nil
	local incoming = requests[player]
	if not from or accept == nil or not incoming or not incoming[from] then
		return false, "That request is gone."
	end
	local expires = incoming[from]
	incoming[from] = nil
	PlayerService.MarkDirty(player, true)
	if os.clock() > expires then
		return false, "That request expired."
	end
	if not accept then
		Network.Notify(from, player.DisplayName .. " declined your trade.", "info")
		return true, nil
	end
	local ok, why = canTrade(player)
	if not ok then
		return false, why
	end
	if not PlayerService.Get(from) or not MonetizationService.CanTrade(from) then
		return false, from.DisplayName .. " can't trade right now."
	end
	if trades[player] or trades[from] then
		return false, "One of you is already trading."
	end
	nextTradeId += 1
	local trade: Trade = {
		Id = nextTradeId,
		Players = { from, player },
		Offers = { [from] = {}, [player] = {} },
		Accepted = {},
		Confirmed = {},
		Phase = "Offer",
		ConfirmAt = 0,
	}
	trades[from] = trade
	trades[player] = trade
	-- starting a trade clears other requests for both players
	requests[player] = nil
	requests[from] = nil
	markBoth(trade)
	return true, nil
end

-- Trade actions -----------------------------------------------------------------------
function TradeService.SetOffer(player: Player, payload: any): (boolean, string?)
	local trade = trades[player]
	local session = PlayerService.Get(player)
	if not trade or not session then
		return false, "You're not trading."
	end
	if trade.Phase ~= "Offer" then
		return false, "Offers are locked. Cancel to change them."
	end
	if type(payload) ~= "table" or #payload > Config.Trading.MaxItems then
		return false, "You can offer up to " .. Config.Trading.MaxItems .. " slimes."
	end
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, raw in payload do
		local id = Validate.String(raw, 16)
		if not id or seen[id] then
			return false, "Bad request"
		end
		local _, slime = SlimeInventory.Find(session.Data.Slimes, id)
		if not slime then
			return false, "You don't own that slime."
		end
		if slime.Locked then
			return false, "Unlock that slime first (🔒 in Slimes)."
		end
		seen[id] = true
		table.insert(ids, id)
	end
	trade.Offers[player] = ids
	resetAccepts(trade)
	markBoth(trade)
	return true, nil
end

function TradeService.Accept(player: Player, payload: any): (boolean, string?)
	local trade = trades[player]
	local accept = Validate.Boolean(payload)
	if not trade or accept == nil then
		return false, "You're not trading."
	end
	if trade.Phase ~= "Offer" then
		return false, nil
	end
	local partner = partnerOf(trade, player)
	if accept and #trade.Offers[player] == 0 and #trade.Offers[partner] == 0 then
		return false, "Add a slime first."
	end
	trade.Accepted[player] = accept
	if trade.Accepted[player] and trade.Accepted[partner] then
		trade.Phase = "Confirm"
		trade.ConfirmAt = os.clock() + Config.Trading.ConfirmDelay
		trade.Confirmed = {}
	end
	markBoth(trade)
	return true, nil
end

function TradeService.Confirm(player: Player, _payload: any): (boolean, string?)
	local trade = trades[player]
	if not trade or trade.Phase ~= "Confirm" then
		return false, "Both players must accept first."
	end
	if os.clock() < trade.ConfirmAt then
		return false, "Check the trade carefully first!"
	end
	trade.Confirmed[player] = true
	local partner = partnerOf(trade, player)
	if not trade.Confirmed[partner] then
		markBoth(trade)
		return true, nil
	end
	local problem = execute(trade)
	if problem then
		endTrade(trade, "Trade cancelled: " .. problem, "error")
		return false, nil
	end
	endTrade(trade, "Trade complete!", "success")
	return true, nil
end

function TradeService.Cancel(player: Player, _payload: any): (boolean, string?)
	local trade = trades[player]
	if not trade then
		return false, nil
	end
	local partner = partnerOf(trade, player)
	trades[player] = nil
	trades[partner] = nil
	if partner.Parent then
		Network.Notify(partner, player.DisplayName .. " cancelled the trade.", "info")
	end
	markBoth(trade)
	return true, "Trade cancelled."
end

-- Keeps offers honest (sold / locked slimes drop out and clear accepts) and expires requests.
function TradeService.Tick()
	local now = os.clock()
	local seen: { [Trade]: boolean } = {}
	for _, trade in trades do
		if not seen[trade] then
			seen[trade] = true
			local changed = false
			for _, player in trade.Players do
				if pruneOffer(trade, player) then
					changed = true
				end
			end
			if changed then
				resetAccepts(trade)
				markBoth(trade)
			end
		end
	end
	for target, incoming in requests do
		local any = false
		for from, expires in incoming do
			if now > expires or not from.Parent then
				incoming[from] = nil
				any = true
			end
		end
		if any then
			PlayerService.MarkDirty(target, true)
		end
	end
end

function TradeService.IsTrading(player: Player): boolean
	return trades[player] ~= nil
end

-- State sent to the client ----------------------------------------------------------------
local function slimesFor(player: Player, ids: { string }): { any }
	local session = PlayerService.Get(player)
	local list = {}
	if not session then
		return list
	end
	for _, id in ids do
		local _, slime = SlimeInventory.Find(session.Data.Slimes, id)
		if slime then
			table.insert(list, { Id = slime.Id, Kind = slime.Kind, Mutation = slime.Mutation })
		end
	end
	return list
end

local function tradeState(session: PlayerService.Session): any
	local player = session.Player
	local trade = trades[player]
	if not trade then
		return nil
	end
	local partner = partnerOf(trade, player)
	return {
		Id = trade.Id,
		Partner = partner.DisplayName,
		PartnerId = partner.UserId,
		Phase = trade.Phase,
		ConfirmIn = math.max(0, trade.ConfirmAt - os.clock()),
		Mine = slimesFor(player, trade.Offers[player]),
		Theirs = slimesFor(partner, trade.Offers[partner]),
		MeAccepted = trade.Accepted[player] == true,
		ThemAccepted = trade.Accepted[partner] == true,
		MeConfirmed = trade.Confirmed[player] == true,
		ThemConfirmed = trade.Confirmed[partner] == true,
	}
end

local function requestState(session: PlayerService.Session): any
	local list = {}
	local now = os.clock()
	local incoming: { [Player]: number } = requests[session.Player] or {}
	for from, expires in incoming do
		if now <= expires then
			table.insert(list, { UserId = from.UserId, Name = from.DisplayName, ExpiresIn = expires - now })
		end
	end
	return list
end

function TradeService.Init()
	Network.Handle("TradeRequest", TradeService.Request)
	Network.Handle("TradeRespond", TradeService.Respond)
	Network.Handle("TradeSetOffer", TradeService.SetOffer)
	Network.Handle("TradeAccept", TradeService.Accept)
	Network.Handle("TradeConfirm", TradeService.Confirm)
	Network.Handle("TradeCancel", TradeService.Cancel)
	PlayerService.RegisterState("Trade", tradeState)
	PlayerService.RegisterState("TradeRequests", requestState)
	PlayerService.RegisterState("CanTrade", function(session)
		return session.Runtime.TradingAllowed == true
	end)
	PlayerService.PlayerLeaving:Connect(function(player: Player)
		local trade = trades[player]
		if trade then
			local partner = partnerOf(trade, player)
			trades[player] = nil
			trades[partner] = nil
			if partner.Parent then
				Network.Notify(partner, player.DisplayName .. " left. Trade cancelled.", "info")
			end
			PlayerService.MarkDirty(partner, true)
		end
		requests[player] = nil
		lastAsked[player] = nil
		for _, incoming in requests do
			incoming[player] = nil
		end
		for _, asked in lastAsked do
			asked[player] = nil
		end
	end)
end

function TradeService.Start()
	task.spawn(function()
		while true do
			task.wait(0.5)
			TradeService.Tick()
		end
	end)
end

return TradeService
