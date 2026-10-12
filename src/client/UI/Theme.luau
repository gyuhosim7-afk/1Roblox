--!strict
-- UI kit: colors, fonts and small builders. Layout is designed at a 1100x620 reference size;
-- every top-level element gets a UIScale so it fits phones and big screens alike.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.Reference = Vector2.new(1100, 620)

Theme.Colors = {
	Background = Color3.fromRGB(30, 30, 46),
	Panel = Color3.fromRGB(42, 42, 64),
	PanelLight = Color3.fromRGB(58, 58, 86),
	Stroke = Color3.fromRGB(16, 16, 26),
	Text = Color3.fromRGB(255, 255, 255),
	SubText = Color3.fromRGB(200, 205, 215),
	Accent = Color3.fromRGB(255, 176, 0),
	Green = Color3.fromRGB(67, 190, 71),
	Red = Color3.fromRGB(229, 57, 53),
	Blue = Color3.fromRGB(64, 156, 255),
	Purple = Color3.fromRGB(178, 102, 255),
	Pink = Color3.fromRGB(255, 79, 163),
	Gold = Color3.fromRGB(255, 213, 79),
	Gem = Color3.fromRGB(80, 220, 255),
	Disabled = Color3.fromRGB(110, 110, 125),
}

Theme.Sounds = {
	Click = "rbxasset://sounds/clickfast.wav",
	Collect = "rbxasset://sounds/electronicpingshort.wav",
	Bonk = "rbxasset://sounds/swordslash.wav",
	Hatch = "rbxasset://sounds/victory.wav",
	Hit = "rbxasset://sounds/uuhhh.mp3",
	Steal = "rbxasset://sounds/snap.wav",
}

local soundCache: { [string]: Sound } = {}

function Theme.Play(name: string, volume: number?)
	local id = (Theme.Sounds :: any)[name]
	if not id then
		return
	end
	local sound = soundCache[name]
	if not sound then
		local newSound = Instance.new("Sound")
		newSound.Name = "UISound_" .. name
		newSound.SoundId = id
		newSound.Volume = volume or 0.5
		newSound.Parent = SoundService
		soundCache[name] = newSound
		sound = newSound
	end
	pcall(function()
		SoundService:PlayLocalSound(sound)
	end)
end

-- Scale factor for the current screen.
function Theme.ScaleFactor(): number
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Theme.Reference
	local factor = math.min(size.X / Theme.Reference.X, size.Y / Theme.Reference.Y)
	return math.clamp(factor, 0.5, 1.6)
end

local scaled: { UIScale } = {}

-- Adds a UIScale that tracks the screen size.
function Theme.AutoScale(guiObject: GuiObject)
	local scale = Instance.new("UIScale")
	scale.Scale = Theme.ScaleFactor()
	scale.Parent = guiObject
	table.insert(scaled, scale)
end

function Theme.RefreshScale()
	local factor = Theme.ScaleFactor()
	for _, scale in scaled do
		scale.Scale = factor
	end
end

