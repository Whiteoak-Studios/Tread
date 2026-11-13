--[[
    The hull grid gives exactly what a walk of every body gives, in seeded
    sweeps, stands and box tests over mixed hulls, cell edges and ties, and
    again once bodies moved outside a step are filed again
--]]

--!strict
local Environment = require("../../Environment")

local HULLS: string = "src/Step/Hulls.luau"
local WORLD: string = "src/Step/World.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local CONSTANTS: string = "src/Constants.luau"
local SEED: number = 5113
local CASES: number = 4000
local MOST_BODIES: number = 30 -- Besides the moving body, which the list holds too, as a world's does
local ROOM: number = 300 -- Studs kept inside the wire bounds, past the farthest a body lies or moves from the start
local NEAR_ORIGIN: number = 50 -- Studs either way of the origin half the cases start within, where float32 is finest
local SMALLEST_RADIUS: number = 0.3 -- The world's hull radius, at least and at most
local LARGEST_RADIUS: number = 2.5
local SHORTEST: number = 1 -- A crouched hull's height at least, and a standing one's at most
local TALLEST: number = 6
local SMALLEST_BOX: number = 0.2 -- Studs on each axis a box that is no hull spans, at least
local LARGEST_BOX: number = 60 -- And at most for a box test, which then spans more cells than the list holds bodies
local NEAR_CELLS: number = 3 -- Cells either way of the start that a body placed near it lies within
local FAR: number = 200 -- Studs either way of the start that a far body lies within, and a far move goes
local SPREAD: number = 3 -- Studs past the bounds that a body placed about them may lie
local INSIDE: number = 0.95 -- The share of the box's half width a tied body lies within across the move
local HULL_BOX: number = 0.8 -- The share of sweeps that move the body's own hull, the rest a box of any size
local EVEN: number = 0.5 -- A coin flip's share

-- The shares of placements: at another's exact place, tied with another along the move, on the move's path, at the
-- bounds, on a cell's edge, near the start, and the rest far
local TWIN: number = 0.08
local TIED: number = 0.22
local ON_PATH: number = 0.45
local AT_BOUND: number = 0.55
local ON_EDGE: number = 0.72
local NEAR: number = 0.92
local EDGE_AXIS: number = 0.7 -- The share of a body on an edge whose each axis lies on a cell line
local GRAZE_X: number = 0.2 -- The shares of those on the path moved to a bound on X, then on Z, then to cell lines
local GRAZE_Z: number = 0.4
local SNAP: number = 0.7

-- Between the rounds: the share of bodies moved, then the shares of the moves, a nudge across cell lines, onto a
-- cell's edge, far, onto another's place and the rest anywhere a placement puts a body, and the share whose posture
-- and modes change
local MOVED: number = 0.4
local NUDGE: number = 0.3
local TO_EDGE: number = 0.5
local TO_FAR: number = 0.65
local TO_TWIN: number = 0.8
local RESTYLED: number = 0.2

-- How the world hears of the moves: each moved body filed again, every body refreshed, or a new list from
-- World.setBodies, some bodies left out and new ones added
local BY_BODY: number = 1 / 3
local BY_REFRESH: number = 2 / 3
local LEFT_OUT: number = 0.15

-- What the set must cover to prove anything: sweeps that meet a hull, those whose nearest is a tie, sweeps over few
-- enough cells for the grid to visit them, hulls met on a cell line, stands that block, boxes that overlap, and
-- cases whose second round follows moves
local LEAST_HITS: number = 1400
local LEAST_TIES: number = 150
local LEAST_GRIDDED: number = 2500
local LEAST_EDGE_HITS: number = 350
local LEAST_BLOCKS: number = 40000
local LEAST_OVERLAPS: number = 5000
local LEAST_MOVED: number = 3500

