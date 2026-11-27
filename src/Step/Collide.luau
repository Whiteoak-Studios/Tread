--[[
    Collide-and-slide for the box hull against the world and the other live
    hulls, with the step up, the ground snap and probe, depenetration, and
    the clear test a stand-up or an overlap check reads
--]]

--!strict
--!native
local Constants = require(script.Parent.Parent.Constants)
local Hulls = require(script.Parent.Hulls)
local Math = require(script.Parent.Math)
local State = require(script.Parent.State)

local SKIN: number = Constants.SKIN
local MAX_BUMPS: number = Constants.MAX_BUMPS
local MIN_MOVE: number = Constants.POSITION_QUANTUM -- A move shorter than one quantum is dropped instead of cast
local SKINS: number = 2 * SKIN -- The body's skin and the ground's, within which a resting body always finds its ground
local HALF_SKIN: number = SKIN / 2 -- Ground a step-up lands on closer than this was pressed into, not climbed
local CAST_REACH: number = Constants.CAST_REACH
local MIN_CREASE: number = Constants.MIN_CREASE
local DEPENETRATION_FIRST: number = Constants.DEPENETRATION_FIRST
local DEPENETRATION_STEPS: number = Constants.DEPENETRATION_STEPS
local AIR: Enum.Material = Enum.Material.Air -- The ground's material off the ground, or on another body's hull

-- Depenetration's level offsets at each distance: the four axes, then the four diagonals
local LEVEL: { vector } = {
	vector.create(1, 0, 0),
	vector.create(-1, 0, 0),
	vector.create(0, 0, 1),
	vector.create(0, 0, -1),
	vector.create(1, 0, 1),
	vector.create(1, 0, -1),
	vector.create(-1, 0, 1),
	vector.create(-1, 0, -1),
}

type Hit = State.Hit
type Settings = State.Settings
type State = State.State
type World = State.World

local Collide = {}

-- The body a move is moving, in numbers, loaded from its state and written back
local px: number, py: number, pz: number = 0, 0, 0
local vx: number, vy: number, vz: number = 0, 0, 0
local blocked: boolean = false -- Whether a slide met a surface too steep to walk that a step up might clear
local stepTop: number = 0 -- The highest hull top a step up from where the walk started can clear

-- The last cast's hit, in numbers, and the body whose hull it met, if any
local hitDistance: number = 0
local hitNormalX: number, hitNormalY: number, hitNormalZ: number = 0, 0, 0
local hitMaterial: Enum.Material = AIR
local hitBody: State? = nil

--[[
    The cast boundary: sweeps the hull from its center by a move against the
    world's geometry and the other live hulls, and keeps the nearer hit
--]]

local function cast(
	state: State,
	world: World,
	size: vector,
	centerX: number,
	centerY: number,
	centerZ: number,
	moveX: number,
	moveY: number,
	moveZ: number
): boolean
	local center: vector = vector.create(centerX, centerY, centerZ)
	local direction: vector = vector.create(moveX, moveY, moveZ)
	local found: Hit? = world.collision.sweep(center, size, direction)
	local hullDistance: number, hullNormal: vector, hullBody: State? =
		Hulls.sweep(state, center, size, direction, world)

	if found and found.distance <= hullDistance then
		local normal: vector = found.normal
		hitDistance = found.distance
		hitNormalX, hitNormalY, hitNormalZ = normal.x, normal.y, normal.z
		hitMaterial = found.material
		hitBody = nil

		return true
	elseif hullBody then
		hitDistance = hullDistance
		hitNormalX, hitNormalY, hitNormalZ = hullNormal.x, hullNormal.y, hullNormal.z
		hitMaterial = AIR
		hitBody = hullBody

		return true
	end

	return false
end

--[[
    How far along the last cast the body may go and keep a whole skin to the
    surface it hit, measured along that surface's normal, from the cosine of
    its approach. A cast that met a surface it is not moving toward holds
--]]

local function stopAt(facing: number): number
	if facing <= 0 then
		return 0
	end

	return math.max(hitDistance - SKIN / facing, 0)
