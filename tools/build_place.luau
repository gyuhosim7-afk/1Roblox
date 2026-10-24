-- Builds build/StealASlime.rbxl without the rojo binary (it is blocked on some PCs).
-- Starts from the existing place file and copies every script from src/ into it, following
-- default.project.json, so the place always matches the repo. Lighting properties too.
-- Usage: lune run tools/build_place [out.rbxl]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local out = process.args[1] or "build/StealASlime.rbxl"
local project = serde.decode("json", fs.readFile("default.project.json"))
local game = roblox.deserializePlace(fs.readFile("build/StealASlime.rbxl"))

local function className(file: string): (string, string)
	local base = file:gsub("%.luau$", "")
	if base:match("%.server$") then
		return (base:gsub("%.server$", "")), "Script"
	elseif base:match("%.client$") then
		return (base:gsub("%.client$", "")), "LocalScript"
	end
	return base, "ModuleScript"
end

local written = 0
local function syncDir(path: string, parent: any)
	local seen = {}
	for _, entry in fs.readDir(path) do
		local full = path .. "/" .. entry
		if fs.isDir(full) then
			local folder = parent:FindFirstChild(entry)
			if not folder then
				folder = roblox.Instance.new("Folder")
				folder.Name = entry
				folder.Parent = parent
			end
			seen[entry] = true
			syncDir(full, folder)
		elseif entry:match("%.luau$") then
			local name, class = className(entry)
			seen[name] = true
			local script = parent:FindFirstChild(name)
			if script and script.ClassName ~= class then
				script:Destroy()
				script = nil
			end
			if not script then
				script = roblox.Instance.new(class)
				script.Name = name
				script.Parent = parent
			end
			script.Source = (fs.readFile(full):gsub("\r\n", "\n"))
			written += 1
		end
	end
	-- remove scripts that no longer exist in the repo
	for _, child in parent:GetChildren() do
		if not seen[child.Name] and (child:IsA("LuaSourceContainer") or child:IsA("Folder")) then
			child:Destroy()
		end
	end
end

local function apply(def: any, instance: any)
	for key, value in def["$properties"] or {} do
		if type(value) == "number" or type(value) == "boolean" or type(value) == "string" then
			pcall(function()
				instance[key] = value
			end)
		end
	end
	for key, child in def do
		if key:sub(1, 1) ~= "$" then
			local target = instance:FindFirstChild(key)
			if not target then
				local class = child["$className"] or "Folder"
				target = if instance == game then game:GetService(class) else roblox.Instance.new(class)
				target.Name = key
				if instance ~= game then
					target.Parent = instance
				end
			end
			if child["$path"] then
				syncDir(child["$path"], target)
			else
				apply(child, target)
			end
		end
	end
end

apply(project.tree, game)
fs.writeFile(out, roblox.serializePlace(game))
print(("Wrote %s (%d scripts)"):format(out, written))
