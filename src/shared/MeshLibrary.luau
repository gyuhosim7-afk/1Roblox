--!strict
-- AI-generated meshes made for this game (ids in ModelAssets). The server turns each id into a
-- MeshPart template once (AssetService) and keeps them in ReplicatedStorage.MeshTemplates, so the
-- server and every client can clone them. When a template is missing (offline tests, a failed
-- load) builders fall back to their part-built versions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelAssets = require(script.Parent.ModelAssets)

local MeshLibrary = {}

local FOLDER_NAME = "MeshTemplates"

local function folder(): Instance?
	return ReplicatedStorage:FindFirstChild(FOLDER_NAME)
end

-- A fresh copy of the template, or nil when it isn't loaded.
function MeshLibrary.Get(key: string): MeshPart?
	local templates = folder()
	local template = templates and templates:FindFirstChild(key)
	if template and template:IsA("MeshPart") then
		return template:Clone()
	end
	return nil
end

function MeshLibrary.Has(key: string): boolean
	local templates = folder()
	return templates ~= nil and templates:FindFirstChild(key) ~= nil
end

-- Scales a part uniformly so its largest side ratio fits inside `box`.
function MeshLibrary.Fit(part: BasePart, box: Vector3): BasePart
	local size = part.Size
	local factor = math.min(box.X / size.X, box.Y / size.Y, box.Z / size.Z)
	part.Size = size * factor
	return part
end

-- Clone + fit + place so the bottom of the mesh sits on `base` (a CFrame at ground level).
function MeshLibrary.Place(key: string, box: Vector3, base: CFrame, parent: Instance?): MeshPart?
	local part = MeshLibrary.Get(key)
	if not part then
		return nil
	end
	MeshLibrary.Fit(part, box)
	part.Anchored = true
	part.CFrame = base * CFrame.new(0, part.Size.Y / 2, 0)
	if parent then
		part.Parent = parent
	end
	return part
end

-- Server only: create every template. Yields; gives up on an asset after `timeout` seconds.
function MeshLibrary.LoadAll(timeout: number?)
	if folder() then
		return
	end
	local ok, assetService = pcall(function()
		return game:GetService("AssetService")
	end)
	if not ok then
		return
	end
	local templates = Instance.new("Folder")
	templates.Name = FOLDER_NAME
	local pending = 0
	for key, entry in ModelAssets do
		pending += 1
		task.spawn(function()
			local created, part = pcall(function()
				return (assetService :: any):CreateMeshPartAsync(Content.fromUri(entry.Mesh), {
					CollisionFidelity = Enum.CollisionFidelity.Box,
					RenderFidelity = Enum.RenderFidelity.Automatic,
				})
			end)
			if created and part then
				part.Name = key
				part.TextureID = entry.Texture
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = true
				part.Parent = templates
			else
				warn("[MeshLibrary] could not load " .. key .. ": " .. tostring(part))
			end
			pending -= 1
		end)
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < (timeout or 15) do
		task.wait(0.1)
	end
	templates.Parent = ReplicatedStorage
end

return MeshLibrary
