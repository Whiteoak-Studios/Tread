--[[
    Builds occluders, a solid part and terrain far from the dev game's
    content, checks which rays block and keep a box, again on a one-worker
    pool, casts segments a kept box settles at Block parts, and removes them all
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Casts = require(ReplicatedStorage.Packages.Tread.Server.AntiEspWorkers.Casts)
local Constants = require(ReplicatedStorage.Packages.Tread.Constants)
local Engine = require(ReplicatedStorage.Packages.Tread.Step.Engine)
local Pool = require(ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)

local CastsModule = ReplicatedStorage.Packages.Tread.Server.AntiEspWorkers.Casts -- What each pool's worker loads

local ORIGIN: Vector3 = Vector3.new(4000, 600, 4000) -- Far from the dev game's content and its plaza
local SPACING: number = 40 -- Studs between the lanes, one ray down each
local REACH: number = 30 -- How far each ray goes, through its block halfway along it
local BLOCK: Vector3 = Vector3.new(8, 8, 2) -- Each part's size, thin along its ray
local BALL: Vector3 = Vector3.new(8, 8, 8) -- The ball's, the same along every axis as a ball's must be
local TURN: CFrame = CFrame.Angles(math.rad(20), math.rad(30), 0) -- The turned occluder's, so its box has tilted axes
local TERRAIN: Vector3 = Vector3.new(12, 12, 12) -- Each terrain block's, whole voxels at its center
local VOXEL: number = 4 -- The voxel size ReadVoxels and WriteVoxels take
local HEARTBEAT_WAIT: number = 5 -- Seconds each wait for a Heartbeat may take before the scenario fails
local WORKER_WAIT: number = 10 -- Seconds the workers may take to be ready, and then to land their rays
local SEPARATOR: string = "; " -- Between the problems in one report
local POOL_PREFIX: string = "OcclusionWorkers" -- Each check's pool's folder under ServerScriptService starts so
local ROUND: number = 1 -- The one batch each pool is sent
local WORKER: number = 1 -- Each pool's one worker, its first
local PAIRS: number = 2 -- Each batch's pairs: the check's ray as a plain pair, as memory off packs it, then a learner
local RAYS: number = 1 -- And each pair's rays, the check's one
local PLAIN: number = 1 -- The plain pair's place in its batch, its count byte bare and its ray cast through occlusion
local LEARNER: number = 2 -- The learner's, which asks its worker for the box of the Block part that blocked it
local ALL_BLOCKED: number = 0 -- A pair's result when every ray of its was blocked
local LEARN: boolean = true -- The learner's flag

-- The box check: seeded segments Casts.crosses accepts against Block parts of mixed sizes and turns
local PLAY_BOUND: number = Constants.PLAY_BOUND
local HEIGHT_MIN: number = Constants.HEIGHT_MIN
local HEIGHT_MAX: number = Constants.HEIGHT_MAX
local INSET: number = Casts.INSET -- How far crosses shrinks a kept box and grows its skin
local BOX_SEED: number = 20261119 -- Any whole number, so every run casts the same set
local BOX_PARTS: number = 8 -- Parts at each of the check's places
local BOX_SEGMENTS: number = 80 -- Segments cast at each part, 1,920 in all
local BOX_TRIES: number = 40 -- Candidates a part may take for each segment it needs before the check gives up on it
local BOX_SPACING: number = 60 -- Studs between neighboring parts, past twice the farthest a part's segments reach
local BOX_MARGIN: number = 40 -- Studs a place at the play bound sits inside it and inside the top of the height window
local BOX_REACH: number = 4 -- The most studs a segment's ends run past the grown box
local BOX_AHEAD: Vector3 = Vector3.new(0, 0, 200) -- From ORIGIN to the first part here, past every lane's ray
local BOX_SIZES: { number } = { 0.04, 0.05, 0.1, 0.25, 0.5, 1, 2, 4, 8, 16 } -- Studs along a part's axis
local GRAZES: { number } = { 0, 1e-4, 1e-3, 4e-3 } -- Studs inside the shrunk box a grazing point sits
local SKINS: { number } = { 1e-3, 4e-3, 1e-2 } -- Studs outside the grown skin a skin segment starts

-- Studs outside the grown box a long segment starts, the fewest and the most, as an eye's ray to a target across the
-- relevancy distance runs
local LONG_BACK: number = 500
local LONG_REACH: number = 2000

-- A box check segment's kind, picked at random for each candidate
local THROUGH: number = 1 -- From outside the grown box, through a point anywhere in the shrunk one
local EDGE: number = 2 -- Through a point at the shrunk box's edge or corner, less a graze
local FACE: number = 3 -- Ending at a point just inside one of the shrunk box's faces, come in through it
local SKIN: number = 4 -- Starting just outside the grown skin
local LONG: number = 5 -- Through, from LONG_BACK to LONG_REACH studs back, toward the play bound on every world axis
local KINDS: number = 5

-- Where the box check's parts stand, one row at each along a direction: past this scenario's lanes, and at two
-- opposite corners of the play bound under the top of the height window, where positions round coarsest
local BOX_PLACES: { { at: Vector3, along: Vector3 } } = {
	{ at = ORIGIN + BOX_AHEAD, along = Vector3.new(1, 0, 0) },
	{
		at = Vector3.new(PLAY_BOUND - BOX_MARGIN, HEIGHT_MAX - BOX_MARGIN, BOX_MARGIN - PLAY_BOUND),
		along = Vector3.new(-1, 0, 0),
	},
	{
		at = Vector3.new(BOX_MARGIN - PLAY_BOUND, HEIGHT_MAX - BOX_MARGIN, PLAY_BOUND - BOX_MARGIN),
		along = Vector3.new(1, 0, 0),
	},
}

-- The lane each check's ray runs down
local OCCLUDER_LANE: number = 0
local CAMERA_LANE: number = 1
local SOLID_LANE: number = 2
local WATER_LANE: number = 3
local ROCK_LANE: number = 4
local TURNED_LANE: number = 5
local WEDGE_LANE: number = 6
local BALL_LANE: number = 7

--[[
    One ray's check: what its include list holds, its lane, whether it
    should be blocked, and whether what blocks it is a Block part whose box
    anti-ESP's verdict memory keeps
--]]

type Check = {
	name: string,
	include: { Instance },
	lane: number,
	blocked: boolean,
	boxed: boolean,
}

-- What a terrain block replaced, so it can be put back
type Saved = {
	region: Region3,
	materials: { { { Enum.Material } } },
	occupancies: { { { number } } },
}

-- Where a lane's ray starts, and the middle of its reach, where its block sits
local function start(lane: number): Vector3
	return ORIGIN + Vector3.new(lane * SPACING, 0, 0)
end

local function middle(lane: number): Vector3
	return start(lane) + Vector3.new(0, 0, REACH / 2)
end

-- A part across a lane's ray, anchored and queryable, colliding or not
local function block(name: string, lane: number, canCollide: boolean, parent: Instance): Part
	local made: Part = Instance.new("Part")
	made.Name = name
	made.Anchored = true
	made.CanCollide = canCollide
	made.CanQuery = true
	made.CanTouch = false
	made.Size = BLOCK
	made.CFrame = CFrame.new(middle(lane))
	made.Parent = parent

	return made
end

-- Fills a terrain block across a lane's ray with a material, keeping what its voxels held before
local function fill(lane: number, material: Enum.Material): Saved
	local terrain: Terrain = Workspace.Terrain
	local center: Vector3 = middle(lane)
	local region: Region3 = Region3.new(center - TERRAIN / 2, center + TERRAIN / 2):ExpandToGrid(VOXEL)
	local materials: { { { Enum.Material } } }, occupancies: { { { number } } } = terrain:ReadVoxels(region, VOXEL)

	terrain:FillBlock(CFrame.new(center), TERRAIN, material)

	return { region = region, materials = materials, occupancies = occupancies }
end

--[[
    Waits for the next Heartbeat, up to HEARTBEAT_WAIT seconds, and gives
    whether one came. A terrain ray meets a FillBlock or a WriteVoxels only
    from the next Heartbeat, so one cast sooner meets the terrain as it was
--]]

local function heartbeat(): boolean
	local came: boolean = false
	local connection: RBXScriptConnection = RunService.Heartbeat:Once(function ()
		came = true
	end)

	local deadline: number = os.clock() + HEARTBEAT_WAIT
	while not came and os.clock() < deadline do
		task.wait()
	end

	connection:Disconnect() -- Already gone once it fired, and dropped here when it never did

	return came
end

--[[
    Whether a filled block's voxels hold again what they held before it was
    filled, read by index, since ReadVoxels' arrays also carry a Size field
--]]

local function restored(put: Saved): boolean
	local materials: { { { Enum.Material } } }, occupancies: { { { number } } } =
		Workspace.Terrain:ReadVoxels(put.region, VOXEL)

	for x: number = 1, #put.materials do
		for y: number = 1, #put.materials[x] do
			for z: number = 1, #put.materials[x][y] do
				if materials[x][y][z] ~= put.materials[x][y][z] or occupancies[x][y][z] ~= put.occupancies[x][y][z] then
					return false
				end
			end
		end
	end

	return true
end

-- The share of a move along one axis, from a coordinate inside a slab of a half-width, at which it leaves the slab
local function exit(at: number, move: number, half: number): number
	if move > 0 then
		return (half - at) / move
	elseif move < 0 then
		return (-half - at) / move
	end

	return math.huge
end

-- How far along a direction a point inside a box of half-size grown leaves it, in the direction's lengths
local function leaving(point: Vector3, along: Vector3, grown: Vector3): number
	return math.min(exit(point.X, along.X, grown.X), exit(point.Y, along.Y, grown.Y), exit(point.Z, along.Z, grown.Z))
end

--[[
    The box check's Block parts, BOX_PARTS along each of its places,
    anchored and queryable, colliding with nothing, each turned at random
    and sized from BOX_SIZES, the first axis cycling through them all
--]]

local function boxParts(random: Random, parent: Instance): { Part }
	local parts: { Part } = {}

	for _, place in BOX_PLACES do
		for index: number = 1, BOX_PARTS do
			local size: Vector3 = Vector3.new(
				BOX_SIZES[#parts % #BOX_SIZES + 1],
				BOX_SIZES[random:NextInteger(1, #BOX_SIZES)],
				BOX_SIZES[random:NextInteger(1, #BOX_SIZES)]
			)
			local turn: CFrame = CFrame.Angles(
				random:NextNumber(-math.pi, math.pi),
				random:NextNumber(-math.pi, math.pi),
				random:NextNumber(-math.pi, math.pi)
			)

			local made: Part = Instance.new("Part")
			made.Name = `BoxCheck{#parts + 1}`
			made.Anchored = true
			made.CanCollide = false
			made.CanQuery = true
			made.CanTouch = false
			made.Size = size
			made.CFrame = CFrame.new(place.at + place.along * ((index - 1) * BOX_SPACING)) * turn
			made.Parent = parent
			table.insert(parts, made)
		end
	end

	return parts
end

-- Which way along one world axis leads away from the middle of the wire bounds from a coordinate, 1 from the middle
local function outward(coordinate: number): number
	return coordinate < 0 and -1 or 1
end

-- Whether a point is inside the wire bounds, so a segment between two such points lies inside them too
local function bounded(point: vector): boolean
	return math.abs(point.x) <= PLAY_BOUND
		and math.abs(point.z) <= PLAY_BOUND
		and point.y >= HEIGHT_MIN
		and point.y <= HEIGHT_MAX
end

--[[
    One candidate segment of a kind in a part's own space: a point inside
    its shrunk box, pushed to an edge, a corner or a face for those kinds, a
    direction at random, for a long one turned away from the middle of the
    wire bounds on every world axis so its far start lies nearer it, a start
    past the grown box behind the point, and an end past it ahead or, for a
    face, the point
--]]

local function candidate(random: Random, part: Part, kind: number): (Vector3, Vector3)
	local half: Vector3 = part.Size / 2
	local inners: { number } = { half.X - INSET, half.Y - INSET, half.Z - INSET }
	local grown: Vector3 = half + Vector3.one * INSET
	local point: { number } = {}
	for axis: number = 1, 3 do
		point[axis] = random:NextNumber(-1, 1) * math.max(inners[axis], 0)
	end

	local face: number = random:NextInteger(1, 3)
	local side: number = random:NextInteger(0, 1) * 2 - 1
	local graze: number = GRAZES[random:NextInteger(1, #GRAZES)]
	local unit: Vector3 = random:NextUnitVector()
	local direction: { number } = { unit.X, unit.Y, unit.Z }

	if kind == EDGE then
		-- The two axes off the face at a shrunk face each, along an edge, and at random the face's own, at a corner
		for axis: number = 1, 3 do
			if axis ~= face or random:NextInteger(0, 1) == 1 then
				point[axis] = (random:NextInteger(0, 1) * 2 - 1) * math.max(inners[axis] - graze, 0)
			end
		end
	elseif kind == FACE then
		point[face] = side * math.max(inners[face] - graze, 0)
		direction[face] = -side * math.abs(direction[face])
	elseif kind == LONG then
		local world: Vector3 = part.CFrame:VectorToWorldSpace(unit)
		local at: Vector3 = part.Position
		local away: Vector3 = Vector3.new(
			math.abs(world.X) * outward(at.X),
			math.abs(world.Y) * outward(at.Y),
			math.abs(world.Z) * outward(at.Z)
		)
		local turned: Vector3 = part.CFrame:VectorToObjectSpace(away)
		direction = { turned.X, turned.Y, turned.Z }
	end

	local inside: Vector3 = Vector3.new(point[1], point[2], point[3])
	local along: Vector3 = Vector3.new(direction[1], direction[2], direction[3])

	local beyond: number = random:NextNumber(0, BOX_REACH)
	if kind == SKIN then
		beyond = SKINS[random:NextInteger(1, #SKINS)]
	elseif kind == LONG then
		beyond = random:NextNumber(LONG_BACK, LONG_REACH)
	end

	local origin: Vector3 = inside - along * (leaving(inside, -along, grown) + beyond)
	local finish: Vector3 = inside
	if kind ~= FACE then
		finish = inside + along * (leaving(inside, along, grown) + random:NextNumber(0, BOX_REACH))
	end

	return origin, finish
end

--[[
    Casts BOX_SEGMENTS segments at each box check part through
    Engine.occluder, each one inside the wire bounds that Casts.crosses
    accepts against the part's box, and prints how many were cast, how many
    of them long, how many missed the part and met another. A long one's
    include list is its part alone, since from far back it may meet a
    neighbor first, and every other's is the check's. Adds a problem for any
    miss or other hit, and for a part the seed gives too few segments in its
    tries
--]]

local function boxCheck(random: Random, parts: { Part }, include: { Instance }, problems: { string })
	local occluder: (origin: vector, direction: vector) -> Instance? = Engine.occluder(include)
	local box: buffer = buffer.create(Casts.BOX_BYTES)
	local cast: number = 0
	local long: number = 0
	local misses: number = 0
	local others: number = 0
	local first: string? = nil -- The first miss or other hit, for the report

	for _, part: Part in parts do
		Casts.writeBox(box, 0, part)
		local alone: (origin: vector, direction: vector) -> Instance? = Engine.occluder({ part })
		local accepted: number = 0
		local tries: number = 0

		while accepted < BOX_SEGMENTS and tries < BOX_SEGMENTS * BOX_TRIES do
			tries += 1

			local kind: number = random:NextInteger(THROUGH, KINDS)
			local localOrigin: Vector3, localFinish: Vector3 = candidate(random, part, kind)
			local origin: vector = Engine.toVector(part.CFrame:PointToWorldSpace(localOrigin))
			local finish: vector = Engine.toVector(part.CFrame:PointToWorldSpace(localFinish))

			if bounded(origin) and bounded(finish) and Casts.crosses(box, 0, origin, finish) then
				accepted += 1
				cast += 1

				local met: Instance? = nil
				if kind == LONG then
					long += 1
					met = alone(origin, finish - origin)
				else
					met = occluder(origin, finish - origin)
				end

				if met == nil then
					misses += 1
				elseif met ~= part then
					others += 1
				end

				if met ~= part and first == nil then
					first = `{part.Name} of size {part.Size} from {origin} to {finish}, which met {met}`
				end
			end
		end

		if accepted < BOX_SEGMENTS then
			local gave: string = `{accepted} of its {BOX_SEGMENTS} segments in {tries} tries`
			table.insert(problems, `the box check's seed gave {part.Name} of size {part.Size} {gave}`)
		end
	end

	local counts: string = `{cast} box segments cast, {long} of them long, {misses} missed their part`
	print(`Occlusion: {counts} and {others} met another instance`)

	if misses > 0 or others > 0 then
		table.insert(problems, `{misses} box segments missed their part and {others} met another, first {first}`)
	elseif long == 0 then
		table.insert(problems, "the box check cast no long segment, so none from across the relevancy distance ran")
	end
end

--[[
    Asks done a Heartbeat apart until it says so or the deadline passes, and
    gives whether it did, each wait for a Heartbeat held to its own deadline
--]]

local function waitFor(deadline: number, done: () -> boolean): boolean
	while not done() do
		if os.clock() >= deadline or not heartbeat() then
			return false
		end
	end

	return true
end

--[[
    Casts each check's ray again through an anti-ESP pool of one worker,
    every pool at once, its include list handed across in the worker's
    setup, as a plain pair, as memory off packs it, and as a learner. Adds
    a problem for a pool not ready or not landed within WORKER_WAIT
    seconds, a failure, either pair's answer unlike the check's, a box from
    the plain pair, a learner's box unlike the check's or the one read in
    the serial phase, and a pool's folder left after. Every pool goes after
--]]

local function throughWorkers(checks: { Check }, boxes: { [number]: buffer }, problems: { string })
	local pools: { Pool.Pool } = {}
	local names: { string } = {}
	local shared: buffer = buffer.create(0)

	local ran: boolean, failure: any = pcall(function ()
		for index: number, check: Check in checks do
			local name: string = `{POOL_PREFIX}{index}`
			local settings: Casts.Settings = { include = check.include }
			table.insert(names, name)
			table.insert(pools, Pool.new(WORKER, name, CastsModule, settings))
		end

		local ready: boolean = waitFor(os.clock() + WORKER_WAIT, function (): boolean
			local all: boolean = true
			for _, pool: Pool.Pool in pools do
				all = pool:ready() == WORKER and all
			end

			return all
		end)

		if not ready then
			table.insert(problems, `the one-worker anti-ESP pools were not all ready within {WORKER_WAIT} s`)

			return
		end

		for index: number, pool: Pool.Pool in pools do
			local origin: vector = Engine.toVector(start(checks[index].lane))
			local origins: { vector } = { origin }
			local ends: { vector } = { origin + vector.create(0, 0, REACH) }
			local size: number = Casts.HEADER_BYTES + PAIRS * Casts.pairSize(RAYS)
			local packed: buffer = buffer.create(size)
			local learner: number = Casts.writePair(packed, Casts.HEADER_BYTES, RAYS, origins, ends)
			Casts.writePair(packed, learner, RAYS, origins, ends, LEARN)

			pool:send(WORKER, ROUND, shared, Casts.batch(packed, size, PAIRS))
		end

		local landed: boolean = waitFor(os.clock() + WORKER_WAIT, function (): boolean
			for _, pool: Pool.Pool in pools do
				local results: buffer?, failed: string? = pool:landed(WORKER, ROUND)
				if results == nil and failed == nil then
					return false
				end
			end

			return true
		end)

		if not landed then
			table.insert(problems, `the one-worker anti-ESP pools had not all landed within {WORKER_WAIT} s`)

			return
		end

		-- A learner's worker reads the hit's Instance, its class, Shape, Size and CFrame desynchronized, so a read the
		-- engine refuses in parallel lands as failure text. The plain pair sends none, so the learner's box is the first
		local boxAt: number = PAIRS * Casts.RESULT_BYTES
		for index: number, pool: Pool.Pool in pools do
			local results: buffer?, failed: string? = pool:landed(WORKER, ROUND)
			local check: Check = checks[index]
			local serial: buffer? = boxes[index]
			local expected: string = check.blocked and "blocked" or "open"

			if results == nil then
				table.insert(problems, `the worker's rays through {check.name} failed: {failed}`)
			elseif (Casts.opened(results, PLAIN) == ALL_BLOCKED) ~= check.blocked then
				table.insert(problems, `the worker's plain ray through {check.name} was not {expected}`)
			elseif Casts.boxed(results, PLAIN) then
				table.insert(problems, `the worker's plain ray through {check.name} sent back a box`)
			elseif (Casts.opened(results, LEARNER) == ALL_BLOCKED) ~= check.blocked then
				table.insert(problems, `the worker's learning ray through {check.name} was not {expected}`)
			elseif Casts.boxed(results, LEARNER) ~= check.boxed then
				local sent: string = check.boxed and "no box" or "a box"
				table.insert(problems, `the worker's learning ray through {check.name} sent back {sent}`)
			elseif serial and buffer.readstring(results, boxAt, Casts.BOX_BYTES) ~= buffer.tostring(serial) then
				table.insert(problems, `the worker's box of {check.name} was not the serial phase's, bit for bit`)
			end
		end
	end)

	if not ran then
		table.insert(problems, `the workers' checks threw: {failure}`)
	end

	for _, pool: Pool.Pool in pools do
		pool:destroy()
	end

	for _, name: string in names do
		if ServerScriptService:FindFirstChild(name) then
			table.insert(problems, `the pool folder {name} was left in ServerScriptService`)
		end
	end
end

return function (): (boolean, string | nil)
	local problems: { string } = {}
	local terrain: Terrain = Workspace.Terrain

	local root: Folder = Instance.new("Folder")
	root.Name = "Occlusion"

	-- The design's occluder folder, held under a Camera, which never replicates
	local holder: Camera = Instance.new("Camera")
	holder.Name = "OcclusionHolder"
	local held: Folder = Instance.new("Folder")
	held.Name = "Occluders"
	held.Parent = holder

	local occluders: Folder = Instance.new("Folder")
	occluders.Name = "Occluders"
	occluders.Parent = root

	local outside: Folder = Instance.new("Folder")
	outside.Name = "Outside"
	outside.Parent = root

	block("Occluder", OCCLUDER_LANE, false, occluders)
	block("HeldOccluder", CAMERA_LANE, false, held)
	block("Solid", SOLID_LANE, true, outside)

	-- Verdict memory keeps the box of a turned Block part, and none of a wedge's or a ball's
	local turned: Part = block("TurnedOccluder", TURNED_LANE, false, occluders)
	turned.CFrame = CFrame.new(middle(TURNED_LANE)) * TURN

	local ball: Part = block("BallOccluder", BALL_LANE, false, occluders)
	ball.Shape = Enum.PartType.Ball
	ball.Size = BALL

	local wedge: WedgePart = Instance.new("WedgePart")
	wedge.Name = "WedgeOccluder"
	wedge.Anchored = true
	wedge.CanCollide = false
	wedge.CanQuery = true
	wedge.CanTouch = false
	wedge.Size = BLOCK
	wedge.CFrame = CFrame.new(middle(WEDGE_LANE))
	wedge.Parent = occluders

	-- The box check's parts in a folder of their own, there from the same Heartbeat as every other lane's
	local checked: Folder = Instance.new("Folder")
	checked.Name = "OcclusionBoxes"
	local random: Random = Random.new(BOX_SEED)
	local boxed: { Part } = boxParts(random, checked)

	root.Parent = Workspace
	holder.Parent = Workspace
	checked.Parent = Workspace

	local saved: { Saved } = {}
	local ran: boolean, failure: any = pcall(function ()
		table.insert(saved, fill(WATER_LANE, Enum.Material.Water))
		table.insert(saved, fill(ROCK_LANE, Enum.Material.Rock))

		if not heartbeat() then
			table.insert(problems, `no Heartbeat within {HEARTBEAT_WAIT} s of the terrain fills, so no ray was cast`)

			return
		end

		-- The water lane holds water, so its open result below is the water's and never an empty lane's
		local withWater: RaycastParams = RaycastParams.new()
		withWater.FilterType = Enum.RaycastFilterType.Include
		withWater.FilterDescendantsInstances = { terrain }
		withWater.IgnoreWater = false

		local wet: RaycastResult? = Workspace:Raycast(start(WATER_LANE), Vector3.new(0, 0, REACH), withWater)
		if not wet or wet.Material ~= Enum.Material.Water then
			table.insert(problems, "a ray down the water lane, water counted, met no terrain water")
		end

		local checks: { Check } = {
			{
				name = "a CanCollide-off occluder in the include list",
				include = { occluders },
				lane = OCCLUDER_LANE,
				blocked = true,
				boxed = true,
			},
			{
				name = "a CanCollide-off occluder held under a Camera",
				include = { held },
				lane = CAMERA_LANE,
				blocked = true,
				boxed = true,
			},
			{
				name = "a CanCollide-on part outside the include list",
				include = { occluders, held, terrain },
				lane = SOLID_LANE,
				blocked = false,
				boxed = false,
			},
			{
				name = "that part with its folder included",
				include = { outside },
				lane = SOLID_LANE,
				blocked = true,
				boxed = true,
			},
			{ name = "terrain water", include = { terrain }, lane = WATER_LANE, blocked = false, boxed = false },
			{ name = "solid terrain", include = { terrain }, lane = ROCK_LANE, blocked = true, boxed = false },
			{
				name = "a turned Block occluder",
				include = { occluders },
				lane = TURNED_LANE,
				blocked = true,
				boxed = true,
			},
			{ name = "a wedge occluder", include = { occluders }, lane = WEDGE_LANE, blocked = true, boxed = false },
			{ name = "a ball occluder", include = { occluders }, lane = BALL_LANE, blocked = true, boxed = false },
		}

		-- Each Block part's box as the server's own script reads it, for the workers' to match
		local boxes: { [number]: buffer } = {}

		for index: number, check: Check in checks do
			local occluder: (origin: vector, direction: vector) -> Instance? = Engine.occluder(check.include)
			local blocked: (origin: vector, direction: vector) -> boolean = Engine.occlusion(check.include)
			local origin: vector = Engine.toVector(start(check.lane))
			local direction: vector = vector.create(0, 0, REACH)
			local met: Instance? = occluder(origin, direction)

			local part: Part? = nil
			if met ~= nil then
				part = Casts.blocker(met)
			end

			if (met ~= nil) ~= check.blocked or blocked(origin, direction) ~= check.blocked then
				local expected: string = check.blocked and "blocked" or "open"
				table.insert(problems, `a ray through {check.name} was not {expected}, by occluder or occlusion`)
			elseif (part ~= nil) ~= check.boxed then
				local kept: string = check.boxed and "kept no box" or "kept a box"
				table.insert(problems, `a ray through {check.name} met {met} and {kept}`)
			elseif part then
				local box: buffer = buffer.create(Casts.BOX_BYTES)
				Casts.writeBox(box, 0, part)
				boxes[index] = box
			end
		end

		-- The same rays cast desynchronized on an Actor worker, against the same parts and terrain
		throughWorkers(checks, boxes, problems)

		-- The step's own casts respect CanCollide, so the same occluder never stops a body or its eye
		local casts: State.Collision = Engine.collision({ occluders })
		local through: State.Hit? = casts.ray(Engine.toVector(start(OCCLUDER_LANE)), vector.create(0, 0, REACH))
		casts.destroy()

		if through ~= nil then
			table.insert(problems, "the step's ray met the CanCollide-off occluder")
		end

		-- Every segment a kept box settles with no engine ray meets that box's part on the engine too
		boxCheck(random, boxed, { checked }, problems)
	end)

	if not ran then
		table.insert(problems, `the checks threw: {failure}`)
	end

	-- Everything it made goes, the terrain it filled put back as it was, whatever the checks did
	for _, put: Saved in saved do
		terrain:WriteVoxels(put.region, VOXEL, put.materials, put.occupancies)

		if not restored(put) then
			table.insert(problems, `the terrain at {put.region.CFrame.Position} was not put back as it was`)
		end
	end

	-- So the next scenario's rays never meet the terrain this one filled
	if not heartbeat() then
		table.insert(problems, `no Heartbeat within {HEARTBEAT_WAIT} s of the terrain being put back`)
	end

	root:Destroy()
	holder:Destroy()
	checked:Destroy()

	if
		Workspace:FindFirstChild("Occlusion")
		or Workspace:FindFirstChild("OcclusionHolder")
		or Workspace:FindFirstChild("OcclusionBoxes")
	then
		table.insert(problems, "a part or folder it made was left in Workspace")
	end

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, nil
end
