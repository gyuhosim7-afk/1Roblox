-- Writes sourcemap.json like `rojo sourcemap` does, for PCs where the rojo binary can't run.
-- Usage: lune run tools/sourcemap [out.json]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local out = process.args[1] or "sourcemap.json"
local project = serde.decode("json", fs.readFile("default.project.json"))

local function scriptNode(name: string, path: string)
	local className = "ModuleScript"
	local base = name:gsub("%.luau$", "")
	if base:match("%.server$") then
		className = "Script"
		base = base:gsub("%.server$", "")
	elseif base:match("%.client$") then
		className = "LocalScript"
		base = base:gsub("%.client$", "")
	end
	return { name = base, className = className, filePaths = { path } }
end

local function dirNode(name: string, path: string)
	local node = { name = name, className = "Folder", children = {} }
	local entries = fs.readDir(path)
	table.sort(entries)
	for _, entry in entries do
		local full = path .. "/" .. entry
		if fs.isDir(full) then
			table.insert(node.children, dirNode(entry, full))
		elseif entry:match("%.luau$") then
			table.insert(node.children, scriptNode(entry, full))
		end
	end
	return node
end

local function treeNode(name: string, def: any)
	if def["$path"] then
		local path = def["$path"]
		if fs.isDir(path) then
			return dirNode(name, path)
		end
		return scriptNode(name, path)
	end
	local node = { name = name, className = def["$className"] or "Folder", children = {} }
	local keys = {}
	for key in def do
		if key:sub(1, 1) ~= "$" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	for _, key in keys do
		table.insert(node.children, treeNode(key, def[key]))
	end
	return node
end

fs.writeFile(out, serde.encode("json", treeNode(project.name, project.tree)))