end

-- Sets the state's ground from the last cast, which found it, or clears it
local function setGround(state: State, found: boolean)
	state.grounded = found

	if found then
		state.groundNormal = vector.create(hitNormalX, hitNormalY, hitNormalZ)
		state.groundMaterial = hitMaterial
	else
		state.groundNormal = vector.zero
		state.groundMaterial = AIR
	end
end

--[[
    Collide-and-slide: moves the body by a move in up to the bump cap's hits,
    each stopping it a skin short of the surface along its normal and sliding
    the rest, and the velocity, along it, or along the crease where two
    surfaces meet. A level move takes a surface too steep to walk as a wall
--]]

local function slide(
	state: State,
	world: World,
	moveX: number,
	moveY: number,
	moveZ: number,
	size: vector,
	half: number,
	level: boolean
)
	local walkable: number = world.settings.walkable
	local planes: number = 0
	local previousX: number, previousY: number, previousZ: number = 0, 0, 0
	local olderX: number, olderY: number, olderZ: number = 0, 0, 0

	for _ = 1, MAX_BUMPS do
		local length: number = math.sqrt(moveX * moveX + moveY * moveY + moveZ * moveZ)
		if length < MIN_MOVE then
			return
		end

		-- The cast reaches past the move, so a surface the move would end under a skin from stops it too
		local stretch: number = (length + CAST_REACH) / length
		local hit: boolean =
			cast(state, world, size, px, py + half, pz, moveX * stretch, moveY * stretch, moveZ * stretch)
		local facing: number = 0
		local travel: number = length

		if hit then
			facing = -(moveX * hitNormalX + moveY * hitNormalY + moveZ * hitNormalZ) / length
			travel = stopAt(facing)
		end

		-- Free when it ends a skin or more from what lies past it, or past a surface it is not moving toward
		if not hit or travel >= length or (facing <= 0 and hitDistance > length) then
			px += moveX
			py += moveY
			pz += moveZ

			return
		end

		local normalX: number, normalY: number, normalZ: number = hitNormalX, hitNormalY, hitNormalZ

		if normalY < walkable then
			-- A hull whose top is past a step's reach is never cleared by one, so only the rest call for the step up
			local body: State? = hitBody
			if not body or body.position.y + Hulls.height(body, world.settings) <= stepTop then
				blocked = true
			end

			-- Seen from the ground, a surface too steep to walk is a wall
			local flat: number = math.sqrt(normalX * normalX + normalZ * normalZ)
			if level and flat > MIN_CREASE then
				normalX /= flat
				normalY = 0
				normalZ /= flat
			end
		end

		-- Stop a skin short of the surface, then slide what is left of the move, and the velocity, along it
		local share: number = travel / length
		local left: number = 1 - share

		px += moveX * share
		py += moveY * share
		pz += moveZ * share
		moveX *= left
		moveY *= left
		moveZ *= left

		local into: number = moveX * normalX + moveY * normalY + moveZ * normalZ
		if into < 0 then
			moveX -= normalX * into
			moveY -= normalY * into
			moveZ -= normalZ * into
		end

		local velocityInto: number = vx * normalX + vy * normalY + vz * normalZ
		if velocityInto < 0 then
			vx -= normalX * velocityInto
			vy -= normalY * velocityInto
			vz -= normalZ * velocityInto
		end

		planes += 1

		-- Sliding back into the surface before means a crease, so the move runs along the line they meet on
		if planes > 1 and moveX * previousX + moveY * previousY + moveZ * previousZ < 0 then
			local creaseX: number = previousY * normalZ - previousZ * normalY
			local creaseY: number = previousZ * normalX - previousX * normalZ
			local creaseZ: number = previousX * normalY - previousY * normalX
			local creaseSquared: number = creaseX * creaseX + creaseY * creaseY + creaseZ * creaseZ

			if creaseSquared < MIN_CREASE * MIN_CREASE then
				return
			end

			local along: number = (moveX * creaseX + moveY * creaseY + moveZ * creaseZ) / creaseSquared
			moveX = creaseX * along
			moveY = creaseY * along
			moveZ = creaseZ * along
		end

		-- Boxed in by three surfaces, it goes no farther
		if planes > 2 and moveX * olderX + moveY * olderY + moveZ * olderZ < 0 then
			return
		end

		olderX, olderY, olderZ = previousX, previousY, previousZ
		previousX, previousY, previousZ = normalX, normalY, normalZ
	end
