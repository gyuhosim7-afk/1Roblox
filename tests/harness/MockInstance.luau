-- A small, permissive imitation of Roblox's Instance tree for tests.
-- Supports parenting, Name lookup, attributes, tags, signals, Clone, Destroy, and
-- CFrame/Position for parts. Unknown properties read as nil (lenient by design).

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local MockInstance = {}

local CLASS_PARENT = {
	Instance = nil,
	PVInstance = "Instance",
	BasePart = "PVInstance",
	FormFactorPart = "BasePart",
	Part = "FormFactorPart",
	SpawnLocation = "Part",
	WedgePart = "FormFactorPart",
	CornerWedgePart = "BasePart",
	TrussPart = "BasePart",
	MeshPart = "BasePart",
	UnionOperation = "BasePart",
	Model = "PVInstance",
	WorldRoot = "Model",
	Workspace = "WorldRoot",
	Folder = "Instance",
	LuaSourceContainer = "Instance",
	BaseScript = "LuaSourceContainer",
	Script = "BaseScript",
	LocalScript = "Script",
	ModuleScript = "LuaSourceContainer",
	ValueBase = "Instance",
	IntValue = "ValueBase",
	NumberValue = "ValueBase",
	StringValue = "ValueBase",
	BoolValue = "ValueBase",
	ObjectValue = "ValueBase",
	Color3Value = "ValueBase",
	Vector3Value = "ValueBase",
	CFrameValue = "ValueBase",
	GuiBase = "Instance",
	GuiBase2d = "GuiBase",
	GuiObject = "GuiBase2d",
	Frame = "GuiObject",
	ScrollingFrame = "GuiObject",
	CanvasGroup = "GuiObject",
	ViewportFrame = "GuiObject",
	TextLabel = "GuiObject",
	TextBox = "GuiObject",
	ImageLabel = "GuiObject",
	GuiButton = "GuiObject",
	TextButton = "GuiButton",
	ImageButton = "GuiButton",
	LayerCollector = "GuiBase2d",
	ScreenGui = "LayerCollector",
	BillboardGui = "LayerCollector",
	SurfaceGuiBase = "LayerCollector",
	SurfaceGui = "SurfaceGuiBase",
	UIComponent = "Instance",
	UIBase = "Instance",
	UICorner = "UIComponent",
	UIStroke = "UIComponent",
	UIGradient = "UIComponent",
	UIPadding = "UIComponent",
	UIScale = "UIComponent",
	UIConstraint = "UIComponent",
	UIAspectRatioConstraint = "UIConstraint",
	UISizeConstraint = "UIConstraint",
	UITextSizeConstraint = "UIConstraint",
	UILayout = "UIComponent",
	UIGridStyleLayout = "UILayout",
	UIListLayout = "UIGridStyleLayout",
	UIGridLayout = "UIGridStyleLayout",
	Light = "Instance",
	PointLight = "Light",
	SpotLight = "Light",
	SurfaceLight = "Light",
	Attachment = "Instance",
	JointInstance = "Instance",
	Weld = "JointInstance",
	Motor6D = "JointInstance",
	WeldConstraint = "Instance",
	Constraint = "Instance",
	Beam = "Instance",
	Trail = "Instance",
	ParticleEmitter = "Instance",
	Sparkles = "Instance",
	Fire = "Instance",
	Smoke = "Instance",
	Sound = "Instance",
	DataModelMesh = "Instance",
	FileMesh = "DataModelMesh",
	SpecialMesh = "FileMesh",
	Decal = "Instance",
	Texture = "Decal",
	Highlight = "Instance",
	Humanoid = "Instance",
	Player = "Instance",
	RemoteEvent = "Instance",
	RemoteFunction = "Instance",
	UnreliableRemoteEvent = "Instance",
	BindableEvent = "Instance",
	BindableFunction = "Instance",
	ProximityPrompt = "Instance",
	ClickDetector = "Instance",
	Camera = "PVInstance",
	Tool = "Instance",
	Accessory = "Instance",
	Atmosphere = "Instance",
	Sky = "Instance",
	Configuration = "Instance",
}

