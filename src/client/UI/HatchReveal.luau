--!strict
-- Egg hatch reveal: the egg shakes (longer and wilder for better rarities, glowing in the
-- rarity color near the end), cracks with a flash and flying shell pieces, then the slime pops
-- out over spinning light rays, glow rings and a sparkle burst. Mythic shows run in rainbow.
-- Numbers per rarity live in Config.HatchFx. Tap to skip the shake / close the result.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local EggBuilder = require(Shared.EggBuilder)
local SlimeBuilder = require(Shared.SlimeBuilder)
local Theme = require(script.Parent.Theme)

local HatchReveal = {}

local screen: ScreenGui? = nil
local queue: { any } = {}
local showing = false

local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 213, 79)

function HatchReveal.Mount(gui: ScreenGui)
	screen = gui
end

-- The egg a slime comes from (for reveals that don't say which egg it was).
local function eggFor(kind: string): string
	for eggId, egg in Config.Eggs do
		for _, entry in egg.Pool do
			if entry.Slime == kind then
				return eggId
			end
		end
	end
	return "Meadow"
end

local function rainbow(t: number, offset: number?): Color3
	return Color3.fromHSV((t * 0.35 + (offset or 0)) % 1, 0.75, 1)
end

local function circle(parent: Instance, size: number, color: Color3, transparency: number, z: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

local function viewportOf(parent: Instance, model: Model, size: number, z: number): (ViewportFrame, Camera)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.BackgroundTransparency = 1
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromOffset(size, size)
	viewport.Ambient = Color3.fromRGB(210, 210, 220)
	viewport.LightColor = WHITE
	viewport.LightDirection = Vector3.new(-0.4, -1, 0.6)
	viewport.ZIndex = z
	model.Parent = viewport
	local extents = model:GetExtentsSize()
	local radius = math.max(extents.X, extents.Y, extents.Z)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local target = Vector3.new(0, extents.Y * 0.5, 0)
	-- models face -Z: look at them from the front, a little from above
	camera.CFrame = CFrame.lookAt(target + Vector3.new(radius * 0.25, radius * 0.35, -radius * 2.3), target)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = parent
	return viewport, camera
end

local function scaleOf(guiObject: GuiObject, start: number): UIScale
	local scale = Instance.new("UIScale")
	scale.Scale = start
	scale.Parent = guiObject
	return scale
end

-- Pieces flying out from the center and fading away.
local function burst(parent: Instance, count: number, color: () -> Color3, minDistance: number, maxDistance: number)
	for i = 1, count do
		local size = math.random(10, 24)
		local piece = Instance.new("Frame")
		piece.Name = "Sparkle"
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromScale(0.5, 0.5)
		piece.Size = UDim2.fromOffset(size, size)
		piece.Rotation = 45
		piece.BackgroundColor3 = color()
		piece.BorderSizePixel = 0
		piece.ZIndex = 26
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(if i % 3 == 0 then 0.5 else 0.15, 0)
		corner.Parent = piece
		piece.Parent = parent
		local angle = (i / count) * math.pi * 2 + math.random() * 0.4
		local distance = minDistance + math.random() * (maxDistance - minDistance)
		local duration = 0.7 + math.random() * 0.7
		TweenService:Create(piece, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(angle) * distance, 0.5, math.sin(angle) * distance),
			Rotation = 45 + math.random(-200, 200),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size * 0.4, size * 0.4),
		}):Play()
		task.delay(duration + 0.05, function()
			piece:Destroy()
		end)
	end
end

