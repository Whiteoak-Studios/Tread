--[[
    Moving platforms in the step: registering one on a world, its calls,
    where its path puts it on a tick, the world's casts wrapped to meet its
    boxes there, and a rider's carry and boarding
--]]

--!strict
--!native
local Constants = require(script.Parent.Parent.Constants)
local Engine = require(script.Parent.Engine)
local Hulls = require(script.Parent.Hulls)
local Math = require(script.Parent.Math)
local Sequence = require(script.Parent.Parent.Codec.Sequence)
local State = require(script.Parent.State)

local MAX_PLATFORMS: number = Constants.MAX_PLATFORMS
local SKIN: number = Constants.SKIN
local QUANTUM: number = Constants.POSITION_QUANTUM
local SKINS: number = 2 * Constants.SKIN -- How far under the feet a box's top may sit to board it, and under a rest
local WRAP: number = 2 ^ 16 -- The ticks a u16 holds, which world.tick wraps in
local NONE: number = math.huge -- An entry's tick before its position is first found, which no tick reaches
local MATERIAL: Enum.Material = Enum.Material.Plastic -- A platform hit's material

type Collision = State.Collision
type Hit = State.Hit
type Platform = State.Platform
type PlatformBox = State.PlatformBox
type PlatformEntry = State.PlatformEntry
type Settings = State.Settings
type State = State.State
type World = State.World

local Platforms = {}

-- The nearest platform box the last meet found: its share of the move, its platform's id, 0 for none, the normal and
-- the box's top
local foundShare: number = math.huge
local foundId: number = 0
local foundNormal: vector = vector.zero
local foundTop: number = 0

--[[
    The world's tick unwrapped against its clock, the tick a platform's
    path is evaluated at
--]]

function Platforms.tick(world: World): number
	local clock: number = world.clock

	return clock + Sequence.difference(world.tick, clock % WRAP)
end

-- The call a path runs from on a tick: the latest at or before it, else the one before that, nil before either
local function calledFor(entry: PlatformEntry, tick: number): number?
	local latest: number? = entry.calledAt
	if latest ~= nil and latest <= tick then
		return latest
	end

	local before: number? = entry.calledBefore
	if before ~= nil and before <= tick then
		return before
	end

	return nil
end

-- Where a platform's path puts it on a whole tick, on the 1/512 quantum
local function evaluate(entry: PlatformEntry, tick: number): vector
	local given: Vector3 = entry._path(tick, calledFor(entry, tick))
	if typeof(given) ~= "Vector3" then
		error(`Platform {entry.id}'s path must give a Vector3, and gave a {typeof(given)} on tick {tick}`)
	end

	-- A value less itself is 0 only when the value is finite
	local x: number, y: number, z: number = given.X, given.Y, given.Z
	if not (x - x == 0 and y - y == 0 and z - z == 0) then
		error(`Platform {entry.id}'s path must give a finite position, and gave {given} on tick {tick}`)
	end

	return vector.create(Math.quantize(x), Math.quantize(y), Math.quantize(z))
end

-- Where a platform stands on the tick the step runs, kept on its entry so every cast that tick finds it once
local function place(entry: PlatformEntry, tick: number): vector
	if entry._tick ~= tick then
		entry._position = evaluate(entry, tick)
		entry._tick = tick
	end

	return entry._position
end

-- Where a platform stands on any whole tick, from what its entry keeps when that is the tick
local function placeOn(entry: PlatformEntry, tick: number): vector
	if entry._tick == tick then
		return entry._position
	end

	return evaluate(entry, tick)
end

-- A platform's velocity on a tick: its move since the tick before, a second's worth
local function velocityOf(entry: PlatformEntry, tick: number, delta: number): vector
	return (place(entry, tick) - placeOn(entry, tick - 1)) / delta
end

--[[
    Sweeps a box of half size half from center along direction against
    every platform's boxes on the tick but skip's, 0 skipping none, and
    keeps the nearest it enters: as an engine cast ignores a part it starts
    inside, a box it starts in is passed by. A tie goes to the lower id,
    and within a platform to its first box, so every realm finds the same
--]]

