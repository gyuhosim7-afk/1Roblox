--!strict
-- Holds the latest state sent by the server and sends requests. The client never decides
-- outcomes: it only displays state and asks the server to do things.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local StateController = {}

StateController.State = nil :: any
StateController.Changed = Signal.new() -- full state arrived
StateController.StatsChanged = Signal.new() -- small stats update arrived
StateController.Notify = Signal.new() -- (text, kind)
StateController.Effect = Signal.new() -- (name, payload)

local requestRemote: RemoteFunction? = nil

function StateController.Data(): any
	local state = StateController.State
	return state and state.Data or nil
end

function StateController.Now(): number
	return Workspace:GetServerTimeNow()
end

-- Sends a request; shows the server's message as a toast. Returns the result table.
function StateController.Request(action: string, payload: any?): any
	local remote = requestRemote
	if not remote then
		return { ok = false }
	end
	local ok, result = pcall(function()
		return remote:InvokeServer(action, payload)
	end)
	if not ok or type(result) ~= "table" then
		StateController.Notify:Fire("Connection problem, try again", "error")
		return { ok = false }
	end
	if result.msg then
		StateController.Notify:Fire(result.msg, if result.ok then "success" else "error")
	end
	return result
end

function StateController.Init()
	requestRemote = Remotes.GetFunction("Request")
	Remotes.GetEvent("State").OnClientEvent:Connect(function(state: any)
		StateController.State = state
		StateController.Changed:Fire(state)
		StateController.StatsChanged:Fire(state)
	end)
	Remotes.GetEvent("Stats").OnClientEvent:Connect(function(stats: any)
		local state = StateController.State
		if not state then
			return
		end
		for key, value in stats do
			if state.Data[key] ~= nil and key ~= "ServerTime" then
				state.Data[key] = value
			end
		end
		StateController.StatsChanged:Fire(state)
	end)
	Remotes.GetEvent("Notify").OnClientEvent:Connect(function(text: string, kind: string?)
		StateController.Notify:Fire(text, kind or "info")
	end)
	Remotes.GetEvent("Effect").OnClientEvent:Connect(function(name: string, payload: any)
		StateController.Effect:Fire(name, payload)
	end)
end

function StateController.Start() end

return StateController
