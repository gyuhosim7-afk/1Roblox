-- Mock Roblox services for tests. Data stores serialize through JSON so storing a
-- non-JSON value (Vector3, Instance, function, mixed tables) fails like it would on Roblox.

local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local MockServices = {}

local function deepCopyJson(value)
	if value == nil then
		return nil
	end
	local ok, encoded = pcall(serde.encode, "json", value)
	if not ok then
		error("DataStore: value is not JSON serializable: " .. tostring(encoded))
	end
	return serde.decode("json", encoded)
end
MockServices.deepCopyJson = deepCopyJson

-- Shared backend so several "servers" (worlds) can see the same saved data.
function MockServices.newDataBackend()
	return {
		stores = {}, -- [storeName] = { [key] = value }
		failNext = 0, -- number of upcoming calls that throw
		failAll = false,
		calls = 0,
	}
end

function MockServices.install(world)
	local lib = world.InstanceLib
	local game = world.game
	local scheduler = world.scheduler
	local services = {}

	local function service(className: string, name: string?)
		local inst = lib.new(className)
		inst.Name = name or className
		inst.Parent = game
		services[className] = inst
		return inst
	end

	-- Workspace ---------------------------------------------------------------
	local workspace = service("Workspace")
	lib.classMethods.Workspace = {
		GetServerTimeNow = function()
			return scheduler:Time()
		end,
		Raycast = function()
			return nil
		end,
		GetPartBoundsInBox = function()
			return {}
		end,
		GetPartBoundsInRadius = function()
			return {}
		end,
	}
	workspace.Gravity = 196.2
	local camera = lib.new("Camera")
	camera.Name = "Camera"
	camera.CFrame = roblox.CFrame.new(0, 20, -150)
	camera.ViewportSize = roblox.Vector2.new(1280, 720)
	camera.Parent = workspace
	workspace.CurrentCamera = camera

	for _, className in
		{
			"ReplicatedStorage",
			"ServerScriptService",
			"ServerStorage",
			"StarterPlayer",
			"StarterGui",
			"StarterPack",
			"Lighting",
			"SoundService",
			"Teams",
			"Chat",
			"TextChatService",
			"ProximityPromptService",
			"LocalizationService",
			"BadgeService",
			"GuiService",
			"UserInputService",
			"ContextActionService",
			"SocialService",
			"AnalyticsService",
		}
	do
		service(className)
	end
	lib.classMethods.SoundService = {
		PlayLocalSound = function(_, sound)
			lib.recordCall(sound, "PlayLocalSound")
		end,
	}
	local starterPlayer = services.StarterPlayer
	local sps = lib.new("Folder")
	sps.Name = "StarterPlayerScripts"
	sps.Parent = starterPlayer

	-- RunService --------------------------------------------------------------
	local runService = service("RunService")
	world.isStudio = world.isStudio or false
	lib.classMethods.RunService = {
		IsStudio = function()
			return world.isStudio
		end,
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		IsRunning = function()
			return true
		end,
		IsRunMode = function()
			return false
		end,
	}
	scheduler.onStep = function(dt)
		lib.getSignal(runService, "Stepped"):Fire(scheduler.now, dt)
		lib.getSignal(runService, "Heartbeat"):Fire(dt)
		if world.clientPlayer then
			lib.getSignal(runService, "RenderStepped"):Fire(dt)
		end
	end

	-- Players -----------------------------------------------------------------
	local players = service("Players")
	players.MaxPlayers = 8
	players.CharacterAutoLoads = true
	lib.classMethods.Players = {
		GetPlayers = function(self)
			local list = {}
			for _, child in self:GetChildren() do
				if child:IsA("Player") then
					table.insert(list, child)
				end
			end
			return list
		end,
		GetPlayerByUserId = function(self, userId)
			for _, child in self:GetChildren() do
				if child:IsA("Player") and child.UserId == userId then
					return child
				end
			end
			return nil
		end,
		GetPlayerFromCharacter = function(self, character)
			for _, child in self:GetChildren() do
				if child:IsA("Player") and child.Character == character then
					return child
				end
			end
			return nil
		end,
		GetUserIdFromNameAsync = function()
			return 1
		end,
	}

	local function buildCharacter(player, position)
		local character = lib.new("Model")
		character.Name = player.Name
		local root = lib.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = roblox.Vector3.new(2, 2, 1)
		root.CFrame = roblox.CFrame.new(position or roblox.Vector3.new(0, 3, 0))
		root.Parent = character
		local head = lib.new("Part")
		head.Name = "Head"
		head.Parent = character
		local humanoid = lib.new("Humanoid")
		humanoid.Name = "Humanoid"
		humanoid.Parent = character
		character.PrimaryPart = root
		return character
	end

	lib.classMethods.Player = {
		Kick = function(self, message)
			lib.recordCall(self, "Kick", message)
			self:SetAttribute("__Kicked", tostring(message))
		end,
		LoadCharacter = function(self)
			local old = self.Character
			if old then
				lib.getSignal(self, "CharacterRemoving"):Fire(old)
				old:Destroy()
			end
			local character = buildCharacter(self)
			character.Parent = workspace
			self.Character = character
			lib.getSignal(self, "CharacterAdded"):Fire(character)
			return character
		end,
		GetRankInGroup = function()
			return 0
		end,
		IsFriendsWith = function()
			return false
		end,
		GetJoinData = function()
			return {}
		end,
		HasAppearanceLoaded = function()
			return true
		end,
		GetNetworkPing = function()
			return 0.05
		end,
	}

	function world.AddPlayer(userId: number, name: string?, opts: any?)
		local player = lib.new("Player")
		player.Name = name or ("Player" .. userId)
		player.DisplayName = player.Name
		player.UserId = userId
		local playerGui = lib.new("Folder")
		playerGui.Name = "PlayerGui"
		playerGui.Parent = player
		local backpack = lib.new("Folder")
		backpack.Name = "Backpack"
		backpack.Parent = player
		player.Parent = players
		lib.getSignal(players, "PlayerAdded"):Fire(player)
		if not (opts and opts.noCharacter) then
			player:LoadCharacter()
		end
		return player
	end

	function world.RemovePlayer(player)
		lib.getSignal(players, "PlayerRemoving"):Fire(player)
		if player.Character then
			player.Character:Destroy()
		end
		player.Parent = nil
	end

	-- CollectionService -------------------------------------------------------
	local collection = service("CollectionService")
	local tagged = {} -- [tag] = { [inst] = true }
	local addedSignals, removedSignals = {}, {}
	lib.onTagChanged = function(inst, tag, added)
		tagged[tag] = tagged[tag] or {}
		if added then
			tagged[tag][inst] = true
			if addedSignals[tag] then
				addedSignals[tag]:Fire(inst)
			end
		else
			tagged[tag][inst] = nil
			if removedSignals[tag] then
				removedSignals[tag]:Fire(inst)
			end
		end
	end
	lib.classMethods.CollectionService = {
		AddTag = function(_, inst, tag)
			inst:AddTag(tag)
		end,
		RemoveTag = function(_, inst, tag)
			inst:RemoveTag(tag)
		end,
		HasTag = function(_, inst, tag)
			return inst:HasTag(tag)
		end,
		GetTagged = function(_, tag)
			local list = {}
			for inst in tagged[tag] or {} do
				table.insert(list, inst)
			end
			return list
		end,
		GetInstanceAddedSignal = function(_, tag)
			addedSignals[tag] = addedSignals[tag] or lib.Signal()
			return addedSignals[tag]
		end,
		GetInstanceRemovedSignal = function(_, tag)
			removedSignals[tag] = removedSignals[tag] or lib.Signal()
			return removedSignals[tag]
		end,
		GetTags = function(_, inst)
			return inst:GetTags()
		end,
	}

	-- DataStoreService -----------------------------------------------------
	local dss = service("DataStoreService")
	local backend = world.dataBackend
	local function maybeFail(op)
		backend.calls += 1
		if backend.failAll then
			error("DataStore " .. op .. " failed (mock outage)")
		end
		if backend.failNext > 0 then
			backend.failNext -= 1
			error("DataStore " .. op .. " failed (mock)")
		end
	end
	local function getStore(name, scope)
		local fullName = name .. "/" .. (scope or "global")
		backend.stores[fullName] = backend.stores[fullName] or {}
		local storeData = backend.stores[fullName]
		local store = {}
		function store:GetAsync(key)
			maybeFail("GetAsync")
			return deepCopyJson(storeData[key])
		end
		function store:SetAsync(key, value)
			maybeFail("SetAsync")
			storeData[key] = deepCopyJson(value)
		end
		function store:UpdateAsync(key, transform)
			maybeFail("UpdateAsync")
			local old = deepCopyJson(storeData[key])
			local new = transform(old, nil)
			if new == nil then
				return nil
			end
			storeData[key] = deepCopyJson(new)
			return deepCopyJson(storeData[key])
		end
		function store:RemoveAsync(key)
			maybeFail("RemoveAsync")
			local old = storeData[key]
			storeData[key] = nil
			return old
		end
		function store:IncrementAsync(key, delta)
			maybeFail("IncrementAsync")
			storeData[key] = (storeData[key] or 0) + (delta or 1)
			return storeData[key]
		end
		function store:GetSortedAsync()
			return {
				GetCurrentPage = function()
					return {}
				end,
				IsFinished = true,
			}
		end
		return store
	end
	lib.classMethods.DataStoreService = {
		GetDataStore = function(_, name, scope)
			return getStore(name, scope)
		end,
		GetOrderedDataStore = function(_, name, scope)
			return getStore("ordered:" .. name, scope)
		end,
		GetRequestBudgetForRequestType = function()
			return 100
		end,
	}

	-- MarketplaceService ------------------------------------------------------
	local mps = service("MarketplaceService")
	world.ownedPasses = world.ownedPasses or {} -- [userId] = { [passId] = true }
	world.prompts = {}
	lib.classMethods.MarketplaceService = {
		UserOwnsGamePassAsync = function(_, userId, passId)
			if world.passCheckFails then
				error("UserOwnsGamePassAsync failed (mock)")
			end
			local owned = world.ownedPasses[userId]
			return owned ~= nil and owned[passId] == true
		end,
		PromptProductPurchase = function(_, player, productId)
			table.insert(world.prompts, { kind = "product", player = player, id = productId })
		end,
		PromptGamePassPurchase = function(_, player, passId)
			table.insert(world.prompts, { kind = "pass", player = player, id = passId })
		end,
		GetProductInfo = function(_, id)
			return { PriceInRobux = 0, Name = tostring(id) }
		end,
	}

	-- PolicyService -----------------------------------------------------------
	local policyService = service("PolicyService")
	world.policies = world.policies or {} -- [userId] = table or "error"
	lib.classMethods.PolicyService = {
		GetPolicyInfoForPlayerAsync = function(_, player)
			local policy = world.policies[player.UserId]
			if policy == "error" then
				error("PolicyService failed (mock)")
			end
			return policy
				or {
					ArePaidRandomItemsRestricted = false,
					IsPaidItemTradingAllowed = true,
					AllowedExternalLinkReferences = {},
					IsSubjectToChinaPolicies = false,
				}
		end,
	}
	local _ = policyService

	-- TweenService ------------------------------------------------------------
	local tweenService = service("TweenService")
	lib.classMethods.TweenService = {
		Create = function(_, inst, _info, goals)
			local completed = lib.Signal()
			return {
				Play = function()
					for key, value in goals do
						inst[key] = value
					end
					world.task.defer(function()
						completed:Fire(roblox.Enum.PlaybackState.Completed)
					end)
				end,
				Cancel = function() end,
				Pause = function() end,
				Destroy = function() end,
				Completed = completed,
			}
		end,
		GetValue = function(_, alpha)
			return alpha
		end,
	}
	local _ = tweenService

	-- HttpService -------------------------------------------------------------
	local http = service("HttpService")
	local guidCounter = 0
	lib.classMethods.HttpService = {
		GenerateGUID = function(_, wrap)
			guidCounter += 1
			local text = string.format("00000000-0000-4000-8000-%012d", guidCounter)
			return if wrap == false then text else "{" .. text .. "}"
		end,
		JSONEncode = function(_, value)
			return serde.encode("json", value)
		end,
		JSONDecode = function(_, text)
			return serde.decode("json", text)
		end,
	}
	local _ = http

	-- Debris ------------------------------------------------------------------
	local debris = service("Debris")
	lib.classMethods.Debris = {
		AddItem = function(_, inst, lifetime)
			world.task.delay(lifetime or 10, function()
				if inst.Parent then
					inst:Destroy()
				end
			end)
		end,
	}
	local _ = debris

	-- PhysicsService --------------------------------------------------------
	local physics = service("PhysicsService")
	lib.classMethods.PhysicsService = {
		RegisterCollisionGroup = function() end,
		CollisionGroupSetCollidable = function() end,
		IsCollisionGroupRegistered = function()
			return true
		end,
	}
	local _ = physics

	-- MessagingService --------------------------------------------------------
	local messaging = service("MessagingService")
	lib.classMethods.MessagingService = {
		SubscribeAsync = function()
			return { Disconnect = function() end }
		end,
		PublishAsync = function() end,
	}
	local _ = messaging

	-- DataModel ---------------------------------------------------------------
	world.closeCallbacks = {}
	lib.classMethods.DataModel = {
		GetService = function(_, name)
			local found = services[name]
			if not found then
				error("Mock GetService: unknown service " .. tostring(name))
			end
			return found
		end,
		BindToClose = function(_, fn)
			table.insert(world.closeCallbacks, fn)
		end,
		IsLoaded = function()
			return true
		end,
	}
	game.JobId = world.jobId or "job-test"
	game.PlaceId = 1
	game.GameId = 1
	game.CreatorId = 1
	game.PrivateServerId = ""

	world.services = services
	return services
end

return MockServices
