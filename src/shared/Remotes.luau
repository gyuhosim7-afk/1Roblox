--!strict
-- Remote names. The server creates them; clients wait for them.
--   Request (RemoteFunction)  client -> server: Request:InvokeServer(action, payload) -> { ok, message?, data? }
--   State   (RemoteEvent)     server -> client: full player state snapshot
--   Stats   (RemoteEvent)     server -> client: small frequent stat update
--   Notify  (RemoteEvent)     server -> client: toast message (text, kind)
--   Effect  (RemoteEvent)     server -> client: visual / physics effects (knockback, hatch reveal, bonk swing)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

Remotes.FolderName = "Remotes"
Remotes.Functions = { "Request" }
Remotes.Events = { "State", "Stats", "Notify", "Effect" }

function Remotes.Create(): Folder
	local folder = ReplicatedStorage:FindFirstChild(Remotes.FolderName) :: Folder?
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = Remotes.FolderName
		newFolder.Parent = ReplicatedStorage
		folder = newFolder
	end
	assert(folder, "remotes folder")
	for _, name in Remotes.Functions do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in Remotes.Events do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	return folder
end

function Remotes.GetEvent(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild(Remotes.FolderName)
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.GetFunction(name: string): RemoteFunction
	local folder = ReplicatedStorage:WaitForChild(Remotes.FolderName)
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
