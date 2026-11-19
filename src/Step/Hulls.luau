--[[
    The hull tests between bodies, a box swept against the other live hulls,
    a hull where it stands and an oriented box, on the box the hull radius
    gives, and the grid of hull positions a server's world keeps for them
--]]

--!strict
--!native
local Constants = require(script.Parent.Parent.Constants)
local State = require(script.Parent.State)

local REJECT_MARGIN: number = Constants.SKIN -- Studs a test's bounds reach past what it tests, far over rounding
local SLOTS: number = Constants.SLOTS -- The most bodies a grid files, one a slot
local CELL_WIDTHS: number = 1 -- Hull widths a grid cell spans on X and Z, so a hull's own bounds touch 2 or 3 each way
local ACROSS: number = 64 -- Buckets along each axis the cells tile, a power of 2 so a cell's wrap is exact anywhere
local U16_BYTES: number = 2

type Box = State.Box
type Grid = State.Grid
type Settings = State.Settings
type State = State.State
type World = State.World

local Hulls = {}

-- The pair Hulls.overlaps is testing, held here so separates reads it without making a closure
local boxRight: vector = vector.zero
local boxUp: vector = vector.zero
local boxLook: vector = vector.zero
local boxHalf: vector = vector.zero -- Half the box's size along its own axes
local hullHalf: vector = vector.zero -- Half the hull's size along the world's
local offset: vector = vector.zero -- From the box's center to the hull's

--[[
    The height of a body's hull: standing, or crouched for a crouched,
    downed or swimming body
--]]

function Hulls.height(state: State, settings: Settings): number
	if state.posture == "Stand" and state.mode ~= "Swim" then
		return settings.standing
	end

	return settings.crouched
end

-- Whether a body's hull blocks others: live, walking and not downed
local function blocks(other: State, state: State): boolean
	return other ~= state and other.moveMode == "Walk" and other.posture ~= "Downed"
end

--[[
    The shares of a move along one axis at which a box enters and leaves a
    slab of half width extent whose center lies gap away, an empty span when
    the move runs beside the slab and every share when it runs inside it
--]]

function Hulls.slab(gap: number, extent: number, move: number): (number, number)
	if move == 0 then
		if math.abs(gap) < extent then
			return -math.huge, math.huge
		end

		return math.huge, -math.huge
	end

	local near: number = (gap - extent) / move
	local far: number = (gap + extent) / move
	if near > far then
		return far, near
	end

	return near, far
end

-- The bucket a body's cell is filed in, its column and row each wrapped across the buckets
local function bucketOf(grid: Grid, state: State): number
	local at: vector = state.position
	local x: number, z: number = at.x, at.z

	-- A value less itself is 0 only when the value is finite
	if not (x - x == 0 and z - z == 0) then
		error(`The hull grid files a body only at a finite position, and got {at}`)
	end

	local size: number = grid.size

	return (math.floor(x / size) % ACROSS) * ACROSS + math.floor(z / size) % ACROSS
end

-- Files a place at the head of a bucket's list
local function file(grid: Grid, place: number, bucket: number)
	local heads: buffer = grid.heads
	local preceding: buffer = grid.preceding
	local first: number = buffer.readu16(heads, bucket * U16_BYTES)

	buffer.writeu16(grid.following, place * U16_BYTES, first)
	buffer.writeu16(preceding, place * U16_BYTES, 0)
	if first ~= 0 then
		buffer.writeu16(preceding, first * U16_BYTES, place)
	end

	buffer.writeu16(heads, bucket * U16_BYTES, place)
	buffer.writeu16(grid.buckets, place * U16_BYTES, bucket)
end

-- Moves a filed place to the bucket its body's position lies in now, when that is another
local function move(grid: Grid, place: number, state: State)
	local bucket: number = bucketOf(grid, state)
	local filed: number = buffer.readu16(grid.buckets, place * U16_BYTES)
	if bucket == filed then
		return
	end

	local following: buffer = grid.following
	local preceding: buffer = grid.preceding
	local before: number = buffer.readu16(preceding, place * U16_BYTES)
	local after: number = buffer.readu16(following, place * U16_BYTES)

	if before == 0 then
		buffer.writeu16(grid.heads, filed * U16_BYTES, after)
	else
		buffer.writeu16(following, before * U16_BYTES, after)
	end

	if after ~= 0 then
		buffer.writeu16(preceding, after * U16_BYTES, before)
	end

	file(grid, place, bucket)
