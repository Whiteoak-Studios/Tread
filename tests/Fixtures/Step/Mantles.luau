--[[
    The mantle's trials on the course, each from a fixed state with fixed
    commands and the ending it must reach: the reach, the path, the posture
    it ends in, a swimmer's climb out, a block, and every refusal
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Packages.Tread.Constants)
local Course = require(script.Parent.Course)
local Geometry = require(script.Parent.Geometry)
local Math = require(ReplicatedStorage.Packages.Tread.Step.Math)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)
local World = require(ReplicatedStorage.Packages.Tread.Step.World)

local SKIN: number = Constants.SKIN
local RISE_QUANTUM: number = Constants.EYE_QUANTUM
local SETTINGS = Course.settings
local GROUND: number = Course.resting
local EAST: number = Course.east
local WEST: number = Course.west
local TICKS: number = Course.ticks
local RISING_TICKS: number = 1 -- Ticks of a jump's climb before its second press, still well under the past row's top

type Collision = State.Collision
type Command = State.Command
type Part = Geometry.Part
type State = State.State
type World = State.World

type Trial = {
	name: string,
	run: (collision: Collision) -> string?,
}

local near = Course.near
local is = Course.is

local Mantles = {}

-- A body standing at a row's approach, a skin from its face, and a jump press facing it
local function atRow(row: Part): (State, Command)
	local state: State = Course.state(vector.create(Course.approach, GROUND, row.center.z), true)
	local order: Command = Course.command()
	order.yaw = EAST
	order.jump = true
	order.pressed.jump = true

	return state, order
end

-- The rise a mantle from feet at a height takes to a skin over a top, on the rise's own step and rounded up
local function riseTo(top: number, feet: number): number
	return math.ceil((top + SKIN - feet) / RISE_QUANTUM) * RISE_QUANTUM
end

-- Why a press that should have jumped started a mantle or did not jump, or nil
local function jumped(label: string, state: State): string?
	return is(`{label}'s mode`, state.mode, "Air")
		or is(`{label}'s jumps`, state.jumps, 1)
		or is(`{label}'s rise speed`, state.velocity.y, SETTINGS.jump)
end

