--!strict
-- Builds the whole UI and keeps it in sync with the server state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local Hud = require(UI.Hud)
local Toasts = require(UI.Toasts)
local Popups = require(UI.Popups)
local ShopWindow = require(UI.ShopWindow)
local UpgradeWindow = require(UI.UpgradeWindow)
local InventoryWindow = require(UI.InventoryWindow)
local IndexWindow = require(UI.IndexWindow)
local RebirthWindow = require(UI.RebirthWindow)
local TradeWindow = require(UI.TradeWindow)
local StateController = require(script.Parent.StateController)

local UIController = {}

local screen: ScreenGui
local windows: { [string]: any } = {} -- { Window: Theme.Window, Refresh: (state) -> (), ShowTab: ((string) -> ())? }
local openName: string? = nil
local refreshQueued = false
local lastBonk = 0

function UIController.Close()
	if openName then
		local entry = windows[openName]
		if entry then
			entry.Window.Frame.Visible = false
		end
	end
	openName = nil
end

-- keepOpen = true: never toggles an already open window closed (used when a trade starts).
function UIController.Open(name: string, keepOpen: boolean?)
	local entry = windows[name]
	if not entry then
		return
	end
	if openName == name and keepOpen then
		local state = StateController.State
		if state then
			entry.Refresh(state)
		end
		return
	end
	if openName == name then
		UIController.Close()
		return
	end
	UIController.Close()
	openName = name
	if name == "Index" and entry.ShowTab then
		entry.ShowTab("Eggs")
	end
	local state = StateController.State
	if state then
		entry.Refresh(state)
	end
	entry.Window.Frame.Visible = true
end

local function refreshOpenWindow()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.delay(0.15, function()
		refreshQueued = false
		local state = StateController.State
		if openName and state then
			windows[openName].Refresh(state)
		end
	end)
end

function UIController.Bonk()
	local now = os.clock()
	if now - lastBonk < Config.Steal.BonkCooldown then
		return
	end
	lastBonk = now
	task.spawn(StateController.Request, "Bonk")
end

function UIController.BonkFraction(): number
	return math.clamp((os.clock() - lastBonk) / Config.Steal.BonkCooldown, 0, 1)
end

function UIController.Lock()
	task.spawn(StateController.Request, "LockBase")
end

function UIController.Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	screen = Instance.new("ScreenGui")
	screen.Name = "MainGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui

	-- Roblox's chat window opens top-left by default, right over the coin counters: move it down.
	pcall(function()
		local config = game:GetService("TextChatService"):FindFirstChildOfClass("ChatWindowConfiguration")
		if config then
			config.VerticalAlignment = Enum.VerticalAlignment.Bottom
		end
	end)

	local ctx = {
		Close = UIController.Close,
		Open = UIController.Open,
		State = function(): any
			return StateController.State
		end,
		Request = function(action: string, payload: any?)
			task.spawn(StateController.Request, action, payload)
		end,
		ShowRoyalOdds = function()
			local state = StateController.State
			if state then
				Popups.RoyalOdds(state, function(action: string, payload: any?)
					task.spawn(StateController.Request, action, payload)
				end)
			end
		end,
	}

	Hud.Mount(screen, {
		OpenWindow = UIController.Open,
		Bonk = UIController.Bonk,
		Lock = UIController.Lock,
		ClaimGift = function()
			task.spawn(StateController.Request, "ClaimGift")
		end,
		ClaimDaily = function()
			task.spawn(StateController.Request, "ClaimDaily")
		end,
	})
	Toasts.Mount(screen)
	Popups.Mount(screen, Hud.TopStack())
	windows.Shop = ShopWindow.Create(screen, ctx)
	windows.Upgrades = UpgradeWindow.Create(screen, ctx)
	windows.Slimes = InventoryWindow.Create(screen, ctx)
	windows.Index = IndexWindow.Create(screen, ctx)
	windows.Rebirth = RebirthWindow.Create(screen, ctx)
	windows.Trade = TradeWindow.Create(screen, ctx)

	StateController.Notify:Connect(function(text: string, kind: string)
		Toasts.Show(text, kind)
	end)

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(Theme.RefreshScale)
	end
end

local function tutorialText(state: any): string?
	local step = state.Data.TutorialStep
	local steps = Config.Tutorial.Steps
	if step >= 1 and step <= #steps then
		return "TIP: " .. steps[step]
	end
	return nil
end

function UIController.Start()
	local announcedDaily = false
	StateController.StatsChanged:Connect(function(state: any)
		Hud.Update(state)
		if openName and openName ~= "Slimes" and openName ~= "Index" and openName ~= "Trade" then
			refreshOpenWindow()
		end
	end)
	StateController.Changed:Connect(function(state: any)
		Hud.Update(state)
		windows.Trade.OnState(state)
		refreshOpenWindow()
		if not announcedDaily and state.Daily and state.Daily.Available then
			announcedDaily = true
			Toasts.Show("Daily reward ready! Tap 📅 Daily for +" .. state.Daily.Gems .. " gems", "rare")
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local state = StateController.State
			if state then
				local now = StateController.Now()
				Hud.UpdateTimers(state, now)
				Hud.BonkCooldown(UIController.BonkFraction())
				local player = Players.LocalPlayer
				local carrying = player:GetAttribute("CarryingEgg")
				if type(carrying) == "string" and Config.Eggs[carrying] then
					Hud.SetBanner(
						"🥚 Carrying " .. Config.Eggs[carrying].Name .. " - run back to your base!",
						Theme.Colors.Accent
					)
				else
					local tip = tutorialText(state)
					Hud.SetBanner(tip, Theme.Colors.Blue)
				end
				if state.Data.TutorialStep == 5 then
					Hud.FlashButton("Upgrades")
				end
			end
		end
	end)
end

return UIController