end

-- Files every body of a list afresh, each by its place in it
local function refile(grid: Grid, bodies: { State })
	local count: number = #bodies
	if not (count <= SLOTS) then
		error(`The hull grid files at most {SLOTS} bodies, and the world's list holds {count}`)
	end

	local places: { [State]: number } = grid.places
	buffer.fill(grid.heads, 0, 0)
	table.clear(places)

	for place: number = 1, count do
		local state: State = bodies[place]
		places[state] = place
		file(grid, place, bucketOf(grid, state))
	end

	grid.bodies = bodies
	grid.count = count
end

--[[
    Gives a world the grid of hull positions its hull tests read in place of
    every body, filed from the world's list now and from each new list
    World.setBodies hands it at the next test
--]]

function Hulls.createGrid(world: World)
	local radius: number = world.settings.radius
	local size: number = CELL_WIDTHS * (radius + radius)
	if not (size > 0 and size < math.huge) then
		error(`A hull grid's cells need a finite hull radius above 0, and got {radius}`)
	end

	local grid: Grid = {
		size = size,
		bodies = world.bodies,
		count = 0,
		places = {},
		heads = buffer.create(ACROSS * ACROSS * U16_BYTES),
		following = buffer.create((SLOTS + 1) * U16_BYTES),
		preceding = buffer.create((SLOTS + 1) * U16_BYTES),
		buckets = buffer.create((SLOTS + 1) * U16_BYTES),
		found = table.create(SLOTS, 0),
	}

	refile(grid, world.bodies)
	world.grid = grid
end

--[[
    Files every body again where its position lies now, for a point after
    which any code may have moved one: a tick stage's start, or a test a
    game's call makes. A world with no grid is left as it is
--]]

function Hulls.refresh(world: World)
	local grid: Grid? = world.grid
	if not grid then
		return
	end

	local bodies: { State } = world.bodies
	if grid.bodies ~= bodies then
		refile(grid, bodies)

		return
	end

	for place: number = 1, grid.count do
		move(grid, place, bodies[place])
	end
end

--[[
    Files one body again where its position lies now, after its step or a
    move outside one. A body the world's list doesn't hold, or a world with
    no grid, is left as it is
--]]

function Hulls.moved(world: World, state: State)
	local grid: Grid? = world.grid
	if not grid then
		return
	end

	if grid.bodies ~= world.bodies then
		refile(grid, world.bodies)

		return
	end

	local place: number? = grid.places[state]
	if place then
		move(grid, place, state)
	end
end

--[[
    The places of the bodies filed in the cells a box on X and Z touches,
    in the grid's found list, and how many. Nil and the list's length for a
    world with no grid or a box over more cells than the list holds bodies,
    a NaN or endless bound among them, so the test walks the whole list
--]]

local function gather(world: World, lowX: number, highX: number, lowZ: number, highZ: number): ({ number }?, number)
	local bodies: { State } = world.bodies
	local grid: Grid? = world.grid
	if not grid then
		return nil, #bodies
	end

	if grid.bodies ~= bodies then
		refile(grid, bodies)
	end

	local size: number = grid.size
	local firstColumn: number = math.floor(lowX / size)
	local firstRow: number = math.floor(lowZ / size)
	local columns: number = math.floor(highX / size) - firstColumn + 1
	local rows: number = math.floor(highZ / size) - firstRow + 1
	if not (columns * rows <= grid.count) then
		return nil, grid.count
	end

	-- Past a full wrap of the buckets every one is already visited, so none is visited twice
	columns = math.min(columns, ACROSS)
	rows = math.min(rows, ACROSS)

	local heads: buffer = grid.heads
	local following: buffer = grid.following
	local found: { number } = grid.found
	local count: number = 0

	for column: number = 0, columns - 1 do
		local start: number = ((firstColumn + column) % ACROSS) * ACROSS

		for row: number = 0, rows - 1 do
			local place: number = buffer.readu16(heads, (start + (firstRow + row) % ACROSS) * U16_BYTES)

			while place ~= 0 do
				count += 1
				found[count] = place
				place = buffer.readu16(following, place * U16_BYTES)
			end
		end
	end

	return found, count
