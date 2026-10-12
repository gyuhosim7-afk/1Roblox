-- Builds a fake Roblox DataModel from default.project.json and runs game code inside it.
-- Usage:
--   local world = World.new({ isStudio = false })
--   local Config = world:Require("ReplicatedStorage/Shared/Config")
--   world:StartServer()          -- runs ServerScriptService scripts
--   world.AddPlayer(1, "Alice")
--   world:Advance(5)              -- move virtual time forward

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Scheduler = require("./Scheduler")
local MockInstance = require("./MockInstance")
local MockServices = require("./MockServices")

local World = {}
World.__index = World

local ROOT = "."

local function readProject()
	local text = fs.readFile(ROOT .. "/default.project.json")
	return serde.decode("json", text)
end

-- Deterministic stand-in for Roblox's Random class.
local function makeRandomClass()
	local Random = {}
	Random.__index = Random
	function Random.new(seed: number?)
		local self = setmetatable({}, Random)
		self.state = math.floor(seed or 12345) % 2147483647
		if self.state <= 0 then
			self.state += 2147483646
		end
		return self
	end
	function Random:_next()
		self.state = (self.state * 48271) % 2147483647
		return self.state / 2147483647
	end
	function Random:NextNumber(min: number?, max: number?)
		local r = self:_next()
		if min and max then
			return min + (max - min) * r
		end
		return r
	end
	function Random:NextInteger(min: number, max: number)
		return min + math.floor(self:_next() * (max - min + 1))
	end
	function Random:Shuffle(list)
		for i = #list, 2, -1 do
			local j = self:NextInteger(1, i)
			list[i], list[j] = list[j], list[i]
		end
	end
	function Random:Clone()
		local copy = Random.new(1)
		copy.state = self.state
		return copy
	end
	return Random
end

function World.new(opts: any?)
	opts = opts or {}
	local self = setmetatable({}, World)
	self.scheduler = Scheduler.new()
	self.task = self.scheduler:TaskLibrary()
	self.InstanceLib = MockInstance.newLibrary(self.scheduler)
	self.dataBackend = opts.dataBackend or MockServices.newDataBackend()
	self.isStudio = opts.isStudio or false
	self.jobId = opts.jobId or "job-test"
	self.ownedPasses = opts.ownedPasses or {}
	self.policies = opts.policies or {}
	self.logs = {}
	self.warnings = {}
	self.quiet = if opts.quiet == nil then true else opts.quiet
	self.moduleCache = {}
	self.loading = {}

	local game = self.InstanceLib.new("DataModel")
	game.Name = "Game"
	self.game = game
	MockServices.install(self)
	self.workspace = self.services.Workspace
	self.Random = makeRandomClass()
	self:_mount(readProject().tree, game)
	return self
end

-- Mount the Rojo tree into the mock DataModel -----------------------------------
local function scriptKind(fileName: string): (string?, string?)
	local base = fileName:match("^(.*)%.luau$") or fileName:match("^(.*)%.lua$")
	if not base then
		return nil, nil
	end
	local serverName = base:match("^(.*)%.server$")
	if serverName then
		return "Script", serverName
	end
	local clientName = base:match("^(.*)%.client$")
	if clientName then
		return "LocalScript", clientName
	end
	return "ModuleScript", base
end

function World:_mountPath(path: string, parent: any, nameOverride: string?)
	local lib = self.InstanceLib
	if fs.isDir(path) then
		local initFile = nil
		for _, candidate in { "init.luau", "init.server.luau", "init.client.luau", "init.lua" } do
			if fs.isFile(path .. "/" .. candidate) then
				initFile = candidate
			end
		end
		local container
		if initFile then
			local kind = scriptKind(initFile)
			container = lib.new(kind :: string)
			rawget(container, "__data").sourcePath = path .. "/" .. initFile
			rawget(container, "__data").source = fs.readFile(path .. "/" .. initFile)
		else
			container = lib.new("Folder")
		end
		container.Name = nameOverride or path:match("([^/]+)$")
		container.Parent = parent
		local entries = fs.readDir(path)
		table.sort(entries)
		for _, entry in entries do
			if not entry:match("^init%.") then
				self:_mountPath(path .. "/" .. entry, container)
			end
		end
		return container
	elseif fs.isFile(path) then
		local fileName = path:match("([^/]+)$")
		local kind, name = scriptKind(fileName)
		if not kind then
			return nil
		end
		local inst = lib.new(kind)
		inst.Name = nameOverride or name
		rawget(inst, "__data").sourcePath = path
		-- Read now: Lune's fs is async and would yield inside game coroutines.
		rawget(inst, "__data").source = fs.readFile(path)
		inst.Parent = parent
		return inst
	end
	return nil
end

function World:_mount(node: any, inst: any)
	for key, child in node do
		if key:sub(1, 1) ~= "$" then
			local target
			if child["$path"] then
				target = self:_mountPath(ROOT .. "/" .. child["$path"], inst, key)
			else
				target = inst:FindFirstChild(key)
				if not target then
					target = self.InstanceLib.new(child["$className"] or "Folder")
					target.Name = key
					target.Parent = inst
				end
			end
			if target then
				self:_mount(child, target)
			end
		end
	end
end

