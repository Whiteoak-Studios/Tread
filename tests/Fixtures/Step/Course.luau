--[[
    The movement modes' fixture course above 1,000 studs: mantle ledges, a
    pool with its shelves and edge, and a ladder against a block, with the
    worlds, states and checks the modes' trials build from them
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Casts = require(script.Parent.Collision)
local Constants = require(ReplicatedStorage.Packages.Tread.Constants)
local Geometry = require(script.Parent.Geometry)
local Math = require(ReplicatedStorage.Packages.Tread.Step.Math)
local Scene = require(script.Parent.Scene)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)
local Step = require(ReplicatedStorage.Packages.Tread.Step)
local World = require(ReplicatedStorage.Packages.Tread.Step.World)

local SIMULATION_RATE: number = 20 -- Frontier Zero's rates.simulation, in Hz
local SKIN: number = Constants.SKIN
local QUANTUM: number = Constants.POSITION_QUANTUM
local TOLERANCE: number = SKIN / 4 -- How far an ending may sit from where it should, well inside the skin it keeps
local MARGIN: number = 1 / 32 -- How far each shelf's depth sits to either side of a swim depth
local FLOOR: number = 1100 -- The course floor's top
local SETTINGS = Scene.settings
local RADIUS: number = SETTINGS.radius

-- The mantle ledges: a row each along Z, their faces at one X, met walking along +X
local FACE: number = 110
local LEDGE_DEPTH: number = 6 -- Along X, past the face
local ROW_WIDTH: number = 6 -- Along Z
local CEILING_THICKNESS: number = 1
local LOW_ROOM: number = 4 -- Over the low row's top: room for the crouched hull and not the standing one
local TIGHT_ROOM: number = 3 -- Over the tight row's top: room for neither

-- The pool: water over a region of the floor, shelves at depths either side of the swim depths, and its edge
local SURFACE: number = FLOOR + 10
local POOL_START: number = 130 -- X where the water starts
local POOL_EDGE: number = 170 -- X where the edge's face stands and the water ends
local POOL_HALF: number = 45 -- The water's half width along Z
local EDGE_RISE: number = 1.5 -- The edge's top over the surface
local SHELF_X: number = 136 -- The shelves' center along X
local SHELF_LENGTH: number = 8
local DEEP_DEPTH: number = 2.5 -- Feet this deep refuse a crouch
local SHALLOW_DEPTH: number = 2 -- And this deep allow one

-- The ladder: a box against the face of a block whose top is the floor above it
local BLOCK_FACE: number = 195
local BLOCK_HEIGHT: number = 10
local LADDER_DEPTH: number = 0.5 -- Its box's thickness out from the block's face
local LADDER_WIDTH: number = 2
local LADDER_SHIFT: number = 1.5 -- The second, overlapping ladder's offset along Z

type Allow = State.Allow
type Collision = State.Collision
type Command = State.Command
type Part = Geometry.Part
type RuleStep = State.RuleStep
type Rules = State.Rules
type State = State.State
type World = State.World

-- A ladder as the game registers it
export type LadderPlace = {
	cframe: CFrame,
	size: Vector3,
}

local Course = {}

Course.settings = SETTINGS
Course.floor = FLOOR
Course.resting = Math.quantize(FLOOR + SKIN) -- Feet at rest on the floor, on the quanta, and the height they keep as ground
Course.surface = SURFACE
Course.float = Math.quantize(SURFACE - SETTINGS.floatDepth) -- An idle swimmer's feet, on the quanta
Course.east = -math.pi / 2 -- A yaw that looks along +X
Course.west = math.pi / 2 -- A yaw that looks along -X
Course.tolerance = TOLERANCE
Course.quantum = QUANTUM
Course.face = FACE
Course.approach = Math.quantize(FACE - RADIUS - SKIN) -- Feet whose hull front stands a skin from the ledges' face
Course.ticks = math.max(math.round(SETTINGS.mantleTime * SIMULATION_RATE), 1) -- A mantle's ticks
Course.over = 2 * RADIUS + 2 * SKIN -- How far a mantle goes past the face
Course.poolEdge = POOL_EDGE
Course.edgeTop = SURFACE + EDGE_RISE
Course.blockFace = BLOCK_FACE
Course.blockTop = FLOOR + BLOCK_HEIGHT

-- A box part by its center's X and Z, its bottom and top, its depth along X and its width along Z
local function box(name: string, x: number, z: number, bottom: number, top: number, depth: number, width: number): Part
	return {
		name = name,
		center = vector.create(x, (bottom + top) / 2, z),
		size = vector.create(depth, top - bottom, width),
		tilt = 0,
	}
end

-- A mantle row's ledge, from the face along +X, centered on z
local function ledge(name: string, z: number, top: number): Part
	return box(name, FACE + LEDGE_DEPTH / 2, z, FLOOR, top, LEDGE_DEPTH, ROW_WIDTH)
end

-- A ceiling over a row's ledge, its underside room over the ledge's top
local function ceiling(name: string, row: Part, room: number): Part
	local underside: number = row.center.y + row.size.y / 2 + room

	return box(name, row.center.x, row.center.z, underside, underside + CEILING_THICKNESS, LEDGE_DEPTH, ROW_WIDTH)
end

-- A shelf in the pool whose top lies depth under the surface
local function shelf(name: string, z: number, depth: number): Part
	return box(name, SHELF_X, z, FLOOR, SURFACE - depth, SHELF_LENGTH, ROW_WIDTH)
end

local function top(part: Part): number
	return part.center.y + part.size.y / 2
end

local ground: number = Course.resting

-- The rows, each by its own Z
local rows = {
	exact = ledge("Exact", -36, ground + SETTINGS.mantleHeight), -- Its top exactly the reach over the last ground
	past = ledge("Past", -27, ground + SETTINGS.mantleHeight + QUANTUM), -- One quantum past the reach
	low = ledge("Low", -18, FLOOR + 2),
	tight = ledge("Tight", -9, FLOOR + 2),
	halfwall = ledge("Halfwall", 0, FLOOR + 5),
	step = ledge("Step", 9, FLOOR + 0.5), -- No higher than the walk steps up
	blocked = ledge("Blocked", 18, FLOOR + 3),
	plain = ledge("Plain", 27, FLOOR + 3),
}

local shelves = {
	enterBelow = shelf("EnterBelow", -36, SETTINGS.swimEnter - MARGIN),
	enterAbove = shelf("EnterAbove", -27, SETTINGS.swimEnter + MARGIN),
	leaveAbove = shelf("LeaveAbove", -18, SETTINGS.swimLeave + MARGIN),
	leaveBelow = shelf("LeaveBelow", -9, SETTINGS.swimLeave - MARGIN),
	deep = shelf("Deep", 0, DEEP_DEPTH + SKIN), -- Feet at rest on it stand DEEP_DEPTH under the surface
	shallow = shelf("Shallow", 9, SHALLOW_DEPTH + SKIN),
}

Course.rows = rows
Course.shelves = shelves
Course.top = top

Course.parts = {
	box("CourseFloor", 150, 0, FLOOR - 2, FLOOR, 120, 2 * POOL_HALF),
	rows.exact,
	rows.past,
	rows.low,
	ceiling("LowCeiling", rows.low, LOW_ROOM),
	rows.tight,
	ceiling("TightCeiling", rows.tight, TIGHT_ROOM),
	rows.halfwall,
	rows.step,
	rows.blocked,
	rows.plain,
	shelves.enterBelow,
	shelves.enterAbove,
	shelves.leaveAbove,
	shelves.leaveBelow,
	shelves.deep,
	shelves.shallow,
	box("PoolEdge", POOL_EDGE + 3, 0, FLOOR, SURFACE + EDGE_RISE, 6, 2 * POOL_HALF),
	box("LadderBlock", BLOCK_FACE + 5, 0, FLOOR, FLOOR + BLOCK_HEIGHT, 10, 20),
} :: { Part }

-- The ladder against the block's face, and a second overlapping it along Z
Course.ladder = {
	cframe = CFrame.new(BLOCK_FACE - LADDER_DEPTH / 2, FLOOR + BLOCK_HEIGHT / 2, 0),
	size = Vector3.new(LADDER_DEPTH, BLOCK_HEIGHT, LADDER_WIDTH),
} :: LadderPlace

Course.beside = {
	cframe = CFrame.new(BLOCK_FACE - LADDER_DEPTH / 2, FLOOR + BLOCK_HEIGHT / 2, LADDER_SHIFT),
	size = Vector3.new(LADDER_DEPTH, BLOCK_HEIGHT, LADDER_WIDTH),
} :: LadderPlace

--[[
    The pool's water query: the surface over the pool's region of the
    floor, and nil anywhere else
--]]

function Course.water(x: number, z: number): number?
	if x >= POOL_START and x < POOL_EDGE and math.abs(z) <= POOL_HALF then
		return SURFACE
	end

	return nil
end

-- A rules function that refuses nothing and caps no speed
local function free(_: RuleStep, _: Allow): number
	return math.huge
end

--[[
    A server's world over the course, Lune's fixture casts when no
    collision is given, with the pool's water and a rules function of the
    trial's own or one that refuses nothing
--]]

function Course.world(collision: Collision?, rules: Rules?): World
	return World.new(SETTINGS, SIMULATION_RATE, collision or Casts(Course.parts), Course.water, rules or free, true)
end

--[[
    A standing body with its feet at feet, on the ground or in the air, its
    last ground under its feet
--]]

function Course.state(feet: vector, grounded: boolean): State
	local state: State = Scene.state(feet, grounded)
	state.groundHeight = feet.y
	state.eyeHeight = Math.quantizeEye(SETTINGS.eyeStanding)

	return state
end

--[[
    A swimmer with its feet at feet, its eye at the crouched height a
    swimmer uses, its last ground the course floor
--]]

function Course.swimmer(feet: vector): State
	local state: State = Scene.state(feet, false)
	state.mode = "Swim"
	state.groundHeight = ground
	state.eyeHeight = Math.quantizeEye(SETTINGS.eyeCrouched)

	return state
end

-- A command with no input, numbered 1, its presses all off
function Course.command(): Command
	return {
		number = 1,
		forward = 0,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		pressed = { jump = false, crouch = false, sprint = false, aim = false },
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	}
end

--[[
    Steps a body for ticks on one command, numbered on from its own, its
    presses off after the first tick as a handler derives them, and gives
    back the speed of the last landing that counted, 0 for none
--]]

function Course.advance(state: State, world: World, order: Command, ticks: number): number
	local landing: number = 0

	for _ = 1, ticks do
		world.tick += 1
		local speed: number, _: number? = Step.advance(state, order, world)
		if speed > 0 then
			landing = speed
		end

		order.number += 1
		order.pressed.jump = false
		order.pressed.crouch = false
		order.pressed.sprint = false
		order.pressed.aim = false
	end

	return landing
end

-- Why a value ended away from where it should, or nil
function Course.near(label: string, got: number, want: number): string?
	if math.abs(got - want) <= TOLERANCE then
		return nil
	end

	return `{label} ended at {got}, where {want} was expected`
end

-- Why a value is not exactly what it should be, or nil
function Course.is(label: string, got: any, want: any): string?
	if got == want then
		return nil
	end

	return `{label} was {got}, where {want} was expected`
end

--[[
    Runs one trial by name from a list over a collision, Lune's fixture
    casts over the course when none is given, and gives whether it ended
    where it should, with the reason when it did not
--]]

function Course.run(
	trials: { { name: string, run: (collision: Collision) -> string? } },
	name: string,
	collision: Collision?
): (boolean, string | nil)
	for _, trial in trials do
		if trial.name == name then
			local failure: string? = trial.run(collision or Casts(Course.parts))
			if failure then
				return false, `{name}: {failure}`
			end

			return true, nil
		end
	end

	return false, `no trial is named {name}`
end

return Course