local function meet(world: World, tick: number, center: vector, half: vector, direction: vector, skip: number)
	foundShare = math.huge
	foundId = 0

	-- Whiteoak TODO: every cast tests every box of every platform; a grid of the boxes, rebuilt each tick, narrows it
	-- to the nearby ones once a game with many platforms shows what the walk costs
	for id: number, entry: PlatformEntry in world.platforms do
		if id ~= skip then
			local position: vector = place(entry, tick)

			for _, box: PlatformBox in entry._boxes do
				local gap: vector = position + box.center - center
				local extent: vector = box.half + half
				local enterX: number, exitX: number = Hulls.slab(gap.x, extent.x, direction.x)
				local enterY: number, exitY: number = Hulls.slab(gap.y, extent.y, direction.y)
				local enterZ: number, exitZ: number = Hulls.slab(gap.z, extent.z, direction.z)
				local enter: number = math.max(enterX, enterY, enterZ)
				local exit: number = math.min(exitX, exitY, exitZ)
				local nearer: boolean = enter < foundShare or (enter == foundShare and id < foundId)

				if enter >= 0 and enter < exit and enter <= 1 and nearer then
					foundShare = enter
					foundId = id
					foundTop = position.y + box.center.y + box.half.y

					-- The face it enters through, which faces against the move on the axis it enters last
					if enter == enterX then
						foundNormal = vector.create(-math.sign(direction.x), 0, 0)
					elseif enter == enterY then
						foundNormal = vector.create(0, -math.sign(direction.y), 0)
					else
						foundNormal = vector.create(0, 0, -math.sign(direction.z))
					end
				end
			end
		end
	end
end

-- Whether a box of half size half at center overlaps any platform's box on the tick, touching counting as apart
local function inside(world: World, tick: number, center: vector, half: vector): boolean
	for _, entry: PlatformEntry in world.platforms do
		local position: vector = place(entry, tick)

		for _, box: PlatformBox in entry._boxes do
			local gap: vector = position + box.center - center
			local extent: vector = box.half + half

			if math.abs(gap.x) < extent.x and math.abs(gap.y) < extent.y and math.abs(gap.z) < extent.z then
				return true
			end
		end
	end

	return false
end

--[[
    The world's casts wrapped so each query also meets the platforms' boxes
    where they stand on the tick it runs at, the nearer of the two answering,
    the casts' own hit on a tie. A platform hit is Plastic and names no
    instance, and the wrapper's own hit table is reused like any other
--]]

local function wrap(world: World, under: Collision): Collision
	local hit: Hit = {
		distance = 0,
		position = vector.zero,
		normal = vector.zero,
		material = MATERIAL,
		instance = nil,
	}

	-- The nearer of the casts' own hit and the last meet's, a box of half size half having moved from center
	local function nearer(found: Hit?, center: vector, half: vector, direction: vector): Hit?
		if foundId == 0 then
			return found
		end

		local length: number =
			math.sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
		local distance: number = foundShare * length
		if found and found.distance <= distance then
			return found
		end

		hit.distance = distance
		hit.position = center + direction * foundShare - foundNormal * half
		hit.normal = foundNormal

		return hit
	end

	return {
		ray = function (origin: vector, direction: vector): Hit?
			local found: Hit? = under.ray(origin, direction)
			meet(world, Platforms.tick(world), origin, vector.zero, direction, 0)

			return nearer(found, origin, vector.zero, direction)
		end,

		sweep = function (center: vector, size: vector, direction: vector): Hit?
			local found: Hit? = under.sweep(center, size, direction)
			local half: vector = size / 2
			meet(world, Platforms.tick(world), center, half, direction, 0)

			return nearer(found, center, half, direction)
		end,

		-- The same plate the casts' own rest sweeps, down from the box's top to two skins under its bottom, which can
		-- only enter a platform's box through its top
		rest = function (center: vector, size: vector): number?
			local height: number? = under.rest(center, size)
			local top: number = center.y + size.y / 2
			local reach: number = size.y + SKINS
			local plate: vector = vector.create(size.x / 2, 0, size.z / 2)
			meet(
				world,
				Platforms.tick(world),
				vector.create(center.x, top, center.z),
				plate,
				vector.create(0, -reach, 0),
				0
			)

			if foundId ~= 0 and (height == nil or foundTop > height) then
				return foundTop
			end

			return height
		end,

		-- Swept as the cube around it, which meets a box's face where the sphere does and its edges a little early
		-- Whiteoak TODO: the cube meets a box's edge up to 0.41 radii early and its corner 0.73; an exact sweep of the
		-- rounded box, its faces then the capsules of its edges and the spheres of its corners, meets them where the
		-- sphere does, once a game's eye clearance near a platform's edge shows the gap
		sphere = function (center: vector, radius: number, direction: vector): Hit?
			local found: Hit? = under.sphere(center, radius, direction)
			local half: vector = vector.create(radius, radius, radius)
			meet(world, Platforms.tick(world), center, half, direction, 0)

			return nearer(found, center, half, direction)
		end,

		overlap = function (center: vector, size: vector): boolean
			return inside(world, Platforms.tick(world), center, size / 2) or under.overlap(center, size)
		end,

		destroy = function ()
			under.destroy()
		end,
	}
end

