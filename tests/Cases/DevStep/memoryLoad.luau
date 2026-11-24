--[[
    Rooms150 is 75 still bots and 74 walkers following no one, each group on
    the same 9 by 9 grid of 30-stud rooms under the height bound, its 20
    walls on the grid's lines, and its pairs counted by room as designed
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local DevShared = require("../../Fixtures/DevShared/Harness")
local Harness = require("../../Fixtures/DevBot/Harness")
local Window = require("../../Fixtures/DevStep/Window")

local LOAD: string = "Rooms150"
local CENTER: any = roblox.Vector3.new(-4000, 1010, 0) -- The rooms' square's center, on the floor's height
local SIDE: number = 270 -- Studs along each of its sides
local ROOMS: number = 9 -- Rooms along each side
local ROOM: number = 30 -- Studs along each side of a room
local THICKNESS: number = 0.4 -- Of each wall
local HEIGHT: number = 11
local TOLERANCE: number = 1e-3 -- Studs, past the float32 rounding Vector3 holds 4,000 studs out to

-- The counts the design gives for the load's ordered pairs, worked from its rooms
local PAIRS: number = 22052 -- 149 bots, each paired with the other 148
local SHARING: number = 148 -- 74 rooms holding a still bot and a walker, each pair counted both ways
local APART: number = 21904
local STILL_APART: number = 5550 -- 75 still bots, each paired with the other 74, no two in one room

-- Whether two numbers agree to the tolerance
local function near(a: number, b: number): boolean
	return math.abs(a - b) <= TOLERANCE
end

-- Whether a value lies on one of a list's lines, to the tolerance
local function onLine(lines: { number }, value: number): boolean
	for _, line: number in lines do
		if near(line, value) then
			return true
		end
	end

	return false
end

return function (): (boolean, string | nil)
	local harness: Harness.Loaded = Harness.load()
	local loaded: any = harness.loaded
	local Config: any = harness.Config
	local Constants: any = harness.Constants
	local Cells: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Bots.Cells)
	local shared: any = DevShared.load().shared -- The dev place's shared table, its standing body's height among it
	local scenario: any = Config.scenarios[LOAD]

	-- 1) The load: still bots with no roam and walkers roaming the same square, each in cells, on no team, following
	-- no one, and the memory run's one load before then after
	if scenario == nil or #scenario.groups ~= 2 then
		return false, `{LOAD} is no scenario of two groups`
	end

	local still: any, walking: any = scenario.groups[1], scenario.groups[2]
	local shape: boolean = still.count == 75
		and walking.count == 74
		and still.kind == nil
		and walking.kind == nil
		and still.cells == true
		and walking.cells == true
		and still.roam == nil
		and walking.roam ~= nil
		and still.team == nil
		and walking.team == nil
		and scenario.follow == false
		and scenario.storm == false
		and scenario.stall == nil

	if not shape then
		return false, `{LOAD} is not 75 still bots and 74 walkers in cells, on no team, following no one`
	end

	for _, area: any in
		{ still.spawn, walking.spawn, walking.roam, { center = scenario.viewer, size = still.spawn.size } }
	do
		if (area.center - CENTER).Magnitude > 0 or area.size.X ~= SIDE or area.size.Y ~= SIDE then
			return false, `One of {LOAD}'s areas is {area.size.X} by {area.size.Y} at {area.center}`
		end
	end

	local memory: any = Config.step.memory
	if memory.scenario ~= LOAD or #memory.order ~= 2 or memory.order[1] ~= false or memory.order[2] ~= true then
		return false, `The memory run's load is {memory.scenario}, its halves not off then on`
	elseif Config.step.walls.thickness ~= THICKNESS or Config.step.walls.height ~= HEIGHT then
		return false, `The walls are {Config.step.walls.thickness} thick and {Config.step.walls.height} high`
	end

	-- A half stands it where its config has it, fixed or not
	local Run: any = Window.run()
	if Run.offset(scenario, true).Magnitude > 0 or Run.offset(scenario, false).Magnitude > 0 then
		return false, `{LOAD}, which follows no one, moved its areas`
	end

	-- 2) Each group's places on one 9 by 9 grid of 30-stud rooms, filled a row at a time, a walker in the room of the
	-- still bot of its place, and no two of a group in one room
	local lowX: number = CENTER.X - SIDE / 2
	local lowZ: number = CENTER.Z - SIDE / 2
	local rooms: { { number } } = {} -- Each bot's room, the still bots' first, by its column and row from 0

	for _, group: any in { still, walking } do
		local taken: { [number]: boolean } = {}

		for place: number = 1, group.count do
			local cell: any = Cells.cell(group.spawn, group.count, place)
			local column: number = (place - 1) % ROOMS
			local row: number = (place - 1) // ROOMS
			local x: number = lowX + (column + 0.5) * ROOM
			local z: number = lowZ + (row + 0.5) * ROOM

			if not near(cell.size.X, ROOM) or not near(cell.size.Y, ROOM) then
				return false, `{group.name}'s room {place} is {cell.size.X} by {cell.size.Y}`
			elseif not near(cell.center.X, x) or not near(cell.center.Z, z) or cell.center.Y ~= CENTER.Y then
				return false, `{group.name}'s room {place} is at {cell.center}, not column {column} and row {row}`
			elseif taken[row * ROOMS + column] then
				return false, `{group.name} put two bots in room {column}, {row}`
			end

			taken[row * ROOMS + column] = true
			table.insert(rooms, { column, row, group == still and 1 or 0 })
		end
	end

	-- 3) The walls: 10 along Z on the columns' edges, then 10 along X on the rows', each its line's length and one
	-- thickness more, standing on the floor laid a sink under the square's height, the same for either group's count
	local walls: { any } = Cells.walls(still.spawn, still.count)
	local others: { any } = Cells.walls(walking.spawn, walking.count)
	local floor: number = CENTER.Y - Config.spawn.sink
	local xs: { number } = {}
	local zs: { number } = {}

	if #walls ~= 2 * (ROOMS + 1) or #others ~= #walls then
		return false, `The walls are {#walls} for the still bots and {#others} for the walkers, not {2 * (ROOMS + 1)}`
	end

	for index: number, wall: any in walls do
		local along: boolean = index <= ROOMS + 1
		local line: number = index - 1
		local center: any = roblox.Vector3.new(lowX + line * ROOM, floor + HEIGHT / 2, CENTER.Z)
		local size: any = roblox.Vector3.new(THICKNESS, HEIGHT, SIDE + THICKNESS)
		if not along then
			line -= ROOMS + 1
			center = roblox.Vector3.new(CENTER.X, floor + HEIGHT / 2, lowZ + line * ROOM)
			size = roblox.Vector3.new(SIDE + THICKNESS, HEIGHT, THICKNESS)
		end

		local other: any = others[index]
		if (wall.center - center).Magnitude > TOLERANCE or (wall.size - size).Magnitude > TOLERANCE then
			return false, `Wall {index} stands {wall.size} at {wall.center}, not {size} at {center}`
		elseif (other.center - wall.center).Magnitude > 0 or (other.size - wall.size).Magnitude > 0 then
			return false, `Wall {index} differs between the two groups' counts`
		end

		if along then
			table.insert(xs, wall.center.X)
		else
			table.insert(zs, wall.center.Z)
		end
	end

	-- Every room's four edges on a wall's line
	for place: number = 1, still.count do
		local cell: any = Cells.cell(still.spawn, still.count, place)
		local halfX: number, halfZ: number = cell.size.X / 2, cell.size.Y / 2
		local edges: boolean = onLine(xs, cell.center.X - halfX)
			and onLine(xs, cell.center.X + halfX)
			and onLine(zs, cell.center.Z - halfZ)
			and onLine(zs, cell.center.Z + halfZ)

		if not edges then
			return false, `Room {place} at {cell.center} has an edge on no wall`
		end
	end

	-- 4) A standing body on the floor and the walls' tops under the height bound, and the floor laid past the square's
	-- edges inside the play bound
	local standing: number = CENTER.Y + Config.spawn.lift + shared.step.standing
	local top: number = floor + HEIGHT
	local reach: number = math.abs(CENTER.X) + SIDE / 2 + Config.spawn.margin

	if not (standing < Constants.HEIGHT_MAX) or not (top <= Constants.HEIGHT_MAX) then
		return false, `A standing body's top at {standing} or a wall's at {top} passes the bound {Constants.HEIGHT_MAX}`
	elseif reach > Constants.PLAY_BOUND then
		return false, `The rooms' floor reaches {reach} studs from 0, past the bound {Constants.PLAY_BOUND}`
	end

	-- 5) The ordered pairs by room: those that share one, those that don't, and of those the pairs of two still bots
	local ordered: number, sharing: number, stillApart: number = 0, 0, 0
	for first: number, a: { number } in rooms do
		for second: number, b: { number } in rooms do
			if first ~= second then
				ordered += 1

				if a[1] == b[1] and a[2] == b[2] then
					sharing += 1
				elseif a[3] == 1 and b[3] == 1 then
					stillApart += 1
				end
			end
		end
	end

	if ordered ~= PAIRS or sharing ~= SHARING or ordered - sharing ~= APART or stillApart ~= STILL_APART then
		local counts: string = `{ordered} pairs, {sharing} sharing a room, {ordered - sharing} apart`
		return false, `{LOAD} gives {counts} and {stillApart} of two still bots apart`
	end

	return true, nil
end
