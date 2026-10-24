-- Renders the real client UI (built inside the test harness) to an HTML file using a small
-- re-implementation of Roblox GUI layout (UDim2, AnchorPoint, UIScale, list/grid layouts).
-- Usage: lune run tools/ui_preview <width> <height> <scene> <out.html>
-- Scenes: hud, shop, upgrades, slimes, index, rebirth, royal, hatch, nest
-- Then: node tools/screenshot.js <out.html> <out.png> <width> <height>

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local World = require("../tests/harness/World")

local width = tonumber(process.args[1]) or 1280
local height = tonumber(process.args[2]) or 720
local scene = process.args[3] or "hud"
local outPath = process.args[4] or "build/ui-preview.html"
local TOP_INSET = 36

local world = World.new()
world.workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(width, height)
world:StartServer()
local player = world.AddPlayer(1, "Preview")
world:Advance(0.5)
local PlayerService = world:Require("ServerScriptService/Server/Services/PlayerService")
local SlimeService = world:Require("ServerScriptService/Server/Services/SlimeService")
local HatchService = world:Require("ServerScriptService/Server/Services/HatchService")
local BoostService = world:Require("ServerScriptService/Server/Services/BoostService")
local session = PlayerService.Get(player)
session.Data.Coins = 1234567
session.Data.Gems = 345
session.Data.Speed = 2345
session.Data.TrainingLevel = 12
session.Data.BestZone = 4
session.Data.Stats.Joins = 3
for _, kind in
	{ "SunnySlime", "FairySlime", "LeafSlime", "BlueSlime", "PinkSlime", "SandSlime", "OwlSlime", "TreantSlime" }
do
	SlimeService.AddSlime(
		player,
		kind,
		if kind == "OwlSlime" then "Gold" elseif kind == "BlueSlime" then "Rainbow" else "None"
	)
end
HatchService.AddEgg(player, "Forest")
BoostService.AddPotion(player, "Luck", 600)
world:StartClient(player)
world:Advance(6) -- let hatch popups pass
local client = world:Find("StarterPlayer/StarterPlayerScripts/Client")
local UIController = world:RequireInstance(client.Controllers.UIController)
local StateController = world:RequireInstance(client.Controllers.StateController)
local Popups = world:RequireInstance(client.UI.Popups)
local EggService = world:Require("ServerScriptService/Server/Services/EggService")

local windowNames = { shop = "Shop", upgrades = "Upgrades", slimes = "Slimes", index = "Index", rebirth = "Rebirth" }
if windowNames[scene] then
	UIController.Open(windowNames[scene])
	world:Advance(0.5)
elseif scene == "royal" then
	Popups.RoyalOdds(StateController.State, function() end)
elseif scene == "hatch" then
	SlimeService.AddSlime(player, "CrystalTitanSlime", "Gold")
	world:Advance(0.3)
elseif scene == "nest" then
	local nest = EggService.GetNests()[1]
	player.Character:PivotTo(roblox.CFrame.new(nest.Position + roblox.Vector3.new(0, 2, 4)))
	EggService.TryTakeNestEgg(player, nest)
	world:Advance(0.8)
end
world:Advance(0.3)

local gui = player.PlayerGui:FindFirstChild("MainGui")

-- Layout ------------------------------------------------------------------------------
local out = {}
local function emit(s)
	table.insert(out, s)
end

local function css(c, transparency)
	if not c then
		return "transparent"
	end
	return string.format(
		"rgba(%d,%d,%d,%.3f)",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5),
		1 - (transparency or 0)
	)
end

local function escape(text)
	text = tostring(text or "")
	text = text:gsub("&", "&amp;")
		:gsub("<font[^>]*>", "")
		:gsub("</font>", "")
		:gsub("<", "&lt;")
		:gsub(">", "&gt;")
		:gsub("\n", "<br>")
	return text
end

local function isGui(inst)
	local c = inst.ClassName
	return c == "Frame"
		or c == "TextLabel"
		or c == "TextButton"
		or c == "ScrollingFrame"
		or c == "ImageLabel"
		or c == "ImageButton"
		or c == "ViewportFrame"
		or c == "TextBox"
end

local function child(inst, class)
	return inst:FindFirstChildOfClass(class)
end

local function udim(u, parentLen, pixelScale)
	return u.Scale * parentLen + u.Offset * pixelScale
end

local render