end

--[[
    A grounded body's move: a level slide, and when a surface too steep to
    walk stopped it, the world's or a hull a step's height can clear, the
    same slide a step's height up and back down onto walkable ground, kept
    when it got farther. Then the ground snap follows the ground down a
    step's height, or the body leaves the ground
--]]

local function walk(state: State, world: World, moveX: number, moveZ: number, size: vector, half: number): State?
	local settings: Settings = world.settings
	local startX: number, startY: number, startZ: number = px, py, pz
	local startVX: number, startVY: number, startVZ: number = vx, vy, vz

	blocked = false
	stepTop = py + settings.stepHeight
	slide(state, world, moveX, 0, moveZ, size, half, true)

	if blocked and settings.stepHeight > 0 then
		local plainX: number, plainY: number, plainZ: number = px, py, pz
		local plainVX: number, plainVY: number, plainVZ: number = vx, vy, vz
		local plainReach: number = (plainX - startX) * (plainX - startX) + (plainZ - startZ) * (plainZ - startZ)
		px, py, pz = startX, startY, startZ
		vx, vy, vz = startVX, startVY, startVZ

		-- Up by a step's height, short of any ceiling, then the same slide
		local lift: number = settings.stepHeight
		if cast(state, world, size, px, py + half, pz, 0, lift, 0) then
			lift = stopAt(-hitNormalY)
		end

		py += lift
		slide(state, world, moveX, 0, moveZ, size, half, true)

		-- A landing under half a skin down means a cast up there missed a shallow contact and the hull is already in
		local stepped: boolean = false
		local landing: boolean = cast(state, world, size, px, py + half, pz, 0, -(lift + SKINS), 0)
		if landing and hitNormalY >= settings.walkable and hitDistance * hitNormalY >= HALF_SKIN then
			py -= stopAt(hitNormalY)
			stepped = (px - startX) * (px - startX) + (pz - startZ) * (pz - startZ) > plainReach
		end

		if not stepped then
			px, py, pz = plainX, plainY, plainZ
			vx, vy, vz = plainVX, plainVY, plainVZ
		end
	end

	local reach: number = settings.stepHeight + SKINS
	if cast(state, world, size, px, py + half, pz, 0, -reach, 0) and hitNormalY >= settings.standable then
		py -= stopAt(hitNormalY)
		setGround(state, true)

		return hitBody
	end

	setGround(state, false)

	return nil
end

--[[
    An airborne body's move: a slide along every surface it meets, then the
    ground probe, which lands a body moving down on ground it stands on
    within a skin or two under it
--]]

local function fall(
	state: State,
	world: World,
	moveX: number,
	moveY: number,
	moveZ: number,
	size: vector,
	half: number
): State?
	slide(state, world, moveX, moveY, moveZ, size, half, false)

	local probed: boolean = moveY <= 0 and cast(state, world, size, px, py + half, pz, 0, -SKINS, 0)
	if probed and hitNormalY >= world.settings.standable then
		py -= stopAt(hitNormalY)
		vy = math.max(vy, 0)
		setGround(state, true)

		return hitBody
	end

	setGround(state, false)

	return nil
end

--[[
    Moves a body by delta, the move its velocity makes this tick: on the
    ground its level part, with the step up and the snap, and in the air all
    of it, with the ground probe. Writes its position, its velocity less what
    pressed into surfaces, its ground and, on the ground, the height it last
    stood at, and gives back the body whose hull top it ends standing on
--]]

