--!strict
-- Player data persistence with session locking (like ProfileService):
--  * Load: UpdateAsync claims a session lock. If another live server holds it, wait and retry,
--    then take over a stale/stuck lock. A failed load never creates data that could overwrite saves.
--  * Save: UpdateAsync only writes while we still own the lock; retries with exponential backoff.
--  * Autosave every Config.Data.AutosaveSeconds, final save + lock release on leave and on shutdown.
--  * Saves for one profile are serialized so a later save always includes the latest data.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)
local ProfileSchema = require(script.Parent.Parent.Logic.ProfileSchema)

export type Profile = {
	UserId: number,
	Key: string,
	Data: ProfileSchema.Data,
	NoSave: boolean, -- temporary data (Studio without API access): never written
	SessionLost: boolean,
	Released: boolean,
	Saving: boolean,
	SaveVersion: number, -- increments every time a save is requested
	SavedVersion: number, -- last version confirmed written
	LastSaveAt: number,
}

local DataService = {}

DataService.ProfileLoaded = Signal.new()
-- Fired right before the final save of a leaving player so services can write runtime state.
DataService.BeforeRelease = Signal.new()

local store: any = nil
local profiles: { [Player]: Profile } = {}
local releasing: { [number]: Profile } = {} -- userId -> profile still being saved after leaving
local shuttingDown = false

local function now(): number
	return os.time()
end

local function keyFor(userId: number): string
	return Config.Data.KeyPrefix .. tostring(userId)
end

local function isStudioApiError(message: string): boolean
	return message:find("StudioAccessToApisNotAllowed") ~= nil
		or message:find("API Services") ~= nil
		or message:find("api services") ~= nil
		or message:find("Studio") ~= nil
end

-- Runs fn with retries and exponential backoff. Returns ok, result, lastError.
local function withRetries(fn: () -> any, maxRetries: number): (boolean, any, string?)
	local lastError: string? = nil
	for attempt = 1, maxRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result, nil
		end
		lastError = tostring(result)
		if attempt < maxRetries then
			task.wait(Config.Data.RetryBaseSeconds * 2 ^ (attempt - 1))
		end
	end
	return false, nil, lastError
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] GetDataStore failed: " .. tostring(result))
	end
end

-- Attempts to claim the session lock and read data. Returns status, data.
-- status: "ok" | "locked" | "error"
local function tryClaim(key: string, force: boolean): (string, any, string?)
	local claimed: any = nil
	local locked = false
	local ok, _, err = withRetries(function()
		locked = false
		claimed = nil
		return store:UpdateAsync(key, function(stored: any): any
			local record = if type(stored) == "table" then stored else {}
			local session = record.Session
			if
				not force
				and type(session) == "table"
				and session.JobId ~= game.JobId
				and type(session.Time) == "number"
				and now() - session.Time < Config.Data.SessionLockSeconds
			then
				locked = true
				return nil -- cancel the write: someone else owns this profile
			end
			record.Session = { JobId = game.JobId, PlaceId = game.PlaceId, Time = now() }
			claimed = record.Data
			if claimed == nil then
				claimed = ProfileSchema.Default(now())
				record.Data = claimed
			end
			return record
		end)
	end, Config.Data.MaxRetries)
	if not ok then
		return "error", nil, err
	end
	if locked then
		return "locked", nil, nil
	end
	return "ok", claimed, nil
end

local function makeProfile(userId: number, data: any, noSave: boolean): Profile
	local reconciled = ProfileSchema.Reconcile(data, now(), Config.Slimes, Config.Eggs)
	return {
		UserId = userId,
		Key = keyFor(userId),
		Data = reconciled,
		NoSave = noSave,
		SessionLost = false,
		Released = false,
		Saving = false,
		SaveVersion = 0,
		SavedVersion = 0,
		LastSaveAt = now(),
	}
end

-- Loads (and locks) the player's data. Returns nil if the player was kicked or left.
function DataService.LoadAsync(player: Player): Profile?
	local userId = player.UserId

	-- Same player rejoined this server before their last save finished: reuse that data.
	local pending = releasing[userId]
	if pending then
		local waited = 0
		while releasing[userId] and waited < 20 do
			waited += task.wait(0.5)
		end
		if releasing[userId] then
			releasing[userId] = nil
			pending.Released = false
			profiles[player] = pending
			DataService.ProfileLoaded:Fire(player, pending)
			return pending
		end
	end

	if not store then
		if RunService:IsStudio() then
			warn("[DataService] No DataStore in Studio: using temporary data (progress will NOT be saved).")
			local profile = makeProfile(userId, nil, true)
			profiles[player] = profile
			DataService.ProfileLoaded:Fire(player, profile)
			return profile
		end
		player:Kick("Could not load your data (Roblox servers busy). Please rejoin in a minute!")
		return nil
	end

	local key = keyFor(userId)
	local status, data, err = "locked", nil, nil
	for attempt = 1, Config.Data.LockWaitAttempts + 1 do
		local force = attempt > Config.Data.LockWaitAttempts
		status, data, err = tryClaim(key, force)
		if status ~= "locked" then
			break
		end
		if player.Parent == nil then
			return nil
		end
		task.wait(Config.Data.LockWaitSeconds)
	end

	if player.Parent == nil then
		-- Left while loading: release the lock we may have just taken.
		if status == "ok" then
			task.spawn(function()
				pcall(function()
					store:UpdateAsync(key, function(stored: any): any
						if type(stored) == "table" and type(stored.Session) == "table" and stored.Session.JobId == game.JobId then
							stored.Session = nil
							return stored
						end
						return nil
					end)
				end)
			end)
		end
		return nil
	end

	if status ~= "ok" then
		local message = tostring(err)
		if RunService:IsStudio() then
			if isStudioApiError(message) then
				warn("[DataService] Studio API access is off: using temporary data (progress will NOT be saved).")
			else
				warn("[DataService] Load failed in Studio, using temporary data: " .. message)
			end
			local profile = makeProfile(userId, nil, true)
			profiles[player] = profile
			DataService.ProfileLoaded:Fire(player, profile)
			return profile
		end
		warn("[DataService] Load failed for " .. userId .. ": " .. message)
		player:Kick("Could not load your data (Roblox servers busy). Your progress is safe - please rejoin!")
		return nil
	end

	local profile = makeProfile(userId, data, false)
	profiles[player] = profile
	DataService.ProfileLoaded:Fire(player, profile)
	return profile
