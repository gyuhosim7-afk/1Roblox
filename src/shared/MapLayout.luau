--!strict
-- Pure-number map layout shared by server and client: zone ranges, gates, nests,
-- guard paths, plots and the positions of everything inside a plot.
-- The runway runs along +Z, centered on x = 0. Ground top is at y = 0.

local Config = require(script.Parent.Config)

export type Point = { X: number, Z: number }
export type Guard = {
	Id: string,
	Kind: string, -- "Patrol" | "Sweeper"
	Zone: number,
	X: number,
	Z: number,
	Amplitude: number, -- Patrol: half width of the sweep; Sweeper: arm length
	Period: number,
	Phase: number,
	Radius: number, -- Patrol: ball radius; Sweeper: arm half-thickness
	Direction: number, -- Sweeper rotation direction (1 or -1)
}
export type ZoneLayout = {
	Index: number,
	Id: string,
	StartZ: number,
	EndZ: number,
	GateZ: number,
	Nests: { Point },
	Guards: { Guard },
}
export type PlotLayout = { Index: number, Side: number, X: number, Z: number }

local MapLayout = {}

local map = Config.Map
local HALF_ROAD = map.RoadWidth / 2

-- Positions inside a plot, in plot-local studs. Local -Z faces the road (the entrance).
MapLayout.PlotLocal = {
	Half = map.PlotSize / 2,
	Spawn = { X = 0, Z = -20 },
	CollectPad = { X = 10, Z = -21, Size = 7 },
	LockPad = { X = -12, Z = -21, Size = 7 },
	Incubators = {} :: { Point },
	Pedestals = {} :: { Point },
	SignZ = 26,
}
for i = 1, 8 do
	table.insert(MapLayout.PlotLocal.Incubators, { X = 20, Z = -15 + 5 * (i - 1) })
end
for row = 0, 5 do
	for col = 0, 3 do
		table.insert(MapLayout.PlotLocal.Pedestals, { X = -20 + 7 * col, Z = -12 + 7 * row })
	end
end

-- Zones -----------------------------------------------------------------------
local zones: { ZoneLayout } = {}
do
	local z = map.FirstZoneStart
	for index, def in Config.Zones do
		local startZ = z
		local endZ = startZ + def.Length
		local layout: ZoneLayout = {
			Index = index,
			Id = def.Id,
			StartZ = startZ,
			EndZ = endZ,
			GateZ = startZ - map.GateGap / 2,
			Nests = {},
			Guards = {},
		}

		-- Nests: two columns, spread over the back half of the zone.
		local rows = math.ceil(def.Nests / 2)
		local nestRowsZ = {}
		for n = 1, def.Nests do
			local row = math.ceil(n / 2)
			local side = if n % 2 == 1 then -1 else 1
			local x = side * (10 + (row % 2) * 8)
			local fraction = if rows > 1 then 0.5 + 0.42 * (row - 1) / (rows - 1) else 0.75
			local nz = startZ + def.Length * fraction
			nestRowsZ[row] = nz
			table.insert(layout.Nests, { X = x, Z = nz })
		end

		-- Guards: evenly spread; sweepers are spaced out and kept away from nest rows.
		local total = def.PatrolGuards + def.SweeperGuards
		local sweeperEvery = if def.SweeperGuards > 0 then math.max(1, math.floor(total / def.SweeperGuards)) else 0
		local sweepersPlaced = 0
		for g = 1, total do
			local fraction = 0.16 + 0.8 * (g - 0.5) / total
			local gz = startZ + def.Length * fraction
			local isSweeper = sweeperEvery > 0
				and sweepersPlaced < def.SweeperGuards
				and (g % sweeperEvery == 0 or (total - g) < (def.SweeperGuards - sweepersPlaced))
			local variance = 0.85 + 0.3 * ((g * 37) % 10) / 10
			if isSweeper then
				sweepersPlaced += 1
				for _, rowZ in nestRowsZ do
					if math.abs(gz - rowZ) < HALF_ROAD + 2 then
						gz = if gz < rowZ then rowZ - HALF_ROAD - 2 else rowZ + HALF_ROAD + 2
					end
				end
				gz = math.clamp(gz, startZ + HALF_ROAD, endZ - HALF_ROAD)
				table.insert(layout.Guards, {
					Id = def.Id .. "_S" .. g,
					Kind = "Sweeper",
					Zone = index,
					X = 0,
					Z = gz,
					Amplitude = HALF_ROAD - 2,
					Period = def.GuardPeriod * 1.6 * variance,
					Phase = g * 1.3,
					Radius = 1.6,
					Direction = if g % 2 == 0 then 1 else -1,
				})
			else
				table.insert(layout.Guards, {
					Id = def.Id .. "_P" .. g,
					Kind = "Patrol",
					Zone = index,
					X = 0,
					Z = gz,
					Amplitude = HALF_ROAD - def.GuardRadius - 1,
					Period = def.GuardPeriod * variance,
					Phase = g * 1.7,
					Radius = def.GuardRadius,
					Direction = 1,
				})
			end
		end

		zones[index] = layout
		z = endZ + map.GateGap
	end
end

MapLayout.Zones = zones
MapLayout.RoadEndZ = zones[#zones].EndZ + 60

-- Plots -----------------------------------------------------------------------
local plots: { PlotLayout } = {}
do
	local index = 0
	for _, side in { -1, 1 } do
		for _, pz in map.PlotZ do
			index += 1
			table.insert(plots, { Index = index, Side = side, X = side * map.PlotColumnsX, Z = pz })
		end
	end
end
MapLayout.Plots = plots

local minPlotZ = math.huge
for _, pz in map.PlotZ do
	minPlotZ = math.min(minPlotZ, pz)
end
MapLayout.RoadStartZ = minPlotZ - map.PlotSize / 2 - 24
MapLayout.HomeHalfWidth = map.PlotColumnsX + map.PlotSize / 2 + 8
MapLayout.HalfRoad = HALF_ROAD

-- Plot-local (lx, lz) -> world (x, z)
function MapLayout.PlotToWorld(plot: PlotLayout, lx: number, lz: number): (number, number)
	return plot.X + lz * plot.Side, plot.Z - lx * plot.Side
end

-- World (x, z) -> plot-local (lx, lz)
function MapLayout.WorldToPlot(plot: PlotLayout, x: number, z: number): (number, number)
	return (plot.Z - z) * plot.Side, (x - plot.X) * plot.Side
end

function MapLayout.IsInPlot(plot: PlotLayout, x: number, z: number, margin: number?): boolean
	local lx, lz = MapLayout.WorldToPlot(plot, x, z)
	local half = MapLayout.PlotLocal.Half + (margin or 0)
	return math.abs(lx) <= half and math.abs(lz) <= half
end

function MapLayout.PlotAt(x: number, z: number): PlotLayout?
	for _, plot in plots do
		if MapLayout.IsInPlot(plot, x, z) then
			return plot
		end
	end
	return nil
end

-- Zone index for a z position (0 = home area before the first gate).
function MapLayout.ZoneAtZ(z: number): number
	local found = 0
	for index, zone in zones do
		if z >= zone.GateZ then
			found = index
		end
	end
	return found
end

-- Where a player should stand to just outside a plot's entrance (on the road side).
function MapLayout.PlotEntrance(plot: PlotLayout, offset: number?): (number, number)
	return MapLayout.PlotToWorld(plot, 0, -MapLayout.PlotLocal.Half - (offset or 8))
end

return MapLayout
