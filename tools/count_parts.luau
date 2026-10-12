-- Builds the server world in the test harness and reports how many parts the map creates.
local World = require("../tests/harness/World")
local world = World.new()
world:StartServer()
local map = world.workspace:FindFirstChild("Map")
local counts = {}
local total = 0
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") then
		total += 1
		local top = d
		while top.Parent and top.Parent ~= map and top.Parent.Parent ~= map:FindFirstChild("Zones") do
			top = top.Parent
		end
		counts[top.Name] = (counts[top.Name] or 0) + 1
	end
end
print("Total parts:", total)
for name, n in counts do
	print(name, n)
end