local DEFAULTS_BY_CLASS = {
	BasePart = {
		Anchored = false,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
		Transparency = 0,
		Reflectance = 0,
		Locked = false,
		CastShadow = true,
		Massless = false,
	},
	GuiObject = { Visible = true, Active = false, BackgroundTransparency = 0, ZIndex = 1, LayoutOrder = 0, Rotation = 0 },
	GuiButton = { AutoButtonColor = true, Selectable = true },
	LayerCollector = { Enabled = true, ResetOnSpawn = true },
	Light = { Enabled = true, Brightness = 1, Range = 8 },
	ProximityPrompt = { Enabled = true, HoldDuration = 0, MaxActivationDistance = 10, ActionText = "Interact", ObjectText = "" },
	Humanoid = { WalkSpeed = 16, JumpPower = 50, JumpHeight = 7.2, Health = 100, MaxHealth = 100, PlatformStand = false },
	ParticleEmitter = { Enabled = true, Rate = 5 },
	Beam = { Enabled = true },
	Sound = { Volume = 0.5, Playing = false, Looped = false },
	ValueBase = {},
	Player = { UserId = 0, AccountAge = 30, MembershipType = nil },
}

local EVENT_NAMES = {
	Changed = true,
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	DescendantRemoving = true,
	AncestryChanged = true,
	Destroying = true,
	AttributeChanged = true,
	Touched = true,
	TouchEnded = true,
	Triggered = true,
	TriggerEnded = true,
	PromptButtonHoldBegan = true,
	PromptButtonHoldEnded = true,
	PromptShown = true,
	PromptHidden = true,
	OnServerEvent = true,
	OnClientEvent = true,
	Event = true,
	Activated = true,
	MouseButton1Click = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	MouseEnter = true,
	MouseLeave = true,
	InputBegan = true,
	InputEnded = true,
	FocusLost = true,
	CharacterAdded = true,
	CharacterRemoving = true,
	CharacterAppearanceLoaded = true,
	Died = true,
	StateChanged = true,
	Running = true,
	MoveToFinished = true,
	Equipped = true,
	Unequipped = true,
	Ended = true,
	Completed = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	Heartbeat = true,
	Stepped = true,
	RenderStepped = true,
	PreSimulation = true,
	PostSimulation = true,
	Chatted = true,
	PromptGamePassPurchaseFinished = true,
	PromptProductPurchaseFinished = true,
	PromptPurchaseFinished = true,
	Idled = true,
}