-- A Vector3 a game gave, as the step's vector, erroring naming what it was when it is no finite Vector3
local function crossed(value: Vector3, what: string): vector
	if typeof(value) ~= "Vector3" then
		error(`{what} must be a Vector3, and got a {typeof(value)}`)
	end

	local x: number, y: number, z: number = value.X, value.Y, value.Z
	if not (x - x == 0 and y - y == 0 and z - z == 0) then
		error(`{what} must be finite, and got {value}`)
	end

	return Engine.toVector(value)
end

--[[
    Registers a platform on a world, its boxes turned into the step's numbers
    once, and gives back the closure that removes it, harmless twice. The
    first platform wraps the world's casts and the last one out puts them
    back. Refuses an id that is no whole number from 1 to MAX_PLATFORMS or
    that another holds, no boxes, a box with no positive, finite size and a
    path that is no function
--]]

function Platforms.add(world: World, platform: Platform): () -> ()
	if type(platform) ~= "table" then
		error(`A platform must be a table, and got a {typeof(platform)}`)
	end

	local id: number = platform.id
	if type(id) ~= "number" or id % 1 ~= 0 or id < 1 or id > MAX_PLATFORMS then
		error(`A platform's id must be a whole number from 1 to {MAX_PLATFORMS}, and got {id}`)
	elseif world.platforms[id] ~= nil then
		error(`A platform with the id {id} is already registered`)
	end

	local path: (tick: number, calledAt: number?) -> Vector3 = platform.path
	if type(path) ~= "function" then
		error(`Platform {id}'s path must be a function, and got a {typeof(path)}`)
	end

	local given: { { center: Vector3, size: Vector3 } } = platform.boxes
	if type(given) ~= "table" or #given == 0 then
		error(`Platform {id} needs a list of at least one box, and got {given}`)
	end

	local boxes: { PlatformBox } = {}
	for index: number = 1, #given do
		local box: { center: Vector3, size: Vector3 } = given[index]
		if type(box) ~= "table" then
			error(`Platform {id}'s box {index} must be a table of its center and size, and got a {typeof(box)}`)
		end

		local center: vector = crossed(box.center, `Platform {id}'s box {index}'s center`)
		local size: vector = crossed(box.size, `Platform {id}'s box {index}'s size`)
		if not (size.x > 0 and size.y > 0 and size.z > 0) then
			error(`Platform {id}'s box {index} needs a size above 0 on every axis, and got {box.size}`)
		end

		table.insert(boxes, { center = center, half = size / 2 })
	end

	local entry: PlatformEntry = {
		id = id,
		calledAt = nil,
		calledBefore = nil,
		_path = path,
		_boxes = boxes,
		_tick = NONE,
		_position = vector.zero,
		_under = world.collision,
		_casts = world.collision,
	}

	-- Every platform of a world shares the one wrapper the first installed
	local _, other: PlatformEntry? = next(world.platforms)
	if other then
		entry._under = other._under
		entry._casts = other._casts
	else
		entry._casts = wrap(world, entry._under)
		world.collision = entry._casts
	end

	world.platforms[id] = entry

	return function ()
		if world.platforms[id] ~= entry then
			return
		end

		world.platforms[id] = nil

		-- Unless other code has swapped in casts of its own since
		if next(world.platforms) == nil and world.collision == entry._casts then
			world.collision = entry._under
		end
	end
end

--[[
    Calls a platform on a tick, unwrapped: its path runs from the latest
    call on the ticks from it on, and from the call before it on the ticks
    before that. A call between the two it keeps replaces the older
--]]

function Platforms.call(world: World, id: number, tick: number)
	local entry: PlatformEntry? = world.platforms[id]
	if not entry then
		error(`No platform with the id {id} is registered to call`)
	elseif type(tick) ~= "number" or tick % 1 ~= 0 then
		error(`Platform {id}'s call needs a whole tick, and got {tick}`)
	end

	local latest: number? = entry.calledAt
	if latest == nil or tick > latest then
		entry.calledBefore = latest
		entry.calledAt = tick
	elseif tick < latest then
		local before: number? = entry.calledBefore
		if before == nil or tick > before then
			entry.calledBefore = tick
		end
	end

	-- What it keeps may now run from another call
	entry._tick = NONE
end

--[[
    Where a platform stands on an unwrapped tick: on the 1/512 quantum at a
    whole tick, and between the two whole ticks around a fraction through
    Math.lerp. Nil for an id no platform holds
--]]