end

-- Writes the profile once (with retries). Returns true when the write is confirmed.
local function writeOnce(profile: Profile, release: boolean, maxRetries: number): boolean
	if profile.NoSave then
		return true
	end
	if profile.SessionLost or not store then
		return false
	end
	local lost = false
	local ok, _, err = withRetries(function()
		lost = false
		return store:UpdateAsync(profile.Key, function(stored: any): any
			if type(stored) == "table" and type(stored.Session) == "table" and stored.Session.JobId ~= game.JobId then
				lost = true
				return nil
			end
			profile.Data.LastSeen = now()
			return {
				Data = profile.Data,
				Session = if release then nil else { JobId = game.JobId, PlaceId = game.PlaceId, Time = now() },
				SavedAt = now(),
			}
		end)
	end, maxRetries)
	if lost then
		profile.SessionLost = true
		warn("[DataService] Session lost for " .. profile.UserId .. " (data opened on another server)")
		local player = Players:GetPlayerByUserId(profile.UserId)
		if player then
			player:Kick("Your data was opened on another server. Please rejoin.")
		end
		return false
	end
	if not ok then
		warn("[DataService] Save failed for " .. profile.UserId .. ": " .. tostring(err))
		return false
	end
	profile.LastSaveAt = now()
	return true
end

-- Saves the profile including every change made before this call.
-- Concurrent calls are serialized; returns true when this call's data is confirmed written.
function DataService.SaveProfileAsync(profile: Profile, release: boolean?, maxRetries: number?): boolean
	profile.SaveVersion += 1
	local myVersion = profile.SaveVersion
	while profile.Saving do
		task.wait(0.1)
	end
	if profile.SavedVersion >= myVersion and not release then
		return true -- a save that started after our request already covered our data
	end
	profile.Saving = true
	local versionAtStart = profile.SaveVersion
	local ok = writeOnce(profile, release == true, maxRetries or Config.Data.MaxRetries)
	if ok then
		profile.SavedVersion = math.max(profile.SavedVersion, versionAtStart)
	end
	profile.Saving = false
	return ok
end

function DataService.SaveAsync(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	return DataService.SaveProfileAsync(profile)
end

function DataService.Get(player: Player): Profile?
	return profiles[player]
end

function DataService.GetData(player: Player): ProfileSchema.Data?
	local profile = profiles[player]
	return profile and profile.Data
end

function DataService.WaitFor(player: Player, timeout: number?): Profile?
	local waited = 0
	local limit = timeout or 15
	while not profiles[player] and waited < limit and player.Parent ~= nil do
		waited += task.wait(0.2)
	end
	return profiles[player]
end

-- Final save + release the session lock. Keeps retrying in the background on failure.
function DataService.ReleaseAsync(player: Player)
	local profile = profiles[player]
	if not profile or profile.Released then
		return
	end
	profile.Released = true
	DataService.BeforeRelease:Fire(player, profile)
	profiles[player] = nil
	if profile.NoSave or profile.SessionLost then
		return
	end
	releasing[profile.UserId] = profile
	local attempts = 0
	while true do
		attempts += 1
		local retries = if shuttingDown then 2 else Config.Data.MaxRetries
		if DataService.SaveProfileAsync(profile, true, retries) then
			break
		end
		if profile.SessionLost or (shuttingDown and attempts >= 2) then
			break
		end
		task.wait(math.min(30, 5 * attempts))
	end
	if releasing[profile.UserId] == profile then
		releasing[profile.UserId] = nil
	end
end

function DataService.AllProfiles(): { [Player]: Profile }
	return profiles
end

function DataService.Start()
	-- Autosave loop
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveSeconds)
			for player, profile in profiles do
				if not profile.Released and not profile.NoSave then
					task.spawn(DataService.SaveProfileAsync, profile)
				end
				local _ = player
			end
		end
	end)

	game:BindToClose(function()
		shuttingDown = true
		local remaining = 0
		local function finish()
			remaining -= 1
		end
		local alreadyReleasing = table.clone(releasing)
		local active = {}
		for player in profiles do
			table.insert(active, player)
		end
		for _, player in active do
			remaining += 1
			task.spawn(function()
				DataService.ReleaseAsync(player)
				finish()
			end)
		end
		for _, profile in alreadyReleasing do
			remaining += 1
			task.spawn(function()
				DataService.SaveProfileAsync(profile, true, 2)
				finish()
			end)
		end
		local waited = 0
		while remaining > 0 and waited < 25 do
			waited += task.wait(0.2)
		end
	end)
end

return DataService
