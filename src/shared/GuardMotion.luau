--!strict
-- Deterministic guard movement from the shared server clock (workspace:GetServerTimeNow()).
-- The client draws guards with these functions; the server uses the same math for hit tests,
-- so guards never need to replicate positions over the network.

local MapLayout = require(script.Parent.MapLayout)

local GuardMotion = {}

local TAU = math.pi * 2

-- Patrol: ball moving left/right across the road. Returns x, z.
function GuardMotion.PatrolPosition(guard: MapLayout.Guard, t: number): (number, number)
	local x = guard.X + guard.Amplitude * math.sin(TAU * t / guard.Period + guard.Phase)
	return x, guard.Z
end

-- Sweeper: arm rotating around (X, Z). Returns the angle in radians.
function GuardMotion.SweeperAngle(guard: MapLayout.Guard, t: number): number
	return guard.Direction * TAU * t / guard.Period + guard.Phase
end

-- Distance from point (px, pz) to the segment (ax, az)-(bx, bz).
local function segmentDistance(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local lengthSq = dx * dx + dz * dz
	local u = if lengthSq > 0 then math.clamp(((px - ax) * dx + (pz - az) * dz) / lengthSq, 0, 1) else 0
	local cx, cz = ax + u * dx, az + u * dz
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

-- Sweeper arm endpoints (it spans both sides of the pivot).
function GuardMotion.SweeperEnds(guard: MapLayout.Guard, t: number): (number, number, number, number)
	local angle = GuardMotion.SweeperAngle(guard, t)
	local dx, dz = math.cos(angle) * guard.Amplitude, math.sin(angle) * guard.Amplitude
	return guard.X - dx, guard.Z - dz, guard.X + dx, guard.Z + dz
end

-- True if a player standing at (px, pz) touches the guard at time t.
-- playerRadius approximates the character's half width.
function GuardMotion.Hits(guard: MapLayout.Guard, t: number, px: number, pz: number, playerRadius: number?): boolean
	local pr = playerRadius or 1.5
	if guard.Kind == "Patrol" then
		local gx, gz = GuardMotion.PatrolPosition(guard, t)
		local dx, dz = px - gx, pz - gz
		return dx * dx + dz * dz <= (guard.Radius + pr) ^ 2
	end
	local ax, az, bx, bz = GuardMotion.SweeperEnds(guard, t)
	return segmentDistance(px, pz, ax, az, bx, bz) <= guard.Radius + pr
end

return GuardMotion
