--[[
    The spread loads lay 149 and 299 bots on grids of 13 by 12 and 18 by 17
    over the 4,000-stud square, each body in a cell of its own inside it, and
    every point a seeded body spawns at or walks to stays inside its cell
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevBot/Harness")

local SIDE: number = 4000 -- Studs along each side of the spread loads' square
local TOLERANCE: number = 0.002 -- Studs, past the float32 rounding Vector2, Vector3 and vector hold 6,000 studs out to
local SEED: number = 7
local SEED_BOUND: number = 2 ^ 31 - 2 -- The largest seed a body's own generator is drawn, as the bot harness's run
local SPEED: number = 60 -- Studs a second a walker covers
local RATE: number = 20 -- Ticks a second, so a walker's 3 studs a tick never pass a goal inside the 4-stud arrival
local TICKS: number = 200 -- Each walker's, a few goals in the smaller cells
local LOADS: { [string]: number } = { Spread150 = 149, Spread300 = 299 } -- Each spread load's bots
local FOLLOWED: any = roblox.Vector3.new(3834, 0.5, -74) -- Where a run moves the square's center, the plaza spawn

-- A count of bodies and the grid the rule gives it, worked out by hand: the count's square root rounded up across,
-- and the rows it needs
type Layout = { count: number, columns: number, rows: number }

local LAYOUTS: { Layout } = {
	{ count = 1, columns = 1, rows = 1 },
	{ count = 2, columns = 2, rows = 1 },
	{ count = 16, columns = 4, rows = 4 },
	{ count = 149, columns = 13, rows = 12 },
	{ count = 299, columns = 18, rows = 17 },
}

-- Whether a point lies inside an area, to the tolerance
local function inside(area: any, x: number, z: number): boolean
	return math.abs(x - area.center.X) <= area.size.X / 2 + TOLERANCE
		and math.abs(z - area.center.Z) <= area.size.Y / 2 + TOLERANCE
end

-- Whether two cells share more than an edge
local function overlap(a: any, b: any): boolean
	local x: number = (a.size.X + b.size.X) / 2 - math.abs(a.center.X - b.center.X)
	local z: number = (a.size.Y + b.size.Y) / 2 - math.abs(a.center.Z - b.center.Z)

	return x > TOLERANCE and z > TOLERANCE
end

return function (): (boolean, string | nil)
	local harness: Harness.Loaded = Harness.load()
	local loaded: any = harness.loaded
	local Config: any = harness.Config
	local Cells: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Bots.Cells)
	local Command: any = loaded.require(loaded.game:GetService("ReplicatedStorage").Packages.Tread.Codec.Command)
	local bound: number = harness.Constants.PLAY_BOUND
	local origin: any = roblox.Vector3.new(0, 0, 0)

	-- 1) Each spread load is one group of its bots in cells, spawning and roaming the square at 0 around its viewer
	for name: string, count: number in LOADS do
		local scenario: any = Config.scenarios[name]
		local group: any = scenario and scenario.groups[1]
		local square: any = group and group.spawn
		local roam: any = group and group.roam

		local same: boolean = group ~= nil
			and #scenario.groups == 1
			and group.count == count
			and group.kind == nil
			and group.cells == true
			and square.center == origin
			and square.size.X == SIDE
			and square.size.Y == SIDE
			and roam ~= nil
			and roam.center == square.center
			and roam.size == square.size
			and scenario.viewer == square.center
			and scenario.follow == true
			and scenario.storm == false

		if not same then
			return false, `{name} is not {count} bots in cells over the {SIDE}-stud square, following its viewer`
		end
	end

	local spread: any = Config.spread
	local timing: any = spread.timing
	local workers: any = Config.workers.timing
	if table.concat(spread.scenarios, ",") ~= "Spread150,Spread300" then
		return false, `The spread run's loads are {table.concat(spread.scenarios, ",")}`
	elseif
		table.concat(timing.seeds, ",") ~= table.concat(workers.seeds, ",")
		or timing.warmup ~= workers.warmup
		or timing.window ~= workers.window
		or timing.interval ~= workers.interval
	then
		return false, "The spread run's timing is not the workers run's"
	end

	-- 2) Over the square at 0 and where a run moves it, each layout's cells, then each body's spawn and walk in its own
	local square: any = Config.scenarios.Spread150.groups[1].spawn
	local areas: { any } = { square, { center = square.center + FOLLOWED, size = square.size } }
	local run: any = harness.Seeded.new(SEED)
	local gait: any = { speed = SPEED, rate = RATE, sprint = false, crouch = false, long = false }
	local step: number = SPEED / RATE

	for _, area: any in areas do
		for _, layout: Layout in LAYOUTS do
			local label: string = `{layout.count} bodies over the square at {area.center}`
			local width: number = SIDE / layout.columns
			local depth: number = SIDE / layout.rows
			local lowX: number = area.center.X - SIDE / 2
			local lowZ: number = area.center.Z - SIDE / 2
			local cells: { any } = {}

			-- Each place's cell is its column and row of the grid, filled a row at a time from the low corner
			for place: number = 1, layout.count do
				local cell: any = Cells.cell(area, layout.count, place)
				local column: number = (place - 1) % layout.columns
				local row: number = (place - 1) // layout.columns
				local offX: number = cell.center.X - cell.size.X / 2 - (lowX + column * width)
				local offZ: number = cell.center.Z - cell.size.Y / 2 - (lowZ + row * depth)
				local reach: number =
					math.max(math.abs(cell.center.X) + cell.size.X / 2, math.abs(cell.center.Z) + cell.size.Y / 2)

				if math.abs(cell.size.X - width) > TOLERANCE or math.abs(cell.size.Y - depth) > TOLERANCE then
					return false, `{label}: cell {place} is {cell.size.X} by {cell.size.Y}, not {width} by {depth}`
				elseif math.abs(offX) > TOLERANCE or math.abs(offZ) > TOLERANCE or cell.center.Y ~= area.center.Y then
					return false, `{label}: cell {place} sits at {cell.center}, not column {column} and row {row}`
				elseif
					not inside(area, cell.center.X - cell.size.X / 2, cell.center.Z - cell.size.Y / 2)
					or not inside(area, cell.center.X + cell.size.X / 2, cell.center.Z + cell.size.Y / 2)
				then
					return false, `{label}: cell {place} at {cell.center} reaches past the area`
				elseif reach > bound then
					return false, `{label}: cell {place} reaches {reach} studs from 0, past the wire's bound {bound}`
				end

				cells[place] = cell
			end

			-- No two places share a cell, or any part of one
			for first: number = 1, #cells do
				for second: number = first + 1, #cells do
					if overlap(cells[first], cells[second]) then
						return false, `{label}: cells {first} and {second} overlap`
					end
				end
			end

			-- Each body draws its spawn as a spawn's first try does, then walks its seeded goals, all inside its cell
			for place: number, cell: any in cells do
				local own: any = harness.Seeded.new(run:integer(1, SEED_BOUND))
				local x: number = cell.center.X + own:number(-cell.size.X / 2, cell.size.X / 2)
				local z: number = cell.center.Z + own:number(-cell.size.Y / 2, cell.size.Y / 2)
				local position: vector = vector.create(x, cell.center.Y, z)
				local steer: any = harness.Programs.roam(cell, own, gait)
				local command: any = Command.new()

				for tick: number = 1, TICKS do
					if not inside(cell, position.x, position.z) then
						return false, `{label}: body {place} stood at {position} on tick {tick}, outside its cell`
					end

					steer(command, tick, position)
					position += vector.create(-math.sin(command.yaw) * step, 0, -math.cos(command.yaw) * step)
				end
			end
		end
	end

	return true, nil
end
