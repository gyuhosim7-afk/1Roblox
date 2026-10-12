--!strict
-- All client <-> server traffic. Clients can only *ask*; every handler validates on the server.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.Logic.RateLimiter)

export type Result = { ok: boolean, msg: string?, data: any? }
export type Handler = (player: Player, payload: any) -> (boolean, string?, any?)

local Network = {}

local handlers: { [string]: Handler } = {}
local limiter = RateLimiter.new(Config.Network.RequestBurst, Config.Network.RequestsPerSecond)
local folder: Folder? = nil

-- Set by PlayerService: returns true once the player's data is loaded.
Network.IsReady = function(_player: Player): boolean
	return false
end

function Network.Handle(action: string, handler: Handler)
	assert(handlers[action] == nil, "Duplicate handler " .. action)
	handlers[action] = handler
end

local function event(name: string): RemoteEvent
	assert(folder, "Network not initialised")
	return folder:FindFirstChild(name) :: RemoteEvent
end

function Network.Init()
	folder = Remotes.Create()
	assert(folder, "remotes folder missing")
	local request = folder:FindFirstChild("Request") :: RemoteFunction
	request.OnServerInvoke = function(player: Player, action: any, payload: any): Result
		if type(action) ~= "string" or #action > 40 then
			return { ok = false, msg = "Bad request" }
		end
		if not limiter:Allow(player, os.clock()) then
			return { ok = false, msg = "Slow down!" }
		end
		if not Network.IsReady(player) then
			return { ok = false, msg = "Loading..." }
		end
		local handler = handlers[action]
		if not handler then
			return { ok = false, msg = "Unknown action" }
		end
		local success, ok, msg, data = pcall(handler, player, payload)
		if not success then
			warn("[Network] " .. action .. " failed for " .. player.Name .. ": " .. tostring(ok))
			return { ok = false, msg = "Something went wrong" }
		end
		return { ok = ok == true, msg = msg, data = data }
	end
	Players.PlayerRemoving:Connect(function(player)
		limiter:Remove(player)
	end)
end

function Network.Start() end

-- kind: "info" | "success" | "error" | "rare" | "warning"
function Network.Notify(player: Player, text: string, kind: string?)
	event("Notify"):FireClient(player, text, kind or "info")
end

function Network.NotifyAll(text: string, kind: string?)
	event("Notify"):FireAllClients(text, kind or "info")
end

function Network.Effect(player: Player, name: string, payload: any?)
	event("Effect"):FireClient(player, name, payload)
end

function Network.EffectAll(name: string, payload: any?)
	event("Effect"):FireAllClients(name, payload)
end

function Network.SendState(player: Player, state: any)
	event("State"):FireClient(player, state)
end

function Network.SendStats(player: Player, stats: any)
	event("Stats"):FireClient(player, stats)
end

-- Test helper: invoke a handler as if the client asked.
function Network.Invoke(player: Player, action: string, payload: any?): Result
	assert(folder, "remotes folder missing")
	local request = folder:FindFirstChild("Request") :: RemoteFunction
	local invoke = (request :: any).OnServerInvoke
	return invoke(player, action, payload)
end

return Network
