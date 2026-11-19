--[[
    Hulls.sweep and Hulls.block give exactly what their loops give with no
    reject, on a seeded random set of sweeps with hulls at the reject's
    bounds and past them, mixing hull sizes, postures, modes and directions
--]]

--!strict
local Environment = require("../../Environment")

local HULLS: string = "src/Step/Hulls.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local CONSTANTS: string = "src/Constants.luau"
local SEED: number = 7349
local CASES: number = 4000
local MOST_BODIES: number = 12 -- Besides the moving body, which the list holds too, as a world's does
local ROOM: number = 120 -- Studs kept inside the wire bounds, past the farthest a body lies from a case's start
local NEAR_ORIGIN: number = 50 -- Studs either way of the origin half the cases start within, where float32 is finest
local SPREAD: number = 3 -- Studs past the bounds that a body placed anywhere about them may lie
local NEAREST_FAR: number = 5 -- Studs past the bounds that a far body lies, at least and at most
local FARTHEST: number = 60
local SMALLEST_RADIUS: number = 0.3 -- The world's hull radius, at least and at most
local LARGEST_RADIUS: number = 2.5
local SHORTEST: number = 1 -- A crouched hull's height at least, and a standing one's at most
local TALLEST: number = 6
local SMALLEST_BOX: number = 0.2 -- Studs on each axis a box that is no hull spans, at least
local HULL_BOX: number = 0.8 -- The share of sweeps that move the body's own hull, the rest a box of any size
local ANYWHERE: number = 0.35 -- The shares of placements about the bounds, then at one of them, then in the start box
local AT_BOUND: number = 0.75
local IN_START: number = 0.9
local TWIN: number = 0.1 -- The share of bodies at another's exact position, which ties every slab between them
local ON_PATH: number = 0.5 -- The share up to which the rest lie on the move's path, the others placed by axis
local GRAZE_X: number = 0.25 -- The shares of those on the path moved to a bound on X, then on Z
local GRAZE_Z: number = 0.5
local EVEN: number = 0.5 -- A coin flip's share

-- What the set must cover to prove anything: sweeps that meet a hull, those that meet one within a skin of the
-- bounds on X or Z, and stands that block
local LEAST_HITS: number = 500
local LEAST_GRAZES: number = 150
local LEAST_BLOCKS: number = 6000

-- Downed covers a sleeper too, which lies Downed and walking
local POSTURES: { string } = { "Stand", "Crouch", "Downed" }
local MODES: { string } = { "Ground", "Air", "Swim" }
local MOVE_MODES: { string } = { "Walk", "Walk", "Walk", "Walk", "Noclip", "Parked" }
local DIRECTIONS: { string } = { "level", "down", "up", "diagonal", "x", "z", "zero" }
local REACHES: { number } = { 0.1, 1, 4, 25 } -- Studs a move spans on an axis at most, up to a fast tick's cast

local function between(low: number, high: number): number
	return low + (high - low) * math.random()
end