-- Downed covers a sleeper too, which lies Downed and walking
local POSTURES: { string } = { "Stand", "Crouch", "Downed" }
local MODES: { string } = { "Ground", "Air", "Swim" }
local MOVE_MODES: { string } = { "Walk", "Walk", "Walk", "Walk", "Noclip", "Parked" }
local DIRECTIONS: { string } = { "level", "down", "up", "diagonal", "x", "z", "zero" }

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
    Hulls.sweep's walk of every body as it runs with no grid, the nearest
    entry kept and the first of a tie, with how many bodies meet the box at
    that distance
--]]

local function sweep(
	Hulls: any,
	margin: number,
	state: any,
	center: vector,
	size: vector,
	direction: vector,
	world: any
): (number, vector, any, number)
	local nearest: number = math.huge
	local normal: vector = vector.zero
	local body: any = nil
	local ties: number = 0

	local length: number = math.sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
	if state.moveMode ~= "Walk" or length == 0 then
		return nearest, normal, body, ties
	end

	local settings: any = world.settings
	local radius: number = settings.radius
	local halfX: number = size.x / 2 + radius
	local halfZ: number = size.z / 2 + radius

	local endX: number = center.x + direction.x
	local endZ: number = center.z + direction.z
	local lowX: number = math.min(center.x, endX) - halfX - margin
	local highX: number = math.max(center.x, endX) + halfX + margin
	local lowZ: number = math.min(center.z, endZ) - halfZ - margin
	local highZ: number = math.max(center.z, endZ) + halfZ + margin

	for _, other: any in world.bodies do
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

			if enter >= 0 and enter < exit and enter <= 1 then
				if enter * length < nearest then
					nearest = enter * length
					body = other
					ties = 1

					if enter == enterX then
						normal = vector.create(-math.sign(direction.x), 0, 0)
					elseif enter == enterY then
						normal = vector.create(0, -math.sign(direction.y), 0)
					else
						normal = vector.create(0, 0, -math.sign(direction.z))
					end
				elseif enter * length == nearest then
					ties += 1
				end
			end
		end
	end

	return nearest, normal, body, ties
end

-- Hulls.block's walk of every body as it runs with no grid
local function block(Hulls: any, state: any, world: any): boolean
	if state.moveMode ~= "Walk" then
		return false
	end

	local settings: any = world.settings
	local reach: number = settings.radius + settings.radius
	local feet: vector = state.position
	local top: number = feet.y + Hulls.height(state, settings)

	for _, other: any in world.bodies do
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

-- The pair the box test's walk is testing, held here so separates reads it
local boxRight: vector = vector.zero
local boxUp: vector = vector.zero
local boxLook: vector = vector.zero
local boxHalf: vector = vector.zero
local hullHalf: vector = vector.zero
local offset: vector = vector.zero

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

local function crossSeparates(axis: vector): boolean
	return separates(0, axis.z, -axis.y) or separates(-axis.z, 0, axis.x) or separates(axis.y, -axis.x, 0)
end

-- Hulls.overlaps's walk of every body as it runs with no grid
local function overlaps(Hulls: any, box: any, world: any): boolean
	local size: vector = box.size
	local settings: any = world.settings
	local radius: number = settings.radius
	boxRight, boxUp, boxLook = box.right, box.up, box.look
	boxHalf = size / 2

	local reachX: number = boxHalf.x * math.abs(boxRight.x)
		+ boxHalf.y * math.abs(boxUp.x)
		+ boxHalf.z * math.abs(boxLook.x)
	local reachY: number = boxHalf.x * math.abs(boxRight.y)
		+ boxHalf.y * math.abs(boxUp.y)
		+ boxHalf.z * math.abs(boxLook.y)
	local reachZ: number = boxHalf.x * math.abs(boxRight.z)
		+ boxHalf.y * math.abs(boxUp.z)
		+ boxHalf.z * math.abs(boxLook.z)

	for _, other: any in world.bodies do
		if other.moveMode == "Walk" then
			local half: number = Hulls.height(other, settings) / 2
			local at: vector = other.position
			hullHalf = vector.create(radius, half, radius)
			offset = vector.create(at.x, at.y + half, at.z) - box.center

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