function Collide.move(state: State, delta: vector, world: World): State?
	-- A value less itself is 0 only when the value is finite
	if not (delta.x - delta.x == 0 and delta.y - delta.y == 0 and delta.z - delta.z == 0) then
		error(`A move must be finite on every axis, and got {delta}`)
	end

	local settings: Settings = world.settings
	local height: number = Hulls.height(state, settings)
	local width: number = settings.radius + settings.radius
	local size: vector = vector.create(width, height, width)
	local half: number = height / 2

	local feet: vector = state.position
	local velocity: vector = state.velocity
	px, py, pz = feet.x, feet.y, feet.z
	vx, vy, vz = velocity.x, velocity.y, velocity.z

	local standingOn: State?
	if state.grounded then
		standingOn = walk(state, world, delta.x, delta.z, size, half)
	else
		standingOn = fall(state, world, delta.x, delta.y, delta.z, size, half)
	end

	state.position = vector.create(px, py, pz)
	state.velocity = vector.create(vx, vy, vz)

	-- A mantle's reach counts from here, which nothing else keeps once the body leaves the ground
	if state.grounded then
		state.groundHeight = state.position.y
	end

	return standingOn
end

--[[
    Whether a box at center is clear of the world's geometry: overlapping no
    collision part, and not sunk below the rest height under it. Touching
    counts as clear
--]]

function Collide.clear(center: vector, size: vector, world: World): boolean
	if not (size.x > 0 and size.y > 0 and size.z > 0) then
		error(`A box needs a size above 0 on every axis, and got {size}`)
	end

	if world.collision.overlap(center, size) then
		return false
	end

	local rest: number? = world.collision.rest(center, size)
	if rest and rest > center.y - size.y / 2 then
		return false
	end

	return true
end

--[[
    Whether a body's hull is clear, of the world and of the other live hulls,
    with its feet at x, y, z rounded to the quantum, leaving it there. The
    rounded spot is tested, since the end-of-step rounding would otherwise
    carry a hull beside a face turned off the axes back into it
--]]

local function settles(state: State, world: World, size: vector, half: number, x: number, y: number, z: number): boolean
	local feet: vector = vector.create(Math.quantize(x), Math.quantize(y), Math.quantize(z))
	state.position = feet

	return Collide.clear(vector.create(feet.x, feet.y + half, feet.z), size, world) and not Hulls.block(state, world)
end

--[[
    Finds a body inside geometry and moves it to the first clear spot on the
    quantum: up by how far it sank, then at each growing distance up, along
    the four axes and along the four diagonals. The rest height is checked
    every time, and the exact overlap query when exact is set. Gives back
    nil when the body is clear or was moved clear, and when no spot is
    clear, leaves it where it was and gives how far it sank, 0 when it sank
    none
--]]

function Collide.depenetrate(state: State, world: World, exact: boolean): number?
	local settings: Settings = world.settings
	local height: number = Hulls.height(state, settings)
	local width: number = settings.radius + settings.radius
	local size: vector = vector.create(width, height, width)
	local half: number = height / 2
	local feet: vector = state.position
	local center: vector = vector.create(feet.x, feet.y + half, feet.z)

	local depth: number = 0
	local rest: number? = world.collision.rest(center, size)
	if rest and rest > feet.y then
		depth = rest - feet.y
	end

	local inside: boolean = depth > 0
	if not inside and exact then
		inside = world.collision.overlap(center, size)
	end

	if not inside then
		inside = Hulls.block(state, world)
	end

	if not inside then
		return nil
	end

	if depth > 0 and settles(state, world, size, half, feet.x, feet.y + depth + SKIN, feet.z) then
		return nil
	end

	local reach: number = DEPENETRATION_FIRST * width
	for _ = 1, DEPENETRATION_STEPS do
		if settles(state, world, size, half, feet.x, feet.y + reach, feet.z) then
			return nil
		end

		for _, way: vector in LEVEL do
			if settles(state, world, size, half, feet.x + way.x * reach, feet.y, feet.z + way.z * reach) then
				return nil
			end
		end

		reach += reach -- Each distance twice the one before
	end

	state.position = feet

	return depth
end

return Collide
