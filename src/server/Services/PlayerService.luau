--!strict
-- Player lifecycle: load data -> ready -> playing -> leaving -> save.
-- Holds a session per player and syncs state to the client (throttled).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)
local DataService = require(script.Parent.DataService)
local Network = require(script.Parent.Network)
local ProfileSchema = require(script.Parent.Parent.Logic.ProfileSchema)

export type Session = {
	Player: Player,
	Profile: DataService.Profile,
	Data: ProfileSchema.Data,
	Ready: boolean,
	JoinedAt: number, -- os.clock()
	FullDirty: boolean,
	StatsDirty: boolean,
	Runtime: { [string]: any }, -- per-service scratch space
}

local PlayerService = {}

PlayerService.PlayerReady = Signal.new() -- (player, session)
PlayerService.PlayerLeaving = Signal.new() -- (player, session) handlers must not yield

local sessions: { [Player]: Session } = {}
local stateProviders: { [string]: (Session) -> any } = {}
local statsProviders: { [string]: (Session) -> any } = {}

function PlayerService.Get(player: Player): Session?
	local session = sessions[player]
	if session and session.Ready then
		return session
	end
	return nil
end

function PlayerService.All(): { Session }
	local list = {}
	for _, session in sessions do
		if session.Ready then
			table.insert(list, session)
		end
	end
	return list
end

-- full = true when anything other than the small stats changed.
function PlayerService.MarkDirty(player: Player, full: boolean?)
	local session = sessions[player]
	if not session then
		return
	end
	if full then
		session.FullDirty = true
	else
		session.StatsDirty = true
	end
end

-- Adds a field to the full state snapshot sent to the client.
function PlayerService.RegisterState(name: string, provider: (Session) -> any)
	stateProviders[name] = provider
end

-- Adds a field to the small, frequent stats update.
function PlayerService.RegisterStats(name: string, provider: (Session) -> any)
	statsProviders[name] = provider
end

local HIDDEN_DATA_KEYS = { Purchases = true, PurchaseOrder = true, PassCache = true }

function PlayerService.BuildState(session: Session): any
	local data = {}
	for key, value in session.Data :: any do
		if not HIDDEN_DATA_KEYS[key] then
			data[key] = value
		end
	end
	local state = { Data = data, ServerTime = os.time() }
	for name, provider in stateProviders do
		(state :: any)[name] = provider(session)
	end
	return state
end

function PlayerService.BuildStats(session: Session): any
	local d = session.Data
	local stats = { Speed = d.Speed, Coins = d.Coins, Gems = d.Gems, Bank = d.Bank, ServerTime = os.time() }
	for name, provider in statsProviders do
		(stats :: any)[name] = provider(session)
	end
	return stats
end

local function updateLeaderstats(session: Session)
	local leaderstats = session.Player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local speed = leaderstats:FindFirstChild("Speed") :: IntValue?
	local rebirths = leaderstats:FindFirstChild("Rebirths") :: IntValue?
	if speed then
		speed.Value = math.floor(session.Data.Speed)
	end
	if rebirths then
		rebirths.Value = session.Data.Rebirths
	end
end

local function createLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local speed = Instance.new("IntValue")
	speed.Name = "Speed"
	speed.Parent = folder
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = folder
	folder.Parent = player
end

local function onPlayerAdded(player: Player)
	local profile = DataService.LoadAsync(player)
	if not profile or player.Parent == nil then
		return
	end
	local session: Session = {
		Player = player,
		Profile = profile,
		Data = profile.Data,
		Ready = false,
		JoinedAt = os.clock(),
		FullDirty = true,
		StatsDirty = true,
		Runtime = {},
	}
	sessions[player] = session
	profile.Data.Stats.Joins += 1
	createLeaderstats(player)
	session.Ready = true
	PlayerService.PlayerReady:Fire(player, session)
	updateLeaderstats(session)
	Network.SendState(player, PlayerService.BuildState(session))
	session.FullDirty = false
	session.StatsDirty = false
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if session then
		if session.Ready then
			PlayerService.PlayerLeaving:Fire(player, session)
		end
		sessions[player] = nil
	end
	DataService.ReleaseAsync(player)
end

function PlayerService.Init()
	Network.IsReady = function(player: Player): boolean
		return PlayerService.Get(player) ~= nil
	end
end

function PlayerService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Throttled state sync
	task.spawn(function()
		while true do
			task.wait(Config.Network.SyncInterval)
			for player, session in sessions do
				if session.Ready and player.Parent ~= nil then
					if session.FullDirty then
						session.FullDirty = false
						session.StatsDirty = false
						Network.SendState(player, PlayerService.BuildState(session))
						updateLeaderstats(session)
					elseif session.StatsDirty then
						session.StatsDirty = false
						Network.SendStats(player, PlayerService.BuildStats(session))
						updateLeaderstats(session)
					end
				end
			end
		end
	end)
end

return PlayerService