function MockInstance.newLibrary(scheduler: any)
	local lib = {}
	local InstanceMT = {}
	local Methods = {}
	local classMethods = {}
	lib.classMethods = classMethods
	lib.onTagChanged = nil :: ((inst: any, tag: string, added: boolean) -> ())?

	-- Signals -----------------------------------------------------------------
	local SignalMT = {}
	SignalMT.__index = SignalMT

	local function newSignal()
		return setmetatable({ _handlers = {}, _waiting = {} }, SignalMT)
	end
	lib.Signal = newSignal

	function SignalMT:Connect(fn)
		local connection = { Connected = true }
		local handlers = self._handlers
		function connection.Disconnect(conn)
			conn.Connected = false
			for index, item in handlers do
				if item == conn then
					table.remove(handlers, index)
					break
				end
			end
		end
		connection.fn = fn
		table.insert(handlers, connection)
		return connection
	end

	function SignalMT:Once(fn)
		local connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end

	function SignalMT:ConnectParallel(fn)
		return self:Connect(fn)
	end

	function SignalMT:Wait()
		local thread = coroutine.running()
		table.insert(self._waiting, thread)
		return coroutine.yield()
	end

	function SignalMT:Fire(...)
		local list = table.clone(self._handlers)
		for _, connection in list do
			if connection.Connected then
				local thread = coroutine.create(connection.fn)
				scheduler:_resume(thread, ...)
			end
		end
		local waiting = self._waiting
		self._waiting = {}
		for _, thread in waiting do
			scheduler:_resume(thread, ...)
		end
	end

	function SignalMT:DisconnectAll()
		for _, connection in self._handlers do
			connection.Connected = false
		end
		table.clear(self._handlers)
	end

	-- Helpers -----------------------------------------------------------------
	local function isA(className: string, target: string): boolean
		local current: string? = className
		while current do
			if current == target then
				return true
			end
			current = CLASS_PARENT[current]
		end
		return target == "Instance"
	end
	lib.classIsA = isA

	local function data(inst)
		return rawget(inst, "__data")
	end

	local function getSignal(inst, name: string)
		local d = data(inst)
		local signal = d.signals[name]
		if not signal then
			signal = newSignal()
			d.signals[name] = signal
		end
		return signal
	end
	lib.getSignal = getSignal

	local function defaultFor(className: string, key: string)
		local current: string? = className
		while current do
			local defaults = DEFAULTS_BY_CLASS[current]
			if defaults and defaults[key] ~= nil then
				return defaults[key]
			end
			current = CLASS_PARENT[current]
		end
		return nil
	end

	local function fireChanged(inst, key: string)
		local d = data(inst)
		local propSignal = d.propSignals[key]
		if propSignal then
			propSignal:Fire()
		end
		local changed = d.signals.Changed
		if changed then
			changed:Fire(key)
		end
	end

	local function ancestors(inst)
		local list = {}
		local current = data(inst).parent
		while current do
			table.insert(list, current)
			current = data(current).parent
		end
		return list
	end

	local function setParent(inst, newParent)
		local d = data(inst)
		if d.destroyed and newParent ~= nil then
			error("The Parent property of " .. d.props.Name .. " is locked")
		end
		local oldParent = d.parent
		if oldParent == newParent then
			return
		end
		if oldParent then
			local od = data(oldParent)
			for index, child in od.children do
				if child == inst then
					table.remove(od.children, index)
					break
				end
			end
			for _, ancestor in { oldParent, table.unpack(ancestors(oldParent)) } do
				local signal = data(ancestor).signals.DescendantRemoving
				if signal then
					signal:Fire(inst)
				end
			end
			local removed = od.signals.ChildRemoved
			if removed then
				removed:Fire(inst)
			end
		end
		d.parent = newParent
		if newParent then
			table.insert(data(newParent).children, inst)
			local added = data(newParent).signals.ChildAdded
			if added then
				added:Fire(inst)
			end
			for _, ancestor in { newParent, table.unpack(ancestors(newParent)) } do
				local signal = data(ancestor).signals.DescendantAdded
				if signal then
					signal:Fire(inst)
				end
			end
			-- wake WaitForChild waiters
			local pd = data(newParent)
			local waiters = pd.childWaiters[d.props.Name]
			if waiters then
				pd.childWaiters[d.props.Name] = nil
				for _, thread in waiters do
					scheduler:_resume(thread, inst)
				end
			end
		end
		local ancestry = d.signals.AncestryChanged
		if ancestry then
			ancestry:Fire(inst, newParent)
		end
		fireChanged(inst, "Parent")
	end

	-- Construction ----------------------------------------------------------
	function lib.new(className: string, parent: any?)
		local inst = setmetatable({
			__data = {
				className = className,
				props = { Name = className },
				children = {},
				parent = nil,
				signals = {},
				propSignals = {},
				attributes = {},
				attrSignals = {},
				tags = {},
				childWaiters = {},
				destroyed = false,
				calls = {},
			},
		}, InstanceMT)
		if isA(className, "BasePart") then
			local props = data(inst).props
			props.CFrame = CFrame.new()
			props.Size = if className == "SpawnLocation" then Vector3.new(12, 1, 12) else Vector3.new(4, 1, 2)
			props.Color = roblox.Color3.fromRGB(163, 162, 165)
			props.Material = roblox.Enum.Material.Plastic
			props.AssemblyLinearVelocity = Vector3.new()
		end
		if parent then
			setParent(inst, parent)
		end
		return inst
	end

	function lib.isInstance(value): boolean
		return type(value) == "table" and getmetatable(value) == InstanceMT
	end

	function lib.className(inst): string
		return data(inst).className
	end

	function lib.calls(inst, method: string)
		return data(inst).calls[method] or {}
	end

	local function recordCall(inst, method: string, ...)
		local calls = data(inst).calls
		calls[method] = calls[method] or {}
		table.insert(calls[method], table.pack(...))
	end
	lib.recordCall = recordCall

	-- Metatable --------------------------------------------------------------
	InstanceMT.__index = function(inst, key)
		local d = data(inst)
		local classTable = classMethods[d.className]
		if classTable and classTable[key] ~= nil then
			return classTable[key]
		end
		local current = CLASS_PARENT[d.className]
		while current do
			local t = classMethods[current]
			if t and t[key] ~= nil then
				return t[key]
			end
			current = CLASS_PARENT[current]
		end
		local method = Methods[key]
		if method then
			return method
		end
		if key == "ClassName" then
			return d.className
		end
		if key == "Parent" then
			return d.parent
		end
		local value = d.props[key]
		if value ~= nil then
			return value
		end
		if key == "Position" and d.props.CFrame then
			return d.props.CFrame.Position
		end
		if key == "Orientation" and d.props.CFrame then
			return Vector3.new(0, 0, 0)
		end
		if EVENT_NAMES[key] then
			return getSignal(inst, key)
		end
		for _, child in d.children do
			if data(child).props.Name == key then
				return child
			end
		end
		return defaultFor(d.className, key)
	end

	InstanceMT.__newindex = function(inst, key, value)
		local d = data(inst)
		if key == "Parent" then
			if value ~= nil and not lib.isInstance(value) then
				error("Parent must be an Instance")
			end
			setParent(inst, value)
			return
		end
		if key == "Position" and d.props.CFrame then
			local cf = d.props.CFrame
			d.props.CFrame = CFrame.new(value) * (cf - cf.Position)
			fireChanged(inst, "CFrame")
			fireChanged(inst, "Position")
			return
		end
		if key == "Name" then
			value = tostring(value)
		end
		d.props[key] = value
		fireChanged(inst, key)
	end

	InstanceMT.__tostring = function(inst)
		return data(inst).props.Name
	end

	-- Generic methods --------------------------------------------------------
	function Methods:IsA(className: string): boolean
		return isA(data(self).className, className)
	end

	function Methods:GetChildren()
		return table.clone(data(self).children)
	end

	function Methods:GetDescendants()
		local list = {}
		local function walk(inst)
			for _, child in data(inst).children do
				table.insert(list, child)
				walk(child)
			end
		end
		walk(self)
		return list
	end

	function Methods:FindFirstChild(name: string, recursive: boolean?)
		for _, child in data(self).children do
			if data(child).props.Name == name then
				return child
			end
		end
		if recursive then
			for _, child in data(self).children do
				local found = child:FindFirstChild(name, true)
				if found then
					return found
				end
			end
		end
		return nil
	end

	function Methods:FindFirstChildOfClass(className: string)
		for _, child in data(self).children do
			if data(child).className == className then
				return child
			end
		end
		return nil
	end

	function Methods:FindFirstChildWhichIsA(className: string, recursive: boolean?)
		for _, child in data(self).children do
			if isA(data(child).className, className) then
				return child
			end
		end
		if recursive then
			for _, child in data(self).children do
				local found = child:FindFirstChildWhichIsA(className, true)
				if found then
					return found
				end
			end
		end
		return nil
	end

	function Methods:FindFirstAncestor(name: string)
		for _, ancestor in ancestors(self) do
			if data(ancestor).props.Name == name then
				return ancestor
			end
		end
		return nil
	end

	function Methods:FindFirstAncestorOfClass(className: string)
		for _, ancestor in ancestors(self) do
			if data(ancestor).className == className then
				return ancestor
			end
		end
		return nil
	end

	function Methods:FindFirstAncestorWhichIsA(className: string)
		for _, ancestor in ancestors(self) do
			if isA(data(ancestor).className, className) then
				return ancestor
			end
		end
		return nil
	end

	function Methods:WaitForChild(name: string, timeout: number?)
		local found = self:FindFirstChild(name)
		if found then
			return found
		end
		if not coroutine.isyieldable() then
			error("WaitForChild(" .. name .. ") would yield forever on main thread; child missing in " .. self:GetFullName())
		end
		local thread = coroutine.running()
		local waiters = data(self).childWaiters
		waiters[name] = waiters[name] or {}
		table.insert(waiters[name], thread)
		if timeout then
			scheduler:_schedule(scheduler.now + timeout, thread, { nil })
		end
		return coroutine.yield()
	end

	function Methods:IsDescendantOf(other)
		for _, ancestor in ancestors(self) do
			if ancestor == other then
				return true
			end
		end
		return false
	end

	function Methods:IsAncestorOf(other)
		return other:IsDescendantOf(self)
	end

	function Methods:GetFullName()
		local parts = { data(self).props.Name }
		for _, ancestor in ancestors(self) do
			if data(ancestor).className == "DataModel" then
				break
			end
			table.insert(parts, 1, data(ancestor).props.Name)
		end
		return table.concat(parts, ".")
	end

	function Methods:Destroy()
		local d = data(self)
		if d.destroyed then
			return
		end
		local destroying = d.signals.Destroying
		if destroying then
			destroying:Fire()
		end
		for _, child in table.clone(d.children) do
			child:Destroy()
		end
		setParent(self, nil)
		d.destroyed = true
		for _, signal in d.signals do
			signal:DisconnectAll()
		end
		for tag in d.tags do
			if lib.onTagChanged then
				lib.onTagChanged(self, tag, false)
			end
		end
	end

	function Methods:ClearAllChildren()
		for _, child in table.clone(data(self).children) do
			child:Destroy()
		end
	end

	function Methods:Clone()
		local d = data(self)
		local copy = lib.new(d.className)
		local cd = data(copy)
		for key, value in d.props do
			cd.props[key] = value
		end
		for key, value in d.attributes do
			cd.attributes[key] = value
		end
		for tag in d.tags do
			cd.tags[tag] = true
			if lib.onTagChanged then
				lib.onTagChanged(copy, tag, true)
			end
		end
		for _, child in d.children do
			local childCopy = child:Clone()
			childCopy.Parent = copy
		end
		return copy
	end

	function Methods:GetAttribute(name: string)
		return data(self).attributes[name]
	end

	function Methods:SetAttribute(name: string, value: any)
		local t = typeof(value)
		if value ~= nil and t ~= "number" and t ~= "string" and t ~= "boolean" and t ~= "Vector3" and t ~= "Color3" and t ~= "CFrame" and t ~= "UDim2" and t ~= "Vector2" and t ~= "NumberRange" then
			error("SetAttribute: unsupported attribute type " .. t .. " for " .. name)
		end
		local d = data(self)
		d.attributes[name] = value
		local signal = d.attrSignals[name]
		if signal then
			signal:Fire()
		end
		local changed = d.signals.AttributeChanged
		if changed then
			changed:Fire(name)
		end
	end

	function Methods:GetAttributes()
		return table.clone(data(self).attributes)
	end

	function Methods:GetAttributeChangedSignal(name: string)
		local d = data(self)
		d.attrSignals[name] = d.attrSignals[name] or newSignal()
		return d.attrSignals[name]
	end

	function Methods:GetPropertyChangedSignal(name: string)
		local d = data(self)
		d.propSignals[name] = d.propSignals[name] or newSignal()
		return d.propSignals[name]
	end

	function Methods:AddTag(tag: string)
		local d = data(self)
		if not d.tags[tag] then
			d.tags[tag] = true
			if lib.onTagChanged then
				lib.onTagChanged(self, tag, true)
			end
		end
	end

	function Methods:RemoveTag(tag: string)
		local d = data(self)
		if d.tags[tag] then
			d.tags[tag] = nil
			if lib.onTagChanged then
				lib.onTagChanged(self, tag, false)
			end
		end
	end

	function Methods:HasTag(tag: string)
		return data(self).tags[tag] == true
	end

	function Methods:GetTags()
		local list = {}
		for tag in data(self).tags do
			table.insert(list, tag)
		end
		return list
	end

	-- PVInstance ---------------------------------------------------------------
	local function primaryOf(model)
		local primary = data(model).props.PrimaryPart
		if primary then
			return primary
		end
		return model:FindFirstChildWhichIsA("BasePart", true)
	end

	function Methods:GetPivot()
		local d = data(self)
		if d.props.CFrame then
			return d.props.CFrame
		end
		local primary = primaryOf(self)
		if primary then
			return data(primary).props.CFrame
		end
		return CFrame.new()
	end

	function Methods:PivotTo(target)
		local d = data(self)
		if d.props.CFrame then
			d.props.CFrame = target
			fireChanged(self, "CFrame")
			return
		end
		local current = self:GetPivot()
		local offset = target * current:Inverse()
		for _, desc in self:GetDescendants() do
			local dd = data(desc)
			if dd.props.CFrame and isA(dd.className, "BasePart") then
				dd.props.CFrame = offset * dd.props.CFrame
			end
		end
		recordCall(self, "PivotTo", target)
	end

	function Methods:GetBoundingBox()
		return self:GetPivot(), Vector3.new(4, 4, 4)
	end

	function Methods:GetExtentsSize()
		return Vector3.new(4, 4, 4)
	end

	function Methods:ScaleTo(_scale: number) end
	function Methods:GetScale()
		return 1
	end

	-- BasePart --------------------------------------------------------------
	function Methods:ApplyImpulse(impulse)
		recordCall(self, "ApplyImpulse", impulse)
	end
	function Methods:SetNetworkOwner(owner)
		recordCall(self, "SetNetworkOwner", owner)
	end
	function Methods:GetMass()
		return 1
	end
	function Methods:GetTouchingParts()
		return {}
	end

	-- Misc --------------------------------------------------------------------
	function Methods:Play()
		recordCall(self, "Play")
	end
	function Methods:Stop()
		recordCall(self, "Stop")
	end
	function Methods:Emit(count)
		recordCall(self, "Emit", count)
	end
	function Methods:TakeDamage(amount)
		local d = data(self)
		d.props.Health = (d.props.Health or 100) - amount
	end
	function Methods:ChangeState(state)
		recordCall(self, "ChangeState", state)
	end
	function Methods:GetState()
		return roblox.Enum.HumanoidStateType.Running
	end
	function Methods:MoveTo(...)
		recordCall(self, "MoveTo", ...)
	end
	function Methods:LoadAnimation()
		return { Play = function() end, Stop = function() end }
	end

	-- Remotes -----------------------------------------------------------------
	function Methods:FireClient(player, ...)
		recordCall(self, "FireClient", player, ...)
		if lib.onFireClient then
			lib.onFireClient(self, player, ...)
		end
	end
	function Methods:FireAllClients(...)
		recordCall(self, "FireAllClients", ...)
		if lib.onFireAllClients then
			lib.onFireAllClients(self, ...)
		end
	end
	function Methods:FireServer(...)
		recordCall(self, "FireServer", ...)
	end
	function Methods:InvokeServer(...)
		recordCall(self, "InvokeServer", ...)
		if lib.onInvokeServer then
			return lib.onInvokeServer(self, ...)
		end
		return nil
	end
	function Methods:InvokeClient(player, ...)
		recordCall(self, "InvokeClient", player, ...)
		return nil
	end
	function Methods:Fire(...)
		local d = data(self)
		if d.className == "BindableEvent" then
			getSignal(self, "Event"):Fire(...)
		end
	end

	return lib
end

return MockInstance