function Theme.Corner(parent: Instance, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = parent
	return corner
end

function Theme.Stroke(parent: Instance, thickness: number?, color: Color3?, transparency: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 3
	stroke.Color = color or Theme.Colors.Stroke
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Theme.Gradient(parent: Instance, top: Color3, bottom: Color3)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = 90
	gradient.Parent = parent
	return gradient
end

function Theme.Padding(parent: Instance, pixels: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pixels)
	padding.PaddingBottom = UDim.new(0, pixels)
	padding.PaddingLeft = UDim.new(0, pixels)
	padding.PaddingRight = UDim.new(0, pixels)
	padding.Parent = parent
	return padding
end

function Theme.List(parent: Instance, padding: number?, horizontal: boolean?, align: Enum.HorizontalAlignment?)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding or 6)
	layout.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = align or Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = parent
	return layout
end

export type FrameProps = {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	Transparency: number?,
	Radius: number?,
	Stroke: boolean?,
	Parent: Instance?,
	LayoutOrder: number?,
}

function Theme.Frame(props: FrameProps): Frame
	local frame = Instance.new("Frame")
	frame.Name = props.Name or "Frame"
	frame.Size = props.Size or UDim2.fromOffset(100, 100)
	frame.Position = props.Position or UDim2.new()
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.BackgroundColor3 = props.Color or Theme.Colors.Panel
	frame.BackgroundTransparency = props.Transparency or 0
	frame.BorderSizePixel = 0
	frame.LayoutOrder = props.LayoutOrder or 0
	if props.Radius ~= 0 then
		Theme.Corner(frame, props.Radius)
	end
	if props.Stroke ~= false then
		Theme.Stroke(frame, 3)
	end
	if props.Parent then
		frame.Parent = props.Parent
	end
	return frame
end

export type TextProps = {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	MaxSize: number?,
	Align: Enum.TextXAlignment?,
	LayoutOrder: number?,
	Wrap: boolean?,
	Stroke: boolean?,
}

function Theme.Text(parent: Instance, text: string, props: TextProps?): TextLabel
	local p: TextProps = props or {}
	local label = Instance.new("TextLabel")
	label.Name = p.Name or "Text"
	label.BackgroundTransparency = 1
	label.Size = p.Size or UDim2.fromScale(1, 1)
	label.Position = p.Position or UDim2.new()
	label.AnchorPoint = p.AnchorPoint or Vector2.zero
	label.Font = Theme.Font
	label.Text = text
	label.TextColor3 = p.Color or Theme.Colors.Text
	label.TextScaled = true
	label.TextWrapped = p.Wrap ~= false
	label.TextXAlignment = p.Align or Enum.TextXAlignment.Center
	label.LayoutOrder = p.LayoutOrder or 0
	label.RichText = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = p.MaxSize or 28
	constraint.MinTextSize = 8
	constraint.Parent = label
	if p.Stroke ~= false then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Theme.Colors.Stroke
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label
	end
	label.Parent = parent
	return label
end

export type ButtonProps = {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	MaxText: number?,
	LayoutOrder: number?,
	Radius: number?,
}

function Theme.Button(parent: Instance, text: string, color: Color3, onClick: () -> (), props: ButtonProps?): TextButton
	local p: ButtonProps = props or {}
	local button = Instance.new("TextButton")
	button.Name = p.Name or "Button"
	button.Size = p.Size or UDim2.fromOffset(140, 50)
	button.Position = p.Position or UDim2.new()
	button.AnchorPoint = p.AnchorPoint or Vector2.zero
	button.BackgroundColor3 = color
	button.AutoButtonColor = false
	button.Text = ""
	button.LayoutOrder = p.LayoutOrder or 0
	button.BorderSizePixel = 0
	Theme.Corner(button, p.Radius or 12)
	Theme.Stroke(button, 3)
	Theme.Gradient(button, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	local label = Theme.Text(button, text, { Name = "Label", MaxSize = p.MaxText or 26 })
	label.Size = UDim2.new(1, -12, 1, -8)
	label.Position = UDim2.fromOffset(6, 4)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local pressTween = TweenInfo.new(0.08)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, pressTween, { Scale = 0.93 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, pressTween, { Scale = 1 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, pressTween, { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		Theme.Play("Click", 0.4)
		onClick()
	end)
	button.Parent = parent
	return button
end

function Theme.SetButtonText(button: TextButton, text: string)
	local label = button:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = text
	end
end

function Theme.SetButtonEnabled(button: TextButton, enabled: boolean, color: Color3)
	button.BackgroundColor3 = if enabled then color else Theme.Colors.Disabled
	button.Active = enabled
	button.AutoButtonColor = false
end

export type Window = {
	Frame: Frame,
	Content: Frame,
	Title: TextLabel,
	Close: () -> (),
}

-- Centered window with a title bar and a close button.
function Theme.Window(screen: Instance, title: string, size: Vector2, onClose: () -> ()): Window
	local frame = Theme.Frame({
		Name = title:gsub("%s", "") .. "Window",
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.Background,
		Radius = 18,
		Parent = screen,
	})
	frame.Visible = false
	frame.ZIndex = 10
	Theme.AutoScale(frame)
	local header = Theme.Frame({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 56),
		Color = Theme.Colors.Accent,
		Radius = 18,
		Parent = frame,
	})
	Theme.Gradient(header, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	local titleLabel = Theme.Text(header, title, { MaxSize = 34 })
	titleLabel.Size = UDim2.new(1, -120, 1, -10)
	titleLabel.Position = UDim2.fromOffset(60, 5)
	Theme.Button(header, "X", Theme.Colors.Red, onClose, {
		Size = UDim2.fromOffset(48, 48),
		Position = UDim2.new(1, -6, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		MaxText = 30,
	})
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -24, 1, -76)
	content.Position = UDim2.fromOffset(12, 66)
	content.Parent = frame
	return {
		Frame = frame,
		Content = content,
		Title = titleLabel,
		Close = onClose,
	}
end

-- Vertical scrolling list that grows with its content.
function Theme.Scroll(parent: Instance, size: UDim2?, position: UDim2?): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = size or UDim2.fromScale(1, 1)
	scroll.Position = position or UDim2.new()
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = parent
	return scroll
end

function Theme.Clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Theme.LocalPlayer(): Player
	return Players.LocalPlayer
end

-- Hex string -> Color3
function Theme.Hex(hex: string): Color3
	local clean = hex:gsub("#", "")
	return Color3.fromRGB(
		tonumber(clean:sub(1, 2), 16) or 255,
		tonumber(clean:sub(3, 4), 16) or 255,
		tonumber(clean:sub(5, 6), 16) or 255
	)
end

return Theme