local TRIALS: { Trial } = {
	{
		-- A top exactly the reach over the ground last stood on is mantled: straight up beside the face, then ahead
		-- onto the top, ending there standing once the game's mantle time has run
		name = "exactReach",
		run = function (collision: Collision): string?
			local row: Part = Course.rows.exact
			local world: World = Course.world(collision)
			local state: State, order: Command = atRow(row)
			local rise: number = riseTo(Course.top(row), GROUND)

			Course.advance(state, world, order, 1)
			local started: string? = is("the mode", state.mode, "Mantle")
				or is("the rise", state.mantleRise, rise)
				or is("the progress", state.mantleTicks, 1)
				or is("the jumps", state.jumps, 0)
			if started then
				return started
			end

			-- Until the rise is done the body only climbs
			local beside: number = state.position.x
			local height: number = state.position.y
			local upTicks: number = math.floor(rise / (rise + Course.over) * TICKS)
			Course.advance(state, world, order, upTicks - 1)
			local climbing: string? = is("the x while it rises", state.position.x, beside)
				or is("the mode while it rises", state.mode, "Mantle")
			if climbing then
				return climbing
			elseif state.position.y <= height then
				return `it rose no higher than {height} by its tick {upTicks}`
			end

			Course.advance(state, world, order, TICKS - upTicks)

			return is("the mode at the end", state.mode, "Ground")
				or is("grounded at the end", state.grounded, true)
				or is("the posture", state.posture, "Stand")
				or is("the progress at the end", state.mantleTicks, 0)
				or is("the rise at the end", state.mantleRise, 0)
				or near("y", state.position.y, Course.top(row) + SKIN)
				or near("x", state.position.x, beside + Course.over)
		end,
	},

	{
		-- A top one quantum past the reach is no ledge to mantle, so the press jumps
		name = "pastReach",
		run = function (collision: Collision): string?
			local world: World = Course.world(collision)
			local state: State, order: Command = atRow(Course.rows.past)
			Course.advance(state, world, order, 1)

			return jumped("the press under a top past the reach", state)
		end,
	},

	{
		-- A jump before the mantle adds nothing to its reach, which counts from the ground last stood on: halfway up
		-- a jump the past row's top lies in reach of the feet, and a second press still finds no ledge. The same
		-- press in the air at the exact row starts one
		name = "jumpFirst",
		run = function (collision: Collision): string?
			local row: Part = Course.rows.past
			local world: World = Course.world(collision)
			local state: State, order: Command = atRow(row)
			Course.advance(state, world, order, 1)
			local first: string? = jumped("the first press", state)
			if first then
				return first
			end

			Course.advance(state, world, order, RISING_TICKS)
			local above: number = Course.top(row) - state.position.y
			if above > SETTINGS.mantleHeight or above <= SETTINGS.stepHeight then
				return `halfway up the jump the top lay {above} over the feet, outside what this trial needs`
			end

			order.pressed.jump = true
			Course.advance(state, world, order, 1)
			local refused: string? = is("the mode after the press in the air", state.mode, "Air")
				or is("the progress after the press in the air", state.mantleTicks, 0)
			if refused then
				return refused
			end

			local exact: Part = Course.rows.exact
			local feet: vector = vector.create(Course.approach, state.position.y, exact.center.z)
			local flying: State = Course.state(feet, false)
			flying.groundHeight = GROUND
			flying.velocity = state.velocity
			local press: Command = Course.command()
			press.yaw = EAST
			press.jump, press.pressed.jump = true, true
			Course.advance(flying, world, press, 1)

			return is("the mode after the same press at the exact row", flying.mode, "Mantle")
		end,
	},

	{
		-- A swimmer's reach counts from its feet, so it climbs out onto the pool's edge, which lies past the reach of
		-- the pool floor it last stood on, and stands there out of the water
		name = "swimmerOut",
		run = function (collision: Collision): string?
			local world: World = Course.world(collision)
			local edge: number = Course.edgeTop
			local start: vector =
				vector.create(Math.quantize(Course.poolEdge - SETTINGS.radius - SKIN), Course.float, 30)
			local state: State = Course.swimmer(start)
			if edge - state.groundHeight <= SETTINGS.mantleHeight then
				return "the pool's edge lies in reach of the pool floor, so this trial proves nothing"
			end

			local order: Command = Course.command()
			order.yaw = EAST
			order.jump, order.pressed.jump = true, true
			Course.advance(state, world, order, 1)
			local started: string? = is("the mode", state.mode, "Mantle")
				or is("the rise", state.mantleRise, riseTo(edge, Course.float))
			if started then
				return started
			end

			Course.advance(state, world, order, TICKS)

			return is("the mode at the end", state.mode, "Ground")
				or is("the posture", state.posture, "Stand")
				or is("the water level", state.waterLevel, "Dry")
				or near("y", state.position.y, edge + SKIN)
		end,
	},

	{
		-- Under a ceiling with room for the crouched hull and not the standing one, the mantle ends crouched
		name = "lowCeiling",
		run = function (collision: Collision): string?
			local row: Part = Course.rows.low
			local world: World = Course.world(collision)
			local state: State, order: Command = atRow(row)
			Course.advance(state, world, order, 1)
			local started: string? = is("the mode", state.mode, "Mantle") or is("the posture", state.posture, "Crouch")
			if started then
				return started
			end

			Course.advance(state, world, order, TICKS)

			return is("the mode at the end", state.mode, "Ground")
				or is("the posture at the end", state.posture, "Crouch")
				or near("y", state.position.y, Course.top(row) + SKIN)
		end,
	},

	{
		-- A body crouched when its mantle starts is crouched when it ends, though the top has room to stand
		name = "crouchedStays",
		run = function (collision: Collision): string?
			local row: Part = Course.rows.plain
			local world: World = Course.world(collision)
			local state: State, order: Command = atRow(row)
			state.posture = "Crouch"
			order.crouch = true
			Course.advance(state, world, order, TICKS)

			return is("the mode at the end", state.mode, "Ground")
				or is("the posture at the end", state.posture, "Crouch")
				or near("y", state.position.y, Course.top(row) + SKIN)
		end,
	},

	{
		-- Another body standing on the top blocks the path ahead, so the mantle drops into the air where it stopped,
		-- beside the face, and the body falls back to the floor
		name = "blocked",
		run = function (collision: Collision): string?
			local row: Part = Course.rows.blocked
			local world: World = Course.world(collision)
			local state: State, order: Command = atRow(row)
			local onTop: vector =
				vector.create(Course.face + SKIN + SETTINGS.radius, Course.top(row) + SKIN, row.center.z)
			local other: State = Course.state(onTop, true)
			World.setBodies(world, { state, other })

			local stoppedAt: vector? = nil
			for _ = 1, TICKS do
				Course.advance(state, world, order, 1)
				if state.mode ~= "Mantle" then
					stoppedAt = state.position
					break
				end
			end

			if not stoppedAt then
				return "the mantle ran its whole path through the other body"
			end

			local dropped: string? = is("the mode where it stopped", state.mode, "Air")
				or is("the progress where it stopped", state.mantleTicks, 0)
				or near("y where it stopped", stoppedAt.y, GROUND + riseTo(Course.top(row), GROUND))
			if dropped then
				return dropped
			elseif stoppedAt.x + SETTINGS.radius > Course.face + SKIN then
				return `it stopped at x {stoppedAt.x}, past the face it should have stopped beside`
			end

			Course.advance(state, world, order, 30)

			return is("grounded after the fall", state.grounded, true)
				or near("y after the fall", state.position.y, GROUND)
		end,
	},

	{
		-- A press starts no mantle at a wall past the reach, at a ledge a walk steps onto, under a ceiling with room
		-- for no hull, facing away, or downed, and jumps instead where it may
		name = "refuses",
		run = function (collision: Collision): string?
			local world: World = Course.world(collision)
			local rows: { Part } = { Course.rows.halfwall, Course.rows.step, Course.rows.tight }

			for _, row: Part in rows do
				local state: State, order: Command = atRow(row)
				Course.advance(state, world, order, 1)

				local refused: string? = jumped(`the press at the {row.name} row`, state)
				if refused then
					return refused
				end
			end

			local away: State, awayOrder: Command = atRow(Course.rows.exact)
			awayOrder.yaw = WEST
			Course.advance(away, world, awayOrder, 1)
			local facingAway: string? = jumped("the press facing away", away)
			if facingAway then
				return facingAway
			end

			-- Tread's own physics lets a downed body jump on the ground, which the game's rules may refuse
			local downed: State, downedOrder: Command = atRow(Course.rows.exact)
			downed.posture = "Downed"
			Course.advance(downed, world, downedOrder, 1)

			return jumped("the downed press", downed) or is("the downed body's posture", downed.posture, "Downed")
		end,
	},
}

-- Every trial's name, in the order a live scenario runs them
Mantles.names = {} :: { string }

for _, trial: Trial in TRIALS do
	table.insert(Mantles.names, trial.name)
end

--[[
    Runs one trial by name over a collision, Lune's fixture casts over the
    course when none is given, and gives whether it ended where it should,
    with the reason when it did not
--]]

function Mantles.run(name: string, collision: Collision?): (boolean, string | nil)
	return Course.run(TRIALS, name, collision)
end

return Mantles