function Platforms.at(world: World, id: number, tick: number): vector?
	local entry: PlatformEntry? = world.platforms[id]
	if not entry then
		return nil
	elseif type(tick) ~= "number" or tick - tick ~= 0 then
		error(`Platform {id}'s place needs a finite tick, and got {tick}`)
	end

	local whole: number = math.floor(tick)
	local from: vector = placeOn(entry, whole)
	local share: number = tick - whole
	if share == 0 then
		return from
	end

	local to: vector = placeOn(entry, whole + 1)

	return vector.create(Math.lerp(from.x, to.x, share), Math.lerp(from.y, to.y, share), Math.lerp(from.z, to.z, share))
end

--[[
    Moves a rider by its platform's move, swept with a skin past it against
    the world's own casts and every other platform's boxes, and no hulls.
    Gives back whether it went the whole way, and when it did not, leaves
    it a skin short of what it met
--]]

local function sweep(state: State, world: World, tick: number, entry: PlatformEntry, move: vector): boolean
	local settings: Settings = world.settings
	local height: number = Hulls.height(state, settings)
	local width: number = settings.radius + settings.radius
	local feet: vector = state.position
	local center: vector = vector.create(feet.x, feet.y + height / 2, feet.z)
	local size: vector = vector.create(width, height, width)
	local length: number = math.sqrt(move.x * move.x + move.y * move.y + move.z * move.z)
	local direction: vector = move * ((length + SKIN) / length)

	-- The casts under the platforms' boxes, or whatever other code has swapped in since
	local casts: Collision = world.collision
	if casts == entry._casts then
		casts = entry._under
	end

	local nearest: number = math.huge
	local found: Hit? = casts.sweep(center, size, direction)
	if found then
		nearest = found.distance
	end

	meet(world, tick, center, size / 2, direction, entry.id)
	if foundId ~= 0 then
		nearest = math.min(nearest, foundShare * (length + SKIN))
	end

	-- Under a quantum short is rounding on a surface the move ends a skin from, as the floor a lift comes down to
	local travel: number = math.max(nearest - SKIN, 0)
	if travel >= length - QUANTUM then
		state.position = feet + move

		return true
	end

	state.position = feet + move * (travel / length)

	return false
end

--[[
    A rider's carry, before its walk: by its platform's move since the last
    tick. Blocked, it stops where the sweep did, off the platform with the
    platform's velocity, and a rider whose platform is gone is dropped.
    Gives back whether any platform's box then presses into the body, which
    the walk's depenetration then checks exactly
--]]

function Platforms.carry(state: State, world: World): boolean
	if next(world.platforms) == nil then
		state.platform = 0

		return false
	end

	local tick: number = Platforms.tick(world)
	local id: number = state.platform
	if id ~= 0 then
		local entry: PlatformEntry? = world.platforms[id]

		if not entry then
			state.platform = 0
		else
			local move: vector = place(entry, tick) - placeOn(entry, tick - 1)
			if move ~= vector.zero and not sweep(state, world, tick, entry, move) then
				state.platform = 0
				state.velocity += move / world.delta
			end
		end
	end

	local settings: Settings = world.settings
	local half: number = Hulls.height(state, settings) / 2
	local feet: vector = state.position
	local center: vector = vector.create(feet.x, feet.y + half, feet.z)

	return inside(world, tick, center, vector.create(settings.radius, half, settings.radius))
end

--[[
    The platform a grounded body stands on after its walk: the one whose box
    top is highest within two skins under its feet and under its footprint,
    the lower id on a tie, else none. A rider's velocity is its platform's,
    so leaving one adds that platform's velocity and boarding one takes it
--]]

function Platforms.board(state: State, world: World)
	if next(world.platforms) == nil then
		return
	end

	local tick: number = Platforms.tick(world)
	local feet: vector = state.position
	local radius: number = world.settings.radius
	local boarded: number = 0
	local highest: number = -math.huge

	if state.grounded then
		for id: number, entry: PlatformEntry in world.platforms do
			local position: vector = place(entry, tick)

			for _, box: PlatformBox in entry._boxes do
				local center: vector = position + box.center
				local half: vector = box.half
				local top: number = center.y + half.y
				local below: number = feet.y - top
				local under: boolean = math.abs(center.x - feet.x) < half.x + radius
					and math.abs(center.z - feet.z) < half.z + radius

				if under and below >= 0 and below <= SKINS and (top > highest or (top == highest and id < boarded)) then
					boarded = id
					highest = top
				end
			end
		end
	end

	local was: number = state.platform
	if boarded == was then
		return
	end

	local left: PlatformEntry? = world.platforms[was]
	if left then
		state.velocity += velocityOf(left, tick, world.delta)
	end

	local onto: PlatformEntry? = world.platforms[boarded]
	if onto then
		state.velocity -= velocityOf(onto, tick, world.delta)
	end

	state.platform = boarded
end

return Platforms