end

--[[
    Sweeps a box from center along direction against the hulls of the other
    live bodies, and gives the distance to the nearest it meets, math.huge
    for none, the normal of the face it meets and that body, the first in
    the world's list of those it meets at that distance. As an engine cast
    ignores a part it starts inside, a hull the box starts in is skipped,
    and a body that walks in no mode meets none
--]]

function Hulls.sweep(
	state: State,
	center: vector,
	size: vector,
	direction: vector,
	world: World
): (number, vector, State?)
	local nearest: number = math.huge
	local normal: vector = vector.zero
	local body: State? = nil
	local bodyPlace: number = 0 -- Its place in the world's list, 0 before any

	local length: number = math.sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
	if state.moveMode ~= "Walk" or length == 0 then
		return nearest, normal, body
	end

	local settings: Settings = world.settings
	local radius: number = settings.radius
	local halfX: number = size.x / 2 + radius
	local halfZ: number = size.z / 2 + radius

	-- Where on X and Z a hull's center may lie to meet the box anywhere along the move, widened by the margin
	local endX: number = center.x + direction.x
	local endZ: number = center.z + direction.z
	local lowX: number = math.min(center.x, endX) - halfX - REJECT_MARGIN
	local highX: number = math.max(center.x, endX) + halfX + REJECT_MARGIN
	local lowZ: number = math.min(center.z, endZ) - halfZ - REJECT_MARGIN
	local highZ: number = math.max(center.z, endZ) + halfZ + REJECT_MARGIN

	local bodies: { State } = world.bodies
	local found: { number }?, count: number = gather(world, lowX, highX, lowZ, highZ)

	for visit: number = 1, count do
		local place: number = visit
		if found then
			place = found[visit]
		end

		local other: State = bodies[place]
		local at: vector = other.position
		if at.x < lowX or at.x > highX or at.z < lowZ or at.z > highZ then
			continue
		end

		if blocks(other, state) then
			local otherHalf: number = Hulls.height(other, settings) / 2

			local enterX: number, exitX: number = Hulls.slab(at.x - center.x, halfX, direction.x)
			local enterY: number, exitY: number =
				Hulls.slab(at.y + otherHalf - center.y, size.y / 2 + otherHalf, direction.y)
			local enterZ: number, exitZ: number = Hulls.slab(at.z - center.z, halfZ, direction.z)
			local enter: number = math.max(enterX, enterY, enterZ)
			local exit: number = math.min(exitX, exitY, exitZ)
			local distance: number = enter * length

			-- A tie goes to the body first in the list, as a walk in the list's order keeps it, whatever order the
			-- cells give
			if
				enter >= 0
				and enter < exit
				and enter <= 1
				and (distance < nearest or (distance == nearest and place < bodyPlace))
			then
				nearest = distance
				body = other
				bodyPlace = place

				-- The face it enters through, which faces against the move on the axis it enters last
				if enter == enterX then
					normal = vector.create(-math.sign(direction.x), 0, 0)
				elseif enter == enterY then
					normal = vector.create(0, -math.sign(direction.y), 0)
				else
					normal = vector.create(0, 0, -math.sign(direction.z))
				end
			end
		end
	end

	return nearest, normal, body
end

--[[
    The hull test where a body stands now: whether its hull overlaps the
    hull of any other live body, touching counting as apart. A body that
    walks in no mode overlaps none
--]]

function Hulls.block(state: State, world: World): boolean
	if state.moveMode ~= "Walk" then
		return false
	end

	local settings: Settings = world.settings
	local reach: number = settings.radius + settings.radius -- Both hulls' half widths
	local feet: vector = state.position
	local top: number = feet.y + Hulls.height(state, settings)

	local span: number = reach + REJECT_MARGIN
	local bodies: { State } = world.bodies
	local found: { number }?, count: number = gather(world, feet.x - span, feet.x + span, feet.z - span, feet.z + span)

	for visit: number = 1, count do
		local place: number = visit
		if found then
			place = found[visit]
		end

		-- The cheap compares first, so a hull apart on X or Z is passed before its mode or posture is read
		local other: State = bodies[place]
		local at: vector = other.position
		if math.abs(at.x - feet.x) >= reach or math.abs(at.z - feet.z) >= reach then
			continue
		end

		if blocks(other, state) then
			local apart: boolean = at.y >= top or feet.y >= at.y + Hulls.height(other, settings)
			if not apart then
				return true
			end
		end
	end

	return false
