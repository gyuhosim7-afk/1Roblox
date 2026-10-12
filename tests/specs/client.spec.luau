-- Runs the real client scripts against the real server in one mock DataModel (remotes bridged),
-- so UI building, state sync and client requests are exercised at runtime.

local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local World = t.World

	local function setup()
		local world = World.new()
		world:StartServer()
		local player = world.AddPlayer(1, "Client")
		world:Advance(0.5)
		world:StartClient(player)
		world:Advance(1)
		local client = world:Find("StarterPlayer/StarterPlayerScripts/Client")
		local s = {
			world = world,
			player = player,
			Config = world:Require("ReplicatedStorage/Shared/Config"),
			PlayerService = world:Require("ServerScriptService/Server/Services/PlayerService"),
			SlimeService = world:Require("ServerScriptService/Server/Services/SlimeService"),
			HatchService = world:Require("ServerScriptService/Server/Services/HatchService"),
			EggService = world:Require("ServerScriptService/Server/Services/EggService"),
			StateController = world:RequireInstance(client.Controllers.StateController),
			UIController = world:RequireInstance(client.Controllers.UIController),
		}
		s.session = s.PlayerService.Get(player)
		s.gui = player.PlayerGui:FindFirstChild("MainGui")
		return s
	end

	local function findText(root, pattern)
		for _, d in root:GetDescendants() do
			if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and type(d.Text) == "string" and d.Text:find(pattern) then
				return d
			end
		end
		return nil
	end

	describe("Client", function()
		it("builds the HUD and shows server state", function()
			local s = setup()
			expect(s.gui ~= nil).toBe(true)
			expect(s.StateController.State ~= nil).toBe(true)
			s.session.Data.Gems = 1234
			s.PlayerService.MarkDirty(s.player, true)
			s.world:Advance(1)
			local gems = s.gui.TopStack.TopBar.Gems.Value
			expect(gems.Text).toBe("1.23K")
			local speed = s.gui.TopStack.TopBar.Speed.Value
			expect(tonumber(speed.Text) ~= nil).toBe(true)
			-- tutorial banner is visible for a new player
			expect(s.gui.TopStack.Banner.Visible).toBe(true)
			expect(findText(s.gui.TopStack.Banner, "steal an egg") ~= nil).toBe(true)
		end)

		it("opens and refreshes every window without errors", function()
			local s = setup()
			s.SlimeService.AddSlime(s.player, "SunnySlime", "Gold")
			s.SlimeService.AddSlime(s.player, "BlueSlime", "Rainbow")
			s.world:Advance(0.5)
			for _, name in { "Shop", "Upgrades", "Slimes", "Index", "Rebirth" } do
				s.UIController.Open(name)
				s.world:Advance(0.4)
				local frame = nil
				for _, child in s.gui:GetChildren() do
					if child.Name:find("Window") and child.Visible then
						frame = child
					end
				end
				expect(frame ~= nil).toBe(true)
			end
			-- index shows every egg with percentages
			s.UIController.Open("Index")
			s.world:Advance(0.4)
			expect(findText(s.gui, "Meadow Egg") ~= nil).toBe(true)
			expect(findText(s.gui, "60%%") ~= nil).toBe(true)
			expect(findText(s.gui, "Probabilities are rounded") ~= nil).toBe(true)
		end)

		it("shows every Royal Egg outcome with odds before buying", function()
			local s = setup()
			s.world:Advance(1.5) -- policy lookup
			local state = s.StateController.State
			expect(state.Restricted).toBe(false)
			local Popups = s.world:RequireInstance(s.world:Find("StarterPlayer/StarterPlayerScripts/Client/UI/Popups"))
			Popups.RoyalOdds(state, function() end)
			local frame = s.gui:FindFirstChild("RoyalOdds")
			expect(frame ~= nil).toBe(true)
			-- Meadow (best zone 1) Rare+: Flower + Sunny
			expect(findText(frame, "Flower Slime") ~= nil).toBe(true)
			expect(findText(frame, "Sunny Slime") ~= nil).toBe(true)
			expect(findText(frame, "Mutations") ~= nil).toBe(true)
			expect(findText(frame, "R%$ 99") ~= nil).toBe(true)
		end)

		it("hides random items in the shop for restricted players", function()
			local world = World.new({ policies = { [2] = { ArePaidRandomItemsRestricted = true } } })
			world:StartServer()
			local player = world.AddPlayer(2, "Restricted")
			world:Advance(0.5)
			world:StartClient(player)
			world:Advance(2)
			local UIController =
				world:RequireInstance(world:Find("StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController"))
			UIController.Open("Shop")
			world:Advance(0.5)
			local gui = player.PlayerGui.MainGui
			expect(findText(gui, "Royal Egg")).toBeNil()
			expect(findText(gui, "Luck Potion")).toBeNil()
			expect(findText(gui, "Speed Potion") ~= nil).toBe(true)
		end)

		it("shows a hatch popup and the nest odds panel", function()
			local s = setup()
			s.SlimeService.AddSlime(s.player, "FairySlime", "None")
			s.world:Advance(0.3)
			expect(s.gui:FindFirstChild("HatchPopup") ~= nil).toBe(true)
			s.world:Advance(5)
			expect(s.gui:FindFirstChild("HatchPopup")).toBeNil()
			-- walk next to a nest
			local nest = s.EggService.GetNests()[1]
			s.player.Character:PivotTo(CFrame.new(nest.Position + Vector3.new(0, 2, 4)))
			s.world:Advance(0.6)
			expect(s.gui:FindFirstChild("NestOdds", true) ~= nil).toBe(true)
			s.player.Character:PivotTo(CFrame.new(0, 3, -200))
			s.world:Advance(0.6)
			expect(s.gui:FindFirstChild("NestOdds", true)).toBeNil()
		end)

		it("sends requests from buttons to the server", function()
			local s = setup()
			s.session.Data.Coins = 1000
			s.PlayerService.MarkDirty(s.player, true)
			s.world:Advance(0.5)
			s.UIController.Open("Upgrades")
			s.world:Advance(0.4)
			local result = s.world:Run(function()
				return s.StateController.Request("BuyUpgrade", "Training")
			end)
			expect(result.ok).toBe(true)
			expect(s.session.Data.TrainingLevel).toBe(1)
			-- the toast for the server message appears
			s.world:Advance(0.2)
			expect(findText(s.gui.Toasts, "Speed Training") ~= nil).toBe(true)
		end)

		it("opens gates locally once the player is fast enough", function()
			local s = setup()
			local gate = nil
			for _, g in s.world.services.CollectionService:GetTagged("SpeedGate") do
				if g:GetAttribute("Zone") == 2 then
					gate = g
				end
			end
			s.world:Advance(1)
			expect(gate.CanCollide).toBe(true)
			s.session.Data.Speed = 150
			s.PlayerService.MarkDirty(s.player, false)
			s.world:Advance(1)
			expect(gate.CanCollide).toBe(false)
		end)

		it("hides the steal prompt on your own incubators and the hatch prompt on others'", function()
			local s = setup()
			s.HatchService.AddEgg(s.player, "Forest")
			s.world:Advance(0.5)
			local PlotService = s.world:Require("ServerScriptService/Server/Services/PlotService")
			local plot = PlotService.Get(s.player)
			local part = plot.Incubators[1].Part
			expect(part.StealPrompt.Enabled).toBe(false)
			expect(part.HatchPrompt.Enabled).toBe(true)
		end)

		it("draws guards that follow the shared clock", function()
			local s = setup()
			local folder = s.world.workspace:FindFirstChild("GuardsLocal")
			expect(folder ~= nil).toBe(true)
			local MapLayout = s.world:Require("ReplicatedStorage/Shared/MapLayout")
			local guard = MapLayout.Zones[1].Guards[1]
			local model = folder:FindFirstChild(guard.Id)
			local camera = s.world.workspace.CurrentCamera
			camera.CFrame = CFrame.new(0, 20, guard.Z - 30)
			s.world:Advance(0.5)
			local GuardMotion = s.world:Require("ReplicatedStorage/Shared/GuardMotion")
			local x = GuardMotion.PatrolPosition(guard, s.world.workspace:GetServerTimeNow())
			expect(math.abs(model.PrimaryPart.Position.X - x)).toBeLessThan(3)
		end)
	end)
end
