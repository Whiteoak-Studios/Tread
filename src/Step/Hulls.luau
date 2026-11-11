--[[
    The hull tests between bodies: a box swept against the other live hulls,
    whether a hull overlaps one where it stands, and an oriented box against
    every live hull, all on the axis-aligned box the hull radius gives
--]]

--!strict
--!native
local Constants = require(script.Parent.Parent.Constants)
local State = require(script.Parent.State)

local REJECT_MARGIN: number = Constants.SKIN -- Studs a sweep's bounds reach past its slab tests, far over rounding

type Box = State.Box
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

--[[
    Sweeps a box from center along direction against the hulls of the other
    live bodies, and gives the distance to the nearest it meets, math.huge
    for none, the normal of the face it meets and that body. As an engine
    cast ignores a part it starts inside, a hull the box starts in is
    skipped, and a body that walks in no mode meets none
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

	-- Whiteoak TODO: each cast walks every live hull the world holds, passing one outside those bounds before any slab
	-- test, so a tick's walks grow with the square of the bodies; a uniform grid of hull positions, which each step
	-- updates as its body moves, narrows each walk to the nearby ones
	for _, other: State in world.bodies do
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

			if enter >= 0 and enter < exit and enter <= 1 and enter * length < nearest then
				nearest = enter * length
				body = other

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

	for _, other: State in world.bodies do
		-- The cheap compares first, so a hull apart on X or Z is passed before its mode or posture is read
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

	for _, other: State in world.bodies do
		if other.moveMode == "Walk" then
			local half: number = Hulls.height(other, settings) / 2
			local at: vector = other.position
			hullHalf = vector.create(radius, half, radius)
			offset = vector.create(at.x, at.y + half, at.z) - box.center

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
