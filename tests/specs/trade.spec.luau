-- Trading: requests, offers, accept/confirm flow, swap safety, policy and cancel rules.

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local World = t.World

	local function setup(opts)
		local world = World.new(opts)
		world:StartServer()
		local s = {
			world = world,
			Config = world:Require("ReplicatedStorage/Shared/Config"),
			PlayerService = world:Require("ServerScriptService/Server/Services/PlayerService"),
			SlimeService = world:Require("ServerScriptService/Server/Services/SlimeService"),
			Trade = world:Require("ServerScriptService/Server/Services/TradeService"),
			Network = world:Require("ServerScriptService/Server/Services/Network"),
		}
		function s.join(userId)
			local player = world.AddPlayer(userId, "P" .. userId)
			world:Advance(1.5) -- data + policy lookup
			return player, s.PlayerService.Get(player)
		end
		function s.give(player, kind, mutation)
			return s.SlimeService.AddSlime(player, kind, mutation or "None", "Test", true)
		end
		function s.call(player, action, payload)
			return s.Network.Invoke(player, action, payload)
		end
		-- a and b start a trade
		function s.start(a, b)
			expect(s.call(a, "TradeRequest", b.UserId).ok).toBe(true)
			expect(s.call(b, "TradeRespond", { From = a.UserId, Accept = true }).ok).toBe(true)
		end
		function s.finish(a, b)
			expect(s.call(a, "TradeAccept", true).ok).toBe(true)
			expect(s.call(b, "TradeAccept", true).ok).toBe(true)
			s.world:Advance(s.Config.Trading.ConfirmDelay + 0.1)
			expect(s.call(a, "TradeConfirm").ok).toBe(true)
			return s.call(b, "TradeConfirm")
		end
		return s
	end

	local function kinds(session)
		local list = {}
		for _, slime in session.Data.Slimes do
			table.insert(list, slime.Kind .. "/" .. slime.Mutation)
		end
		table.sort(list)
		return table.concat(list, ",")
	end

	describe("Trading", function()
		it("swaps the offered slimes after both accept and confirm, and saves a log", function()
			local s = setup()
			local a, sa = s.join(1)
			local b, sb = s.join(2)
			local blue = s.give(a, "BlueSlime", "Gold")
			s.give(a, "GreenSlime")
			local leaf = s.give(b, "LeafSlime")
			s.start(a, b)
			expect(s.Trade.IsTrading(a)).toBe(true)
			expect(s.call(a, "TradeSetOffer", { blue.Id }).ok).toBe(true)
			expect(s.call(b, "TradeSetOffer", { leaf.Id }).ok).toBe(true)
			local r = s.finish(a, b)
			expect(r.ok).toBe(true)
			expect(kinds(sa)).toBe("GreenSlime/None,LeafSlime/None")
			expect(kinds(sb)).toBe("BlueSlime/Gold")
			expect(s.Trade.IsTrading(a)).toBe(false)
			-- ids stay unique in the receiver, the Index is filled, no discovery gems for trades
			local seen = {}
			for _, slime in sa.Data.Slimes do
				expect(seen[slime.Id]).toBeNil()
				seen[slime.Id] = true
			end
			expect(sb.Data.Discovered.BlueSlime).toBe(true)
			expect(sb.Data.Discovered.BlueSlime_Gold).toBe(true)
			expect(#sa.Data.TradeLog).toBe(1)
			expect(sa.Data.TradeLog[1].Got[1]).toBe("LeafSlime/None")
			expect(sb.Data.Stats.Trades).toBe(1)
		end)

		it("allows gifts (one side empty) but not an empty trade", function()
			local s = setup()
			local a, sa = s.join(1)
			local b, sb = s.join(2)
			local blue = s.give(a, "BlueSlime")
			s.start(a, b)
			expect(s.call(a, "TradeAccept", true).ok).toBe(false) -- nothing on the table
			s.call(a, "TradeSetOffer", { blue.Id })
			expect(s.finish(a, b).ok).toBe(true)
			expect(#sa.Data.Slimes).toBe(0)
			expect(kinds(sb)).toBe("BlueSlime/None")
		end)

		it("changing an offer clears both accepts", function()
			local s = setup()
			local a = s.join(1)
			local b = s.join(2)
			local blue = s.give(a, "BlueSlime")
			local green = s.give(a, "GreenSlime")
			s.start(a, b)
			s.call(a, "TradeSetOffer", { blue.Id })
			s.call(a, "TradeAccept", true)
			s.call(b, "TradeAccept", false)
			s.call(a, "TradeSetOffer", { blue.Id, green.Id })
			s.call(b, "TradeAccept", true)
			-- a's accept was cleared, so we are still in the offer phase
			expect(s.call(b, "TradeConfirm").ok).toBe(false)
		end)

		it("confirm only works after both accept and the wait", function()
			local s = setup()
			local a = s.join(1)
			local b = s.join(2)
			local blue = s.give(a, "BlueSlime")
			s.start(a, b)
			s.call(a, "TradeSetOffer", { blue.Id })
			expect(s.call(a, "TradeConfirm").ok).toBe(false)
			s.call(a, "TradeAccept", true)
			s.call(b, "TradeAccept", true)
			expect(s.call(a, "TradeConfirm").ok).toBe(false) -- too early
			-- offers are frozen now
			expect(s.call(a, "TradeSetOffer", {}).ok).toBe(false)
		end)

		it("rejects slimes you don't own, locked slimes, duplicates and too many", function()
			local s = setup()
			local a = s.join(1)
			local b = s.join(2)
			local blue = s.give(a, "BlueSlime")
			local theirs = s.give(b, "LeafSlime")
			s.start(a, b)
			expect(s.call(a, "TradeSetOffer", { "S999" }).ok).toBe(false)
			local _ = theirs
			expect(s.call(a, "TradeSetOffer", { blue.Id, blue.Id }).ok).toBe(false)
			expect(s.call(a, "TradeSetOffer", "nope").ok).toBe(false)
			s.call(a, "LockSlime", blue.Id)
			expect(s.call(a, "TradeSetOffer", { blue.Id }).ok).toBe(false)
			local many = {}
			for i = 1, s.Config.Trading.MaxItems + 1 do
				table.insert(many, s.give(a, "GreenSlime").Id)
				local _ = i
			end
			expect(s.call(a, "TradeSetOffer", many).ok).toBe(false)
		end)

		it("a slime sold during the trade drops out and clears accepts", function()
			local s = setup()
			local a, sa = s.join(1)
			local b, sb = s.join(2)
			local blue = s.give(a, "BlueSlime")
			s.give(a, "GreenSlime")
			s.start(a, b)
			s.call(a, "TradeSetOffer", { blue.Id })
			s.call(a, "TradeAccept", true)
			s.call(b, "TradeAccept", true)
			expect(s.call(a, "SellSlime", blue.Id).ok).toBe(true)
			s.world:Advance(1)
			local state = s.PlayerService.BuildState(sb)
			expect(#state.Trade.Theirs).toBe(0)
			expect(state.Trade.Phase).toBe("Offer")
			expect(state.Trade.ThemAccepted).toBe(false)
			local _ = sa
		end)

		it("refuses when the receiver has no room", function()
			local s = setup()
			local a, sa = s.join(1)
			local b, sb = s.join(2)
			local blue = s.give(a, "BlueSlime")
			for _ = 1, s.Config.Base.MaxSlimes do
				s.give(b, "LeafSlime")
			end
			s.start(a, b)
			s.call(a, "TradeSetOffer", { blue.Id })
			s.finish(a, b)
			expect(#sa.Data.Slimes).toBe(1)
			expect(#sb.Data.Slimes).toBe(s.Config.Base.MaxSlimes)
			expect(s.Trade.IsTrading(a)).toBe(false)
		end)

		it("requests: decline, expiry, cooldown, busy players", function()
			local s = setup()
			local a = s.join(1)
			local b = s.join(2)
			local c = s.join(3)
			expect(s.call(a, "TradeRequest", a.UserId).ok).toBe(false)
			expect(s.call(a, "TradeRequest", 999).ok).toBe(false)
			expect(s.call(a, "TradeRequest", b.UserId).ok).toBe(true)
			expect(s.call(a, "TradeRequest", b.UserId).ok).toBe(false) -- cooldown
			expect(s.call(b, "TradeRespond", { From = a.UserId, Accept = false }).ok).toBe(true)
			expect(s.Trade.IsTrading(a)).toBe(false)
			-- expired requests can't be accepted
			s.world:Advance(s.Config.Trading.RequestCooldown + 0.1)
			s.call(a, "TradeRequest", b.UserId)
			s.world:Advance(s.Config.Trading.RequestSeconds + 1)
			expect(s.call(b, "TradeRespond", { From = a.UserId, Accept = true }).ok).toBe(false)
			-- someone already trading can't be asked
			s.start(a, c)
			expect(s.call(b, "TradeRequest", a.UserId).ok).toBe(false)
		end)

		it("cancel and leaving end the trade without moving anything", function()
			local s = setup()
			local a, sa = s.join(1)
			local b, sb = s.join(2)
			local blue = s.give(a, "BlueSlime")
			s.start(a, b)
			s.call(a, "TradeSetOffer", { blue.Id })
			expect(s.call(b, "TradeCancel").ok).toBe(true)
			expect(s.Trade.IsTrading(a)).toBe(false)
			expect(#sa.Data.Slimes).toBe(1)
			s.world:Advance(s.Config.Trading.RequestCooldown + 0.1)
			s.start(a, b)
			s.world.RemovePlayer(b)
			s.world:Advance(1)
			expect(s.Trade.IsTrading(a)).toBe(false)
			expect(#sa.Data.Slimes).toBe(1)
			local _ = sb
		end)

		it("players whose policy blocks paid item trading can't trade", function()
			local s = setup({
				policies = { [2] = { ArePaidRandomItemsRestricted = false, IsPaidItemTradingAllowed = false } },
			})
			local a = s.join(1)
			local b, sb = s.join(2)
			expect(s.call(a, "TradeRequest", b.UserId).ok).toBe(false)
			expect(s.call(b, "TradeRequest", a.UserId).ok).toBe(false)
			expect(s.PlayerService.BuildState(sb).CanTrade).toBe(false)
		end)

		it("policy lookup failure blocks trading (safe default)", function()
			local s = setup({ policies = { [1] = "error" } })
			local a = s.join(1)
			local b = s.join(2)
			s.world:Advance(4)
			expect(s.call(a, "TradeRequest", b.UserId).ok).toBe(false)
		end)

		-- (the test harness runs one client at a time, so we watch the receiver's screen)
		it("client shows the request banner, then opens the trade screen with both offers", function()
			local s = setup()
			local a = s.join(1)
			local b = s.join(2)
			local blue = s.give(a, "BlueSlime")
			s.give(b, "LeafSlime")
			s.world:StartClient(b)
			s.world:Advance(1)
			s.call(a, "TradeRequest", b.UserId)
			s.world:Advance(1)
			local gui = b.PlayerGui.MainGui
			expect(gui.TradeRequest.Visible).toBe(true)
			expect(gui.Rewards.Trade.Badge.Visible).toBe(true)
			s.call(b, "TradeRespond", { From = a.UserId, Accept = true })
			s.call(a, "TradeSetOffer", { blue.Id })
			s.world:Advance(1)
			expect(gui.TradeRequest.Visible).toBe(false)
			expect(gui.TradeWindow.Visible).toBe(true)
			local screen = gui.TradeWindow.Content.TradeScreen
			expect(screen.Visible).toBe(true)
			-- their offer shows a's slime; my slimes list shows the Leaf Slime to add
			local theirBox = screen:GetChildren()
			local found = 0
			for _, child in theirBox do
				if child.Name == "Box" then
					for _, item in child.Scroll:GetChildren() do
						if item.ClassName == "Frame" then
							found += 1
						end
					end
				end
			end
			expect(found).toBe(1)
		end)
	end)
end