local function pick<T>(list: { T }): T
	return list[math.random(#list)]
end

-- Whether a body's hull blocks others, as the module reads it
local function blocks(other: any, state: any): boolean
	return other ~= state and other.moveMode == "Walk" and other.posture ~= "Downed"
end

--[[
    Hulls.sweep's loop as it runs with no reject: every blocking body goes
    through its three slabs, the nearest entry kept, the first of a tie
--]]

local function sweep(
	Hulls: any,
	state: any,
	center: vector,
	size: vector,
	direction: vector,
	world: any
): (number, vector, any)
	local nearest: number = math.huge
	local normal: vector = vector.zero
	local body: any = nil

	local length: number = math.sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
	if state.moveMode ~= "Walk" or length == 0 then
		return nearest, normal, body
	end

	local settings: any = world.settings
	local radius: number = settings.radius
	local halfX: number = size.x / 2 + radius
	local halfZ: number = size.z / 2 + radius

	for _, other: any in world.bodies do
		if blocks(other, state) then
			local otherHalf: number = Hulls.height(other, settings) / 2
			local at: vector = other.position

			local enterX: number, exitX: number = Hulls.slab(at.x - center.x, halfX, direction.x)
			local enterY: number, exitY: number =
				Hulls.slab(at.y + otherHalf - center.y, size.y / 2 + otherHalf, direction.y)
			local enterZ: number, exitZ: number = Hulls.slab(at.z - center.z, halfZ, direction.z)
			local enter: number = math.max(enterX, enterY, enterZ)
			local exit: number = math.min(exitX, exitY, exitZ)

			if enter >= 0 and enter < exit and enter <= 1 and enter * length < nearest then
				nearest = enter * length
				body = other

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

-- Hulls.block's loop as it runs with no reject: every blocking body tested on all four bounds
local function block(Hulls: any, state: any, world: any): boolean
	if state.moveMode ~= "Walk" then
		return false
	end

	local settings: any = world.settings
	local reach: number = settings.radius + settings.radius
	local feet: vector = state.position
	local top: number = feet.y + Hulls.height(state, settings)

	for _, other: any in world.bodies do
		if blocks(other, state) then
			local at: vector = other.position
			local apart: boolean = math.abs(at.x - feet.x) >= reach
				or math.abs(at.z - feet.z) >= reach
				or at.y >= top
				or feet.y >= at.y + Hulls.height(other, settings)

			if not apart then
				return true
			end
		end
	end

	return false
end

-- A move of one kind, each axis it runs on up to reach either way
local function move(kind: string, reach: number): vector
	if kind == "level" then
		return vector.create(between(-reach, reach), 0, between(-reach, reach))
	elseif kind == "down" then
		return vector.create(0, -between(0, reach), 0)
	elseif kind == "up" then
		return vector.create(0, between(0, reach), 0)
	elseif kind == "diagonal" then
		return vector.create(between(-reach, reach), between(-reach, reach), between(-reach, reach))
	elseif kind == "x" then
		return vector.create(between(-reach, reach), 0, 0)
	elseif kind == "z" then
		return vector.create(0, 0, between(-reach, reach))
	end

	return vector.zero
end

return function (): (boolean, string | nil)
	local Hulls: any = Environment.load(HULLS)
	local Scene: any = Environment.load(SCENE)
	local Constants: any = Environment.load(CONSTANTS)
	local collision: any = Environment.load(CASTS)({})
	local skin: number = Constants.SKIN
	local quantum: number = Constants.POSITION_QUANTUM
	local bound: number = Constants.PLAY_BOUND - ROOM
	local lowest: number = Constants.HEIGHT_MIN + ROOM
	local highest: number = Constants.HEIGHT_MAX - ROOM

	-- How far inside or outside a bound a body placed at one lies
	local edges: { number } = { 0, quantum / 4, quantum / 2, quantum, skin / 2, skin, 2 * skin }

	-- A coordinate at either of two bounds, on it or just inside or outside it
	local function edge(low: number, high: number): number
		local offset: number = pick(edges)
		if math.random() < EVEN then
			offset = -offset
		end

		if math.random() < EVEN then
			return low - offset
		end

		return high + offset
	end

	-- One coordinate: anywhere about the bounds, at one of them, in the start box's span, or far past them
	local function place(low: number, high: number, start: number, half: number): number
		local roll: number = math.random()
		if roll < ANYWHERE then
			return between(low - SPREAD, high + SPREAD)
		elseif roll < AT_BOUND then
			return edge(low, high)
		elseif roll < IN_START then
			return between(start - half, start + half)
		end

		local far: number = between(NEAREST_FAR, FARTHEST)
		if math.random() < EVEN then
			return low - far
		end

		return high + far
	end

	local hits: number = 0
	local grazes: number = 0
	local blocked: number = 0

	math.randomseed(SEED)

	for index: number = 1, CASES do
		local settings: any = table.clone(Scene.settings)
		settings.radius = between(SMALLEST_RADIUS, LARGEST_RADIUS)
		settings.standing = between(SHORTEST, TALLEST)
		settings.crouched = between(SHORTEST, settings.standing)

		local start: vector
		if math.random() < EVEN then
			start = vector.create(
				between(-NEAR_ORIGIN, NEAR_ORIGIN),
				between(lowest, highest),
				between(-NEAR_ORIGIN, NEAR_ORIGIN)
			)
		else
			start = vector.create(between(-bound, bound), between(lowest, highest), between(-bound, bound))
		end

		local state: any = Scene.state(start, true)
		state.posture = pick(POSTURES)
		state.mode = pick(MODES)
		state.moveMode = pick(MOVE_MODES)

		local radius: number = settings.radius
		local size: vector
		if math.random() < HULL_BOX then
			size = vector.create(2 * radius, Hulls.height(state, settings), 2 * radius)
		else
			size = vector.create(
				between(SMALLEST_BOX, TALLEST),
				between(SMALLEST_BOX, TALLEST),
				between(SMALLEST_BOX, TALLEST)
			)
		end

		local center: vector = start + vector.create(0, size.y / 2, 0)
		local direction: vector = move(pick(DIRECTIONS), pick(REACHES))
		local endX: number = center.x + direction.x
		local endY: number = center.y + direction.y
		local endZ: number = center.z + direction.z

		-- The bounds a hull's center lies within to meet the box on X and Z, and its feet on Y
		local halfX: number = size.x / 2 + radius
		local halfZ: number = size.z / 2 + radius
		local lowX: number = math.min(center.x, endX) - halfX
		local highX: number = math.max(center.x, endX) + halfX
		local lowZ: number = math.min(center.z, endZ) - halfZ
		local highZ: number = math.max(center.z, endZ) + halfZ
		local lowY: number = math.min(center.y, endY) - size.y / 2
		local highY: number = math.max(center.y, endY) + size.y / 2

		local others: { any } = {}
		for _ = 1, math.random(MOST_BODIES) do
			local other: any = Scene.state(start, true)
			other.posture = pick(POSTURES)
			other.mode = pick(MODES)
			other.moveMode = pick(MOVE_MODES)

			local height: number = Hulls.height(other, settings)
			local roll: number = math.random()
			if #others > 0 and roll < TWIN then
				other.position = pick(others).position
			elseif roll < ON_PATH then
				-- Overlapping the box somewhere along the move, so it meets it unless it starts in it
				local along: vector = center + direction * math.random()
				local reachY: number = (size.y + height) / 2
				local x: number = along.x + between(-halfX, halfX)
				local y: number = along.y - height / 2 + between(-reachY, reachY)
				local z: number = along.z + between(-halfZ, halfZ)

				local side: number = math.random()
				if side < GRAZE_X then
					x = edge(lowX, highX)
				elseif side < GRAZE_Z then
					z = edge(lowZ, highZ)
				end

				other.position = vector.create(x, y, z)
			else
				local x: number = place(lowX, highX, center.x, halfX)
				local y: number = place(lowY - height, highY, center.y - height / 2, (size.y + height) / 2)
				local z: number = place(lowZ, highZ, center.z, halfZ)
				other.position = vector.create(x, y, z)
			end

			table.insert(others, other)
		end

		local bodies: { any } = table.clone(others)
		table.insert(bodies, math.random(#bodies + 1), state)

		local world: any = Scene.world(collision, bodies)
		world.settings = settings

		local distance: number, normal: vector, body: any = Hulls.sweep(state, center, size, direction, world)
		local wantDistance: number, wantNormal: vector, wantBody: any =
			sweep(Hulls, state, center, size, direction, world)
		if distance ~= wantDistance or normal ~= wantNormal or body ~= wantBody then
			local found: string = `Hulls.sweep in case {index} gave {distance} and {normal}`
			local wanted: string = `{wantDistance} and {wantNormal} from the loop with no reject`

			return false, `{found}, where {wanted} were expected, the same body {body == wantBody}`
		end

		if wantBody then
			local at: vector = wantBody.position
			hits += 1

			if math.min(at.x - lowX, highX - at.x, at.z - lowZ, highZ - at.z) < skin then
				grazes += 1
			end
		end

		for _, standing: any in bodies do
			local wanted: boolean = block(Hulls, standing, world)
			if Hulls.block(standing, world) ~= wanted then
				local found: string = `Hulls.block in case {index} gave {not wanted}`

				return false, `{found}, where the loop with no reject gave {wanted}`
			end

			if wanted then
				blocked += 1
			end
		end
	end

	if hits < LEAST_HITS or grazes < LEAST_GRAZES or blocked < LEAST_BLOCKS then
		local covered: string = `{hits} hits, {grazes} within a skin of the bounds and {blocked} blocked stands`

		return false, `The random set covered only {covered}, under {LEAST_HITS}, {LEAST_GRAZES} and {LEAST_BLOCKS}`
	end

	return true, nil
end