-- A box turned by a random rotation, its axes the columns of a unit quaternion's matrix
local function turned(center: vector, size: vector): { [string]: vector }
	local w: number, x: number, y: number, z: number = between(-1, 1), between(-1, 1), between(-1, 1), between(-1, 1)
	local length: number = math.sqrt(w * w + x * x + y * y + z * z)
	w, x, y, z = w / length, x / length, y / length, z / length

	return {
		center = center,
		right = vector.create(1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y)),
		up = vector.create(2 * (x * y - w * z), 1 - 2 * (x * x + z * z), 2 * (y * z + w * x)),
		look = vector.create(2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y)),
		size = size,
	}
end

return function (): (boolean, string | nil)
	local Hulls: any = Environment.load(HULLS)
	local World: any = Environment.load(WORLD)
	local Scene: any = Environment.load(SCENE)
	local Constants: any = Environment.load(CONSTANTS)
	local collision: any = Environment.load(CASTS)({})
	local skin: number = Constants.SKIN
	local quantum: number = Constants.POSITION_QUANTUM
	local fastest: number = Constants.VELOCITY_LIMIT * Scene.world(collision).delta -- A tick's move at the most
	local bound: number = Constants.PLAY_BOUND - ROOM
	local lowest: number = Constants.HEIGHT_MIN + ROOM
	local highest: number = Constants.HEIGHT_MAX - ROOM
	local reaches: { number } = { 0.1, 1, 4, fastest }

	-- How far inside or outside a line a body placed on one lies
	local edges: { number } = { 0, quantum / 4, quantum / 2, quantum, skin / 2, skin, 2 * skin }

	local function edge(line: number): number
		local away: number = pick(edges)
		if math.random() < EVEN then
			away = -away
		end

		return line + away
	end

	-- A coordinate on a cell line within two cells of where it starts
	local function onCell(start: number, cell: number): number
		return edge((math.floor(start / cell) + math.random(-2, 2)) * cell)
	end

	local hits: number = 0
	local ties: number = 0
	local gridded: number = 0
	local edgeHits: number = 0
	local blocked: number = 0
	local overlapping: number = 0
	local movedRounds: number = 0

	math.randomseed(SEED)

	for index: number = 1, CASES do
		local settings: any = table.clone(Scene.settings)
		settings.radius = between(SMALLEST_RADIUS, LARGEST_RADIUS)
		settings.standing = between(SHORTEST, TALLEST)
		settings.crouched = between(SHORTEST, settings.standing)
		local radius: number = settings.radius

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

		local kind: string = pick(DIRECTIONS)
		local center: vector = start + vector.create(0, size.y / 2, 0)
		local direction: vector = move(kind, pick(reaches))
		local endX: number = center.x + direction.x
		local endZ: number = center.z + direction.z
		local halfX: number = size.x / 2 + radius
		local halfZ: number = size.z / 2 + radius
		local lowX: number = math.min(center.x, endX) - halfX
		local highX: number = math.max(center.x, endX) + halfX
		local lowZ: number = math.min(center.z, endZ) - halfZ
		local highZ: number = math.max(center.z, endZ) + halfZ

		-- The grid's cell, as Hulls.createGrid sizes it, the bodies on cell lines, and those on the move's path, which
		-- twins and ties copy so the sweep meets them
		local cell: number = 0
		local edged: { [any]: boolean } = {}
		local others: { any } = {}
		local onPath: { any } = {}

		-- One body's place: the kinds the shares above give
		local function place(other: any)
			local height: number = Hulls.height(other, settings)
			local roll: number = math.random()
			local copied: { any } = #onPath > 0 and onPath or others

			if #copied > 0 and roll < TWIN then
				other.position = pick(copied).position
			elseif #copied > 0 and roll < TIED then
				-- Another's place along the move's one axis, and inside the box across it, so it enters at the same share
				local twin: vector = pick(copied).position
				local acrossX: number = center.x + between(-halfX, halfX) * INSIDE
				local acrossZ: number = center.z + between(-halfZ, halfZ) * INSIDE
				if kind == "x" then
					other.position = vector.create(twin.x, twin.y, acrossZ)
				elseif kind == "z" then
					other.position = vector.create(acrossX, twin.y, twin.z)
				else
					other.position = vector.create(acrossX, twin.y, acrossZ)
				end
			elseif roll < ON_PATH then
				local along: vector = center + direction * math.random()
				local reachY: number = (size.y + height) / 2
				local x: number = along.x + between(-halfX, halfX)
				local y: number = along.y - height / 2 + between(-reachY, reachY)
				local z: number = along.z + between(-halfZ, halfZ)

				local side: number = math.random()
				if side < GRAZE_X then
					x = edge(math.random() < EVEN and lowX or highX)
				elseif side < GRAZE_Z then
					z = edge(math.random() < EVEN and lowZ or highZ)
				elseif side < SNAP then
					x = edge(math.round(x / cell) * cell)
					z = edge(math.round(z / cell) * cell)
					edged[other] = true
				end

				other.position = vector.create(x, y, z)
				table.insert(onPath, other)
			elseif roll < AT_BOUND then
				local x: number = between(lowX - SPREAD, highX + SPREAD)
				local z: number = between(lowZ - SPREAD, highZ + SPREAD)
				if math.random() < EVEN then
					x = edge(math.random() < EVEN and lowX or highX)
				else
					z = edge(math.random() < EVEN and lowZ or highZ)
				end

				other.position = vector.create(x, center.y - height / 2 + between(-height, height), z)
			elseif roll < ON_EDGE then
				local x: number = start.x + between(-NEAR_CELLS, NEAR_CELLS) * cell
				local z: number = start.z + between(-NEAR_CELLS, NEAR_CELLS) * cell
				if math.random() < EDGE_AXIS then
					x = onCell(start.x, cell)
				end

				if math.random() < EDGE_AXIS then
					z = onCell(start.z, cell)
				end

				other.position = vector.create(x, start.y + between(-height, height), z)
				edged[other] = true
			elseif roll < NEAR then
				local x: number = start.x + between(-NEAR_CELLS, NEAR_CELLS) * cell
				local z: number = start.z + between(-NEAR_CELLS, NEAR_CELLS) * cell
				other.position = vector.create(x, start.y + between(-height, height), z)
			else
				local x: number = start.x + between(-FAR, FAR)
				local z: number = start.z + between(-FAR, FAR)
				other.position = vector.create(x, start.y + between(-height, height), z)
			end
		end

		local function restyle(other: any)
			other.posture = pick(POSTURES)
			other.mode = pick(MODES)
			other.moveMode = pick(MOVE_MODES)
		end

		local world: any = Scene.world(collision, {})
		world.settings = settings
		Hulls.createGrid(world)
		cell = world.grid.size

		for _ = 1, math.random(MOST_BODIES) do
			local other: any = Scene.state(start, true)
			restyle(other)
			place(other)
			table.insert(others, other)
		end

		local bodies: { any } = table.clone(others)
		table.insert(bodies, math.random(#bodies + 1), state)
		World.setBodies(world, bodies)

		-- Every test against its walk, the sweep's tied body included
		local function compare(round: string): (boolean, string | nil)
			local distance: number, normal: vector, body: any = Hulls.sweep(state, center, size, direction, world)
			local wantDistance: number, wantNormal: vector, wantBody: any, wantTies: number =
				sweep(Hulls, skin, state, center, size, direction, world)
			if distance ~= wantDistance or normal ~= wantNormal or body ~= wantBody then
				local found: string = `Hulls.sweep in case {index}, {round}, gave {distance} and {normal}`
				local wanted: string = `{wantDistance} and {wantNormal} from the walk`

				return false, `{found}, where {wanted} were expected, the same body {body == wantBody}`
			end

			if wantBody then
				hits += 1

				if wantTies > 1 then
					ties += 1
				end

				if edged[wantBody] then
					edgeHits += 1
				end
			end

			-- Whether the sweep's bounds span few enough cells for the grid to visit them
			local columns: number = math.floor((highX + skin) / cell) - math.floor((lowX - skin) / cell) + 1
			local rows: number = math.floor((highZ + skin) / cell) - math.floor((lowZ - skin) / cell) + 1
			if state.moveMode == "Walk" and direction ~= vector.zero and columns * rows <= #world.bodies then
				gridded += 1
			end

			for _, standing: any in world.bodies do
				local wanted: boolean = block(Hulls, standing, world)
				if Hulls.block(standing, world) ~= wanted then
					local found: string = `Hulls.block in case {index}, {round}, gave {not wanted}`

					return false, `{found}, where the walk gave {wanted}`
				end

				if wanted then
					blocked += 1
				end
			end

			-- Mostly small, and now and then wide enough to span more cells than the list holds bodies
			local boxSize: vector = vector.create(
				between(SMALLEST_BOX, LARGEST_BOX) ^ 2 / LARGEST_BOX + SMALLEST_BOX,
				between(SMALLEST_BOX, TALLEST),
				between(SMALLEST_BOX, LARGEST_BOX) ^ 2 / LARGEST_BOX + SMALLEST_BOX
			)
			local boxCenter: vector = pick(world.bodies).position
				+ vector.create(between(-cell, cell), between(-TALLEST, TALLEST), between(-cell, cell))
			local box: { [string]: vector } = turned(boxCenter, boxSize)

			local wantOverlap: boolean = overlaps(Hulls, box, world)
			if Hulls.overlaps(box, world) ~= wantOverlap then
				local found: string = `Hulls.overlaps in case {index}, {round}, gave {not wantOverlap}`

				return false, `{found}, where the walk gave {wantOverlap}`
			end

			if wantOverlap then
				overlapping += 1
			end

			return true, nil
		end

		local passed: boolean, reason: string? = compare("as placed")
		if not passed then
			return false, reason
		end

		-- Bodies moved outside a step, as a teleport, a spawn's depenetration or a mode change moves them
		local moved: { any } = {}
		for _, other: any in bodies do
			if math.random() >= MOVED then
				continue
			end

			local at: vector = other.position
			local roll: number = math.random()
			if roll < NUDGE then
				other.position = at + vector.create(between(-cell, cell), 0, between(-cell, cell))
			elseif roll < TO_EDGE then
				other.position = vector.create(onCell(at.x, cell), at.y, onCell(at.z, cell))
				edged[other] = true
			elseif roll < TO_FAR then
				other.position = start + vector.create(between(-FAR, FAR), 0, between(-FAR, FAR))
			elseif roll < TO_TWIN then
				other.position = pick(bodies).position
			else
				place(other)
			end

			if math.random() < RESTYLED then
				restyle(other)
			end

			table.insert(moved, other)
		end

		local told: number = math.random()
		if told < BY_BODY then
			for _, other: any in moved do
				Hulls.moved(world, other)
			end
		elseif told < BY_REFRESH then
			Hulls.refresh(world)
		else
			local list: { any } = {}
			for _, other: any in bodies do
				if other == state or math.random() >= LEFT_OUT then
					table.insert(list, other)
				end
			end

			for _ = 1, math.random(0, 3) do
				local other: any = Scene.state(start, true)
				restyle(other)
				place(other)
				table.insert(list, math.random(#list + 1), other)
			end

			World.setBodies(world, list)
		end

		if #moved > 0 then
			movedRounds += 1
		end

		passed, reason = compare("after the moves")
		if not passed then
			return false, reason
		end
	end

	if
		hits < LEAST_HITS
		or ties < LEAST_TIES
		or gridded < LEAST_GRIDDED
		or edgeHits < LEAST_EDGE_HITS
		or blocked < LEAST_BLOCKS
		or overlapping < LEAST_OVERLAPS
		or movedRounds < LEAST_MOVED
	then
		local sweeps: string =
			`{hits} hits, {ties} ties, {gridded} sweeps on the grid, {edgeHits} hulls met on a cell line`
		local rest: string =
			`{blocked} blocked stands, {overlapping} overlapping boxes and {movedRounds} rounds after moves`

		return false, `The random set covered only {sweeps}, {rest}, under the least each needs`
	end

	return true, nil
end