local function layoutChildren(inst, rect, pixelScale, depth)
	local kids = {}
	for _, c in inst:GetChildren() do
		if isGui(c) and c.Visible ~= false then
			table.insert(kids, c)
		end
	end
	-- paint order: ZIndex, then creation order (stable)
	for i, c in kids do
		rawset(c, "__order", i)
	end
	local list = child(inst, "UIListLayout")
	local grid = child(inst, "UIGridLayout")
	local padding = child(inst, "UIPadding")
	local inner = { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
	if padding then
		local l = udim(padding.PaddingLeft, rect.w, pixelScale)
		local t = udim(padding.PaddingTop, rect.h, pixelScale)
		inner = {
			x = rect.x + l,
			y = rect.y + t,
			w = rect.w - l - udim(padding.PaddingRight, rect.w, pixelScale),
			h = rect.h - t - udim(padding.PaddingBottom, rect.h, pixelScale),
		}
	end
	if list or grid then
		table.sort(kids, function(a, b)
			if (a.LayoutOrder or 0) ~= (b.LayoutOrder or 0) then
				return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
			end
			return rawget(a, "__order") < rawget(b, "__order")
		end)
	else
		table.sort(kids, function(a, b)
			if (a.ZIndex or 1) ~= (b.ZIndex or 1) then
				return (a.ZIndex or 1) < (b.ZIndex or 1)
			end
			return rawget(a, "__order") < rawget(b, "__order")
		end)
	end
	if grid then
		local cw = udim(grid.CellSize.X, inner.w, pixelScale)
		local ch = udim(grid.CellSize.Y, inner.h, pixelScale)
		local px = udim(grid.CellPadding.X, inner.w, pixelScale)
		local py = udim(grid.CellPadding.Y, inner.h, pixelScale)
		local perRow = math.max(1, math.floor((inner.w + px) / (cw + px)))
		for i, c in kids do
			local col = (i - 1) % perRow
			local row = (i - 1) // perRow
			render(
				c,
				{ x = inner.x + col * (cw + px), y = inner.y + row * (ch + py), w = cw, h = ch },
				pixelScale,
				depth + 1,
				true
			)
		end
		return
	end
	if list then
		local horizontal = list.FillDirection == roblox.Enum.FillDirection.Horizontal
		local pad = udim(list.Padding, if horizontal then inner.w else inner.h, pixelScale)
		local sizes = {}
		local total = 0
		for i, c in kids do
			local s = c.Size
			local w = udim(s.X, inner.w, pixelScale)
			local h = udim(s.Y, inner.h, pixelScale)
			local scale = child(c, "UIScale")
			if scale then
				w *= scale.Scale
				h *= scale.Scale
			end
			sizes[i] = { w = w, h = h }
			total += (if horizontal then w else h) + (if i > 1 then pad else 0)
		end
		local cursor
		if horizontal then
			local align = list.HorizontalAlignment
			cursor = inner.x
			if align == roblox.Enum.HorizontalAlignment.Center then
				cursor = inner.x + (inner.w - total) / 2
			elseif align == roblox.Enum.HorizontalAlignment.Right then
				cursor = inner.x + inner.w - total
			end
		else
			cursor = inner.y
		end
		for i, c in kids do
			local s = sizes[i]
			local r
			if horizontal then
				local y = inner.y
				if list.VerticalAlignment == roblox.Enum.VerticalAlignment.Center then
					y = inner.y + (inner.h - s.h) / 2
				end
				r = { x = cursor, y = y, w = s.w, h = s.h }
				cursor += s.w + pad
			else
				local x = inner.x
				local align = list.HorizontalAlignment
				if align == roblox.Enum.HorizontalAlignment.Center then
					x = inner.x + (inner.w - s.w) / 2
				elseif align == roblox.Enum.HorizontalAlignment.Right then
					x = inner.x + inner.w - s.w
				end
				r = { x = x, y = cursor, w = s.w, h = s.h }
				cursor += s.h + pad
			end
			render(c, r, pixelScale, depth + 1, true)
		end
		return
	end
	for _, c in kids do
		render(c, inner, pixelScale, depth + 1, false)
	end
end

render = function(inst, parentRect, parentPixelScale, depth, placed)
	local rect
	local scaleObj = child(inst, "UIScale")
	local k = if scaleObj then scaleObj.Scale else 1
	if placed then
		rect = parentRect
	else
		local w = udim(inst.Size.X, parentRect.w, parentPixelScale) * k
		local h = udim(inst.Size.Y, parentRect.h, parentPixelScale) * k
		local anchor = inst.AnchorPoint or roblox.Vector2.new(0, 0)
		local x = parentRect.x + udim(inst.Position.X, parentRect.w, parentPixelScale) - anchor.X * w
		local y = parentRect.y + udim(inst.Position.Y, parentRect.h, parentPixelScale) - anchor.Y * h
		rect = { x = x, y = y, w = w, h = h }
	end
	local pixelScale = parentPixelScale * k
	local styles = {
		string.format("left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx", rect.x, rect.y, rect.w, rect.h),
	}
	local bgT = inst.BackgroundTransparency or 0
	if bgT < 1 then
		table.insert(styles, "background:" .. css(inst.BackgroundColor3, bgT))
		local gradient = child(inst, "UIGradient")
		if gradient and inst.ClassName == "TextButton" then
			table.insert(styles, "background-image:linear-gradient(rgba(255,255,255,0.0),rgba(0,0,0,0.25))")
		end
	end
	local corner = child(inst, "UICorner")
	if corner then
		local r = corner.CornerRadius.Scale * math.min(rect.w, rect.h) + corner.CornerRadius.Offset * pixelScale
		table.insert(styles, string.format("border-radius:%.1fpx", r))
	end
	local stroke = child(inst, "UIStroke")
	if stroke and inst.ClassName ~= "TextLabel" then
		table.insert(
			styles,
			string.format(
				"box-shadow:0 0 0 %.1fpx %s",
				stroke.Thickness * pixelScale,
				css(stroke.Color, stroke.Transparency)
			)
		)
	end
	if inst.ClassName == "ScrollingFrame" then
		table.insert(styles, "overflow:hidden")
	end
	local text = ""
	local attrs = ""
	if (inst.ClassName == "TextLabel" or inst.ClassName == "TextButton") and inst.Text and inst.Text ~= "" then
		local constraint = child(inst, "UITextSizeConstraint")
		local maxSize = (if constraint then constraint.MaxTextSize else 100) * pixelScale
		local align = "center"
		if inst.TextXAlignment == roblox.Enum.TextXAlignment.Left then
			align = "left"
		elseif inst.TextXAlignment == roblox.Enum.TextXAlignment.Right then
			align = "right"
		end
		table.insert(styles, "color:" .. css(inst.TextColor3, inst.TextTransparency))
		table.insert(
			styles,
			"text-align:"
				.. align
				.. ";justify-content:"
				.. (if align == "left" then "flex-start" elseif align == "right" then "flex-end" else "center")
		)
		attrs = string.format(' data-max="%.1f" class="t"', maxSize)
		text = "<span>" .. escape(inst.Text) .. "</span>"
	end
	if inst.ClassName == "ViewportFrame" then
		table.insert(styles, "background:radial-gradient(circle,#ffffff22,#00000000);")
		text = "<span style='color:#aaa'>[3D slime]</span>"
		attrs = ' class="t" data-max="16"'
	end
	emit(string.format('<div%s style="%s" title="%s">%s', attrs, table.concat(styles, ";"), inst.Name, text))
	if inst.ClassName == "ScrollingFrame" then
		emit("</div>")
		-- children positioned in page space but clipped: render inside a clip box
		emit(
			string.format(
				'<div style="left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;overflow:hidden">',
				rect.x,
				rect.y,
				rect.w,
				rect.h
			)
		)
		layoutChildren(inst, { x = 0, y = 0, w = rect.w - 8 * pixelScale, h = 100000 }, pixelScale, depth)
		emit("</div>")
		return
	end
	emit("</div>")
	layoutChildren(inst, rect, pixelScale, depth)
end

emit([[<!doctype html><html><head><meta charset="utf-8"><style>
body{margin:0;width:]] .. width .. [[px;height:]] .. height .. [[px;position:relative;overflow:hidden;
background:linear-gradient(#87b9e8,#bfe3a6 55%,#7ccb5b 56%);font-family:"Arial Rounded MT Bold","Nunito","DejaVu Sans",sans-serif;font-weight:800}
div{position:absolute;box-sizing:border-box}
.t{display:flex;align-items:center;overflow:hidden;line-height:1.05;-webkit-text-stroke:0.6px #10101a;paint-order:stroke fill}
.t span{display:block;width:100%}
.topbar{left:0;top:0;width:100%;height:]] .. TOP_INSET .. [[px;background:rgba(0,0,0,0.25)}
.touch{border-radius:50%;background:rgba(255,255,255,0.18);border:2px solid rgba(255,255,255,0.5)}
</style></head><body><div class="topbar"></div>]])

local root = { x = 0, y = TOP_INSET, w = width, h = height - TOP_INSET }
layoutChildren(gui, root, 1, 0)

-- Mobile touch controls (thumbstick + jump) to spot overlaps
if width <= 1000 then
	emit(
		string.format(
			"<div class='touch' style='left:%dpx;top:%dpx;width:%dpx;height:%dpx;z-index:999'></div>",
			30,
			height - 170,
			140,
			140
		)
	)
	emit(
		string.format(
			"<div class='touch' style='left:%dpx;top:%dpx;width:%dpx;height:%dpx;z-index:999'></div>",
			width - 120,
			height - 120,
			90,
			90
		)
	)
end

emit([[<script>
for (const el of document.querySelectorAll('.t')) {
  const span = el.querySelector('span'); if (!span) continue;
  let size = parseFloat(el.dataset.max) || 40;
  const h = el.clientHeight, w = el.clientWidth;
  size = Math.min(size, h);
  span.style.fontSize = size + 'px';
  while (size > 6 && (span.scrollHeight > h + 1 || span.scrollWidth > w + 1)) { size -= 1; span.style.fontSize = size + 'px'; }
}
</script></body></html>]])

fs.writeFile(outPath, table.concat(out, "\n"))
print("wrote " .. outPath)
