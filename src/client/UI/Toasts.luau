--!strict
-- Short messages that slide in at the top of the screen and fade away.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Toasts = {}

local container: Frame? = nil
local COLORS = {
	info = Theme.Colors.Blue,
	success = Theme.Colors.Green,
	error = Theme.Colors.Red,
	warning = Theme.Colors.Accent,
	rare = Theme.Colors.Pink,
}
local MAX_TOASTS = 4

-- Toasts stack up from the bottom-center of the screen, above windows.
function Toasts.Mount(screen: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "Toasts"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(520, 220)
	frame.Position = UDim2.new(0.5, 0, 1, -8)
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.ZIndex = 30
	frame.Parent = screen
	local layout = Theme.List(frame, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	Theme.AutoScale(frame)
	container = frame
end

local order = 0

function Toasts.Show(text: string, kind: string?)
	local parent = container
	if not parent then
		return
	end
	local toasts = {}
	for _, child in parent:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts >= MAX_TOASTS then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
	order += 1
	local toast = Theme.Frame({
		Name = "Toast",
		Size = UDim2.fromOffset(500, 46),
		Color = (COLORS :: any)[kind or "info"] or Theme.Colors.Blue,
		Radius = 14,
		LayoutOrder = order,
		Parent = parent,
	})
	local label = Theme.Text(toast, text, { MaxSize = 22 })
	label.Size = UDim2.new(1, -16, 1, -8)
	label.Position = UDim2.fromOffset(8, 4)
	task.delay(3.2, function()
		if toast.Parent then
			local tween = TweenService:Create(toast, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
			TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
			tween:Play()
			tween.Completed:Wait()
			toast:Destroy()
		end
	end)
end

return Toasts