end

--[[
    Whether the axis lx, ly, lz separates the pair being tested, their
    projections onto it apart or touching. The axis is used as it comes, so
    all three projections share its rounding, and a zero axis separates
    nothing
--]]

local function separates(lx: number, ly: number, lz: number): boolean
	if lx == 0 and ly == 0 and lz == 0 then
		return false
	end

	local boxReach: number = boxHalf.x * math.abs(boxRight.x * lx + boxRight.y * ly + boxRight.z * lz)
		+ boxHalf.y * math.abs(boxUp.x * lx + boxUp.y * ly + boxUp.z * lz)
		+ boxHalf.z * math.abs(boxLook.x * lx + boxLook.y * ly + boxLook.z * lz)
	local hullReach: number = hullHalf.x * math.abs(lx) + hullHalf.y * math.abs(ly) + hullHalf.z * math.abs(lz)

	return math.abs(offset.x * lx + offset.y * ly + offset.z * lz) >= boxReach + hullReach
end

-- Whether an axis of the box crossed with the world's X, Y or Z separates the pair
local function crossSeparates(axis: vector): boolean
	return separates(0, axis.z, -axis.y) or separates(-axis.z, 0, axis.x) or separates(axis.y, -axis.x, 0)
end

--[[
    Whether an oriented box overlaps the hull of any live body that walks,
    a downed one included, touching counting as apart: the separating axis
    test on the world's axes, the box's, and each pair of them crossed
--]]

function Hulls.overlaps(box: Box, world: World): boolean
	local size: vector = box.size
	if not (size.x > 0 and size.y > 0 and size.z > 0) then
		error(`A box needs a size above 0 on every axis, and got {size}`)
	end

	local settings: Settings = world.settings
	local radius: number = settings.radius
	boxRight, boxUp, boxLook = box.right, box.up, box.look
	boxHalf = size / 2

	-- How far the box reaches along each world axis from its center
	local reachX: number = boxHalf.x * math.abs(boxRight.x)
		+ boxHalf.y * math.abs(boxUp.x)
		+ boxHalf.z * math.abs(boxLook.x)
	local reachY: number = boxHalf.x * math.abs(boxRight.y)
		+ boxHalf.y * math.abs(boxUp.y)
		+ boxHalf.z * math.abs(boxLook.y)
	local reachZ: number = boxHalf.x * math.abs(boxRight.z)
		+ boxHalf.y * math.abs(boxUp.z)
		+ boxHalf.z * math.abs(boxLook.z)

	local center: vector = box.center
	local spanX: number = reachX + radius + REJECT_MARGIN
	local spanZ: number = reachZ + radius + REJECT_MARGIN
	local bodies: { State } = world.bodies
	local found: { number }?, count: number =
		gather(world, center.x - spanX, center.x + spanX, center.z - spanZ, center.z + spanZ)

	for visit: number = 1, count do
		local place: number = visit
		if found then
			place = found[visit]
		end

		local other: State = bodies[place]
		if other.moveMode == "Walk" then
			local half: number = Hulls.height(other, settings) / 2
			local at: vector = other.position
			hullHalf = vector.create(radius, half, radius)
			offset = vector.create(at.x, at.y + half, at.z) - center

			-- The world's axes first, then the box's, then each crossed pair
			local apart: boolean = math.abs(offset.x) >= reachX + radius
				or math.abs(offset.y) >= reachY + half
				or math.abs(offset.z) >= reachZ + radius
				or separates(boxRight.x, boxRight.y, boxRight.z)
				or separates(boxUp.x, boxUp.y, boxUp.z)
				or separates(boxLook.x, boxLook.y, boxLook.z)
				or crossSeparates(boxRight)
				or crossSeparates(boxUp)
				or crossSeparates(boxLook)

			if not apart then
				return true
			end
		end
	end

	return false
end

return Hulls