local function showNext()
	local gui = screen
	if showing or #queue == 0 or not gui then
		return
	end
	local info = table.remove(queue, 1)
	local def = Config.Slimes[info.Kind]
	if not def then
		showNext()
		return
	end
	showing = true
	local fx = (Config.HatchFx :: any)[def.Rarity] or Config.HatchFx.Common
	local speed = if #queue > 0 then Config.HatchFx.QueueSpeedUp else 1
	local isRainbow = fx.Rainbow == true or info.Mutation == "Rainbow"
	local rarityColor = Theme.Hex(Config.Rarities[def.Rarity].Color)
	local mainColor = if info.Mutation == "Gold" then GOLD else rarityColor
	local eggId = if type(info.Egg) == "string" then info.Egg else eggFor(info.Kind)
	local connections: { RBXScriptConnection } = {}
	local clock = 0

	-- Dark backdrop that covers the screen (tap anywhere)
	local overlay = Instance.new("TextButton")
	overlay.Name = "HatchPopup"
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.BackgroundColor3 = Color3.fromRGB(10, 6, 24)
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 20
	overlay.Parent = gui
	TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.3 }):Play()

	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromOffset(520, 520)
	stage.ZIndex = 21
	stage.Parent = overlay
	Theme.AutoScale(stage)

	-- Glow rings (start hidden, they charge up during the shake)
	local rings: { Frame } = {}
	for i = 1, fx.Rings do
		local ring = circle(stage, 150 + i * 80, mainColor, 1, 21)
		table.insert(rings, ring)
	end

	-- Light rays behind the slime
	local rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.BackgroundTransparency = 1
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromOffset(760, 760)
	rays.Visible = false
	rays.ZIndex = 22
	rays.Parent = stage
	local rayBars: { Frame } = {}
	for i = 1, fx.Rays do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.new(1, 0, 0, if i % 2 == 0 then 26 else 14)
		bar.Rotation = (i - 1) * 180 / fx.Rays
		bar.BackgroundColor3 = mainColor
		bar.BorderSizePixel = 0
		bar.ZIndex = 22
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = bar
		bar.Parent = rays
		table.insert(rayBars, bar)
	end
	local raysScale = scaleOf(rays, 0.2)

	-- The egg
	local egg = EggBuilder.Build(eggId, 1)
	local eggView = viewportOf(stage, egg, 250, 24)
	local eggScale = scaleOf(eggView, 0.4)
	TweenService:Create(eggScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	local cracked = false
	local closed = false
	local revealAt = math.huge
	local shakeTime = fx.Shake * speed
	local lastTick = 0

	local crackedAt = 0
	-- force = timer closing it; a tap only closes once the result has been visible a moment
	local function close(force: boolean?)
		if closed or not cracked or (not force and os.clock() - crackedAt < 0.4) then
			return
		end
		closed = true
		for _, connection in connections do
			connection:Disconnect()
		end
		TweenService:Create(overlay, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stage, TweenInfo.new(0.2), { Position = UDim2.fromScale(0.5, 0.56) }):Play()
		task.delay(0.2, function()
			overlay:Destroy()
			showing = false
			showNext()
		end)
	end

	local function crack()
		if cracked then
			return
		end
		cracked = true
		revealAt = clock
		crackedAt = os.clock()
		-- white flash
		local flash = Instance.new("Frame")
		flash.BackgroundColor3 = WHITE
		flash.BorderSizePixel = 0
		flash.Size = UDim2.fromScale(1, 1)
		flash.ZIndex = 30
		flash.Parent = overlay
		TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
		task.delay(0.5, function()
			flash:Destroy()
		end)
		-- shell pieces
		local eggDef = Config.Eggs[eggId]
		local shellColor = if eggDef then Theme.Hex(eggDef.Color) elseif eggId == "Royal" then GOLD else WHITE
		burst(stage, 10, function()
			return shellColor
		end, 120, 220)
		eggView:Destroy()
		-- sparkles
		burst(stage, fx.Sparkles, function()
			if isRainbow then
				return rainbow(math.random(), 0)
			end
			local roll = math.random()
			return if roll < 0.5 then mainColor elseif roll < 0.8 then WHITE else GOLD
		end, 160, 420)
		-- rays + rings
		rays.Visible = true
		TweenService:Create(raysScale, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		for i, ring in rings do
			ring.BackgroundTransparency = 0.55
			TweenService:Create(ring, TweenInfo.new(0.6 + i * 0.15), { BackgroundTransparency = 0.8 }):Play()
		end
		-- soft halo so the slime stands out from the bright rays
		local halo = circle(stage, 250, WHITE, 0.55, 23)
		halo.Position = UDim2.fromScale(0.5, 0.46)
		TweenService:Create(halo, TweenInfo.new(1.2), { BackgroundTransparency = 0.75 }):Play()
		-- the slime pops out
		local slime = SlimeBuilder.Build(info.Kind, info.Mutation)
		local slimeView = viewportOf(stage, slime, 300, 25)
		slimeView.Position = UDim2.fromScale(0.5, 0.46)
		local slimeScale = scaleOf(slimeView, 0.1)
		TweenService:Create(slimeScale, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		table.insert(
			connections,
			RunService.RenderStepped:Connect(function(dt: number)
				slime:PivotTo(slime:GetPivot() * CFrame.Angles(0, dt * 1.1, 0))
			end)
		)

		-- texts
		local order = Config.Rarities[def.Rarity].Order
		local headline = if info.New then "NEW SLIME!" elseif info.Source == "Royal" then "ROYAL HATCH!" else "HATCHED!"
		local top = Theme.Text(stage, headline, { MaxSize = 40, Color = GOLD, StrokeThickness = 3.5 })
		top.Size = UDim2.new(1, 0, 0, 50)
		top.Position = UDim2.fromOffset(0, 18)
		top.ZIndex = 27
		local banner = Theme.Frame({
			Name = "RarityBanner",
			Size = UDim2.fromOffset(240, 44),
			Position = UDim2.new(0.5, 0, 0, 74),
			AnchorPoint = Vector2.new(0.5, 0),
			Color = mainColor,
			Radius = 22,
			Parent = stage,
		})
		banner.ZIndex = 27
		local rarityText = Theme.Text(
			banner,
			string.upper(def.Rarity) .. (if order >= 5 then "!!" elseif order >= 3 then "!" else ""),
			{ MaxSize = 30, StrokeThickness = 3 }
		)
		rarityText.Size = UDim2.new(1, -16, 1, -6)
		rarityText.Position = UDim2.fromOffset(8, 3)
		rarityText.ZIndex = 28
		local shimmer: UIGradient? = nil
		if order >= 5 or isRainbow then
			local gradient = Instance.new("UIGradient")
			gradient.Color = if isRainbow
				then ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
					ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 90)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 140)),
					ColorSequenceKeypoint.new(0.75, Color3.fromRGB(90, 170, 255)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 90, 255)),
				})
				else ColorSequence.new({
					ColorSequenceKeypoint.new(0, mainColor),
					ColorSequenceKeypoint.new(0.5, WHITE),
					ColorSequenceKeypoint.new(1, mainColor),
				})
			gradient.Parent = banner
			shimmer = gradient
		end
		local mutationName = if info.Mutation ~= "None"
			then (Config.Mutations :: any)[info.Mutation].Name .. " "
			else ""
		local name = Theme.Text(stage, mutationName .. def.Name, { MaxSize = 34, Color = WHITE, StrokeThickness = 3.5 })
		name.Size = UDim2.new(1, 0, 0, 44)
		name.Position = UDim2.new(0, 0, 1, -122)
		name.ZIndex = 27
		local nameStroke = name:FindFirstChildOfClass("UIStroke")
		if nameStroke then
			nameStroke.Color = Theme.Colors.Outline
		end
		local detail = "$"
			.. Format.Number(def.Income * (Config.Mutations :: any)[info.Mutation or "None"].Multiplier)
			.. "/s"
		if info.Gems and info.Gems > 0 then
			detail ..= "   +" .. info.Gems .. " Gems"
		end
		local sub =
			Theme.Text(stage, detail, { MaxSize = 26, Color = Color3.fromRGB(150, 255, 140), StrokeThickness = 3 })
		sub.Size = UDim2.new(1, 0, 0, 34)
		sub.Position = UDim2.new(0, 0, 1, -78)
		sub.ZIndex = 27
		local tap = Theme.Text(stage, "tap to continue", { MaxSize = 16, Color = Theme.Colors.SubText })
		tap.Size = UDim2.new(1, 0, 0, 22)
		tap.Position = UDim2.new(0, 0, 1, -36)
		tap.ZIndex = 27

		Theme.Play("Hatch", if order >= 4 then 0.9 else 0.5)
		-- rays spin, rainbow cycles, gold shimmer slides
		table.insert(
			connections,
			RunService.RenderStepped:Connect(function(dt: number)
				rays.Rotation += dt * (if order >= 5 then 40 else 22)
				if isRainbow then
					for i, bar in rayBars do
						bar.BackgroundColor3 = rainbow(clock, i / #rayBars)
					end
					for i, ring in rings do
						ring.BackgroundColor3 = rainbow(clock, i * 0.2)
					end
				end
				local gradient = shimmer
				if gradient then
					gradient.Offset = Vector2.new(math.sin(clock * 2.5) * 0.6, 0)
				end
			end)
		)
		task.delay(fx.Hold * speed + 0.45, function()
			close(true)
		end)
	end

	-- Shake, charge the glow, then crack. Screen shake right after the crack.
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt: number)
			clock += dt
			if not cracked then
				local progress = math.clamp(clock / shakeTime, 0, 1)
				local amplitude = 6 + 22 * progress * progress
				local angle = math.sin(clock * (14 + 16 * progress)) * amplitude
				egg:PivotTo(CFrame.Angles(0, clock * 0.8, math.rad(angle)))
				eggScale.Scale = 1 + 0.12 * progress + 0.04 * math.sin(clock * 20) * progress
				if progress > 0.45 then
					local charge = (progress - 0.45) / 0.55
					for i, ring in rings do
						ring.BackgroundTransparency = 1 - 0.35 * charge / i
						if isRainbow then
							ring.BackgroundColor3 = rainbow(clock, i * 0.2)
						end
					end
				end
				if clock - lastTick > 0.32 then
					lastTick = clock
					Theme.Play("Click", 0.25)
				end
				if progress >= 1 then
					crack()
				end
			elseif fx.ScreenShake > 0 and clock - revealAt < 0.55 then
				local strength = fx.ScreenShake * (1 - (clock - revealAt) / 0.55)
				stage.Position = UDim2.new(
					0.5,
					math.random(-100, 100) / 100 * strength,
					0.5,
					math.random(-100, 100) / 100 * strength
				)
			else
				stage.Position = UDim2.fromScale(0.5, 0.5)
			end
		end)
	)

	overlay.Activated:Connect(function()
		if not cracked then
			crack()
		else
			close()
		end
	end)
	-- safety: never stay on screen forever
	task.delay(shakeTime + fx.Hold * speed + 3, function()
		if not cracked then
			crack()
		end
		task.delay(1, function()
			close(true)
		end)
	end)
end

function HatchReveal.Show(info: any)
	table.insert(queue, info)
	showNext()
end

-- Shows the reveal is running (for tests and other popups).
function HatchReveal.IsShowing(): boolean
	return showing
end

return HatchReveal
