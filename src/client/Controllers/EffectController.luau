--!strict
-- Visual / physical effects requested by the server: knockback, bonk swings, hatch reveals,
-- coin pops, theft alarms, welcome-back and rebirth messages. VIP chat tags.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local Popups = require(UI.Popups)
local StateController = require(script.Parent.StateController)

local EffectController = {}

local player = Players.LocalPlayer

local function knockback(payload: any)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or type(payload) ~= "table" then
		return
	end
	local direction = if typeof(payload.Direction) == "Vector3" then payload.Direction else Vector3.new(0, 0, 1)
	local speed = tonumber(payload.Speed) or 60
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = direction * speed + Vector3.new(0, 38, 0)
	Theme.Play("Hit", 0.6)
	task.delay(math.clamp(tonumber(payload.Stun) or 0.5, 0.1, 1.5), function()
		if humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

local function bonkSwing(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local swinger = Players:GetPlayerByUserId(payload.UserId)
	local character = swinger and swinger.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local arc = Instance.new("Part")
	arc.Name = "BonkArc"
	arc.Anchored = true
	arc.CanCollide = false
	arc.CanQuery = false
	arc.CanTouch = false
	arc.Material = Enum.Material.Neon
	arc.Color = Color3.fromRGB(255, 220, 120)
	arc.Shape = Enum.PartType.Cylinder
	arc.Size = Vector3.new(0.4, 2, 2)
	arc.Transparency = 0.2
	arc.CFrame = root.CFrame * CFrame.new(0, 0, -2) * CFrame.Angles(0, 0, math.pi / 2)
	arc.Parent = Workspace
	TweenService:Create(arc, TweenInfo.new(0.25), { Size = Vector3.new(0.4, 18, 18), Transparency = 1 }):Play()
	task.delay(0.3, function()
		arc:Destroy()
	end)
	if (root.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude < 80 then
		Theme.Play("Bonk", 0.5)
	end
end

local coinPopOrder = 0
local function coinPop(amount: number)
	local gui = player:FindFirstChild("PlayerGui")
	local screen = gui and gui:FindFirstChild("MainGui")
	if not screen then
		return
	end
	coinPopOrder += 1
	local label = Theme.Text(screen, "+$" .. Format.Number(amount), { MaxSize = 40, Color = Theme.Colors.Green })
	label.Size = UDim2.fromOffset(260, 50)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.42)
	Theme.AutoScale(label)
	TweenService:Create(label, TweenInfo.new(1.1), { Position = UDim2.fromScale(0.5, 0.12), TextTransparency = 1 })
		:Play()
	task.delay(1.2, function()
		label:Destroy()
	end)
	Theme.Play("Collect", 0.5)
end

local function alarm()
	local gui = player:FindFirstChild("PlayerGui")
	local screen = gui and gui:FindFirstChild("MainGui")
	if not screen then
		return
	end
	local flash = Instance.new("Frame")
	flash.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	flash.BackgroundTransparency = 0.6
	flash.Size = UDim2.fromScale(1, 1)
	flash.BorderSizePixel = 0
	flash.ZIndex = 0
	flash.Parent = screen
	TweenService:Create(flash, TweenInfo.new(1), { BackgroundTransparency = 1 }):Play()
	task.delay(1.1, function()
		flash:Destroy()
	end)
	Theme.Play("Steal", 0.8)
end

local HANDLERS: { [string]: (any) -> () } = {
	Knockback = knockback,
	BonkSwing = bonkSwing,
	Hatch = function(payload)
		Popups.Hatch(payload)
	end,
	Collect = function(payload)
		if type(payload) == "table" and type(payload.Amount) == "number" then
			coinPop(payload.Amount)
		end
	end,
	Alarm = function()
		alarm()
	end,
	OfflineEarnings = function(payload)
		if type(payload) == "table" then
			Popups.Message(
				"Welcome back!",
				"Your slimes earned $"
					.. Format.Number(payload.Coins or 0)
					.. " while you were away ("
					.. Format.Duration(payload.Seconds or 0)
					.. ")."
			)
		end
	end,
	Rebirth = function(payload)
		Popups.Message(
			"REBIRTH " .. tostring(payload and payload.Rebirths or ""),
			"You are faster and richer than ever. Run!",
			Theme.Colors.Accent
		)
	end,
}

function EffectController.Init() end

function EffectController.Start()
	StateController.Effect:Connect(function(name: string, payload: any)
		local handler = HANDLERS[name]
		if handler then
			handler(payload)
		end
	end)

	-- VIP chat tag
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		if source then
			local speaker = Players:GetPlayerByUserId(source.UserId)
			if speaker and speaker:GetAttribute("VIP") then
				properties.PrefixText = '<font color="#FFD54F">[VIP]</font> ' .. message.PrefixText
			end
		end
		return properties
	end
end

return EffectController
