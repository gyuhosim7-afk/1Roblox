--!strict
-- Keyboard shortcuts for PC players (mobile players use the big on-screen buttons).

local UserInputService = game:GetService("UserInputService")

local UIController = require(script.Parent.UIController)

local InputController = {}

local KEYS: { [Enum.KeyCode]: () -> () } = {
	[Enum.KeyCode.F] = UIController.Bonk,
	[Enum.KeyCode.Q] = UIController.Lock,
	[Enum.KeyCode.G] = function()
		UIController.Open("Shop")
	end,
	[Enum.KeyCode.U] = function()
		UIController.Open("Upgrades")
	end,
	[Enum.KeyCode.B] = function()
		UIController.Open("Slimes")
	end,
}

function InputController.Init() end

function InputController.Start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		local action = KEYS[input.KeyCode]
		if action then
			action()
		end
	end)
end

return InputController