-- Module loading -------------------------------------------------------------
function World:_env(scriptInstance: any)
	local world = self
	local lib = self.InstanceLib
	local function mockTypeof(value)
		if lib.isInstance(value) then
			return "Instance"
		end
		if type(value) == "table" and getmetatable(value) == world.Random then
			return "Random"
		end
		return typeof(value)
	end
	local env = {
		game = self.game,
		workspace = self.workspace,
		Workspace = self.workspace,
		script = scriptInstance,
		task = self.task,
		Random = self.Random,
		typeof = mockTypeof,
		Instance = {
			new = function(className, parent)
				return lib.new(className, parent)
			end,
		},
		tick = function()
			return world.scheduler:Time()
		end,
		time = function()
			return world.scheduler.now
		end,
		wait = function(t)
			return world.task.wait(t)
		end,
		delay = function(t, fn)
			return world.task.delay(t, fn)
		end,
		spawn = function(fn)
			return world.task.defer(fn)
		end,
		print = function(...)
			local parts = table.pack(...)
			for i = 1, parts.n do
				parts[i] = tostring(parts[i])
			end
			local line = table.concat(parts, " ")
			table.insert(world.logs, line)
			if not world.quiet then
				print("[game]", line)
			end
		end,
		warn = function(...)
			local parts = table.pack(...)
			for i = 1, parts.n do
				parts[i] = tostring(parts[i])
			end
			local line = table.concat(parts, " ")
			table.insert(world.warnings, line)
			if not world.quiet then
				print("[warn]", line)
			end
		end,
		os = setmetatable({
			time = function(t)
				if t then
					return os.time(t)
				end
				return math.floor(world.scheduler:Time())
			end,
			clock = function()
				return world.scheduler.now
			end,
		}, { __index = os }),
		DateTime = {
			now = function()
				local t = world.scheduler:Time()
				return { UnixTimestamp = math.floor(t), UnixTimestampMillis = math.floor(t * 1000) }
			end,
			fromUnixTimestamp = function(t)
				return { UnixTimestamp = t, UnixTimestampMillis = t * 1000 }
			end,
		},
		TweenInfo = {
			new = function(...)
				return { args = table.pack(...) }
			end,
		},
		RaycastParams = {
			new = function()
				return {}
			end,
		},
		OverlapParams = {
			new = function()
				return {}
			end,
		},
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		BrickColor = roblox.BrickColor,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		PhysicalProperties = roblox.PhysicalProperties,
		Rect = roblox.Rect,
		Ray = roblox.Ray,
		Region3 = roblox.Region3,
		Font = roblox.Font,
		Faces = roblox.Faces,
		Axes = roblox.Axes,
	}
	env.require = function(target)
		return world:RequireInstance(target)
	end
	return env
end

function World:RequireInstance(target: any)
	local lib = self.InstanceLib
	if not lib.isInstance(target) then
		error("require() expects a ModuleScript instance in tests, got " .. typeof(target))
	end
	local cached = self.moduleCache[target]
	if cached ~= nil then
		return cached.value
	end
	if self.loading[target] then
		error("Cyclic require detected: " .. target:GetFullName())
	end
	local sourcePath = rawget(target, "__data").sourcePath
	if not sourcePath then
		error("No source for module " .. target:GetFullName())
	end
	self.loading[target] = true
	local source = rawget(target, "__data").source
	local chunk = luau.load(source, { debugName = sourcePath, environment = self:_env(target) })
	local results = table.pack(pcall(chunk))
	self.loading[target] = nil
	if not results[1] then
		error("Error loading " .. sourcePath .. ": " .. tostring(results[2]), 0)
	end
	if results.n ~= 2 then
		error("Module " .. sourcePath .. " must return exactly one value")
	end
	self.moduleCache[target] = { value = results[2] }
	return results[2]
end

-- Path like "ReplicatedStorage/Shared/Config"
function World:Find(path: string)
	local current = self.game
	for part in path:gmatch("[^/]+") do
		local nextInst = current:FindFirstChild(part)
		if not nextInst then
			error("World:Find could not find '" .. part .. "' in " .. path)
		end
		current = nextInst
	end
	return current
end

function World:Require(path: string)
	return self:RequireInstance(self:Find(path))
end

function World:RunScript(inst: any)
	local sourcePath = rawget(inst, "__data").sourcePath
	local source = rawget(inst, "__data").source
	local chunk = luau.load(source, { debugName = sourcePath, environment = self:_env(inst) })
	self.task.spawn(chunk)
	self.scheduler:RunDue()
	self.scheduler:ThrowIfErrors()
end

function World:StartServer()
	local container = self:Find("ServerScriptService")
	for _, desc in container:GetDescendants() do
		if desc.ClassName == "Script" then
			self:RunScript(desc)
		end
	end
end

-- Run fn inside a coroutine so it may yield; advance time until it finishes.
function World:Run(fn: () -> ...any, maxSeconds: number?)
	local results
	local done = false
	local thread = coroutine.create(function()
		results = table.pack(fn())
		done = true
	end)
	self.scheduler:_resume(thread)
	local elapsed = 0
	local limit = maxSeconds or 120
	while not done and elapsed < limit do
		self.scheduler:Advance(0.1)
		elapsed += 0.1
	end
	self.scheduler:ThrowIfErrors()
	if not done then
		error("World:Run timed out after " .. limit .. " virtual seconds")
	end
	return table.unpack(results, 1, results.n)
end

function World:Advance(seconds: number, step: number?)
	self.scheduler:Advance(seconds, step)
	self.scheduler:ThrowIfErrors()
end

-- Simulate the server shutting down (runs BindToClose callbacks).
function World:Close(maxSeconds: number?)
	for _, fn in self.closeCallbacks do
		self:Run(fn, maxSeconds or 30)
	end
end

function World:FiredTo(remote: any, player: any?)
	local calls = self.InstanceLib.calls(remote, "FireClient")
	local list = {}
	for _, call in calls do
		if player == nil or call[1] == player then
			table.insert(list, call)
		end
	end
	return list
end

return World
