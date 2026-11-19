--[[
    The ledge search answers as a press does and changes nothing: on a ledge
    in reach, one too high, a step, a wall with no top in reach, crouched
    room only, no room, a body in the way and the bodies no press mantles,
    find, start and a jump press through the step all agree
--]]

--!strict
local Environment = require("../../Environment")

local COURSE: string = "tests/Fixtures/Step/Course.luau"
local MANTLE: string = "src/Step/Mantle.luau"
local STATE: string = "src/Step/State.luau"
local WORLD: string = "src/Step/World.luau"

local BACK: number = 1 -- Studs the body in the way's trial stands back from its usual place, inside the face's reach
local GAP: number = 0.3 -- Studs between that body's hull and the other's, nearer than the face
local SIDE: number = 2 -- How far along Z the other body stands from it, its hull still across the way

-- One body facing a ledge, and the posture the search must give for it, nil for no mantle
type Trial = {
	label: string,
	row: string, -- The course row it faces
	want: string?,
	set: ((state: any, order: any) -> ())?, -- Changes the body and its press before the trial
	back: number?, -- How far back from the row's approach it stands
	blocker: boolean?, -- Whether another body stands in its way
}

local TRIALS: { Trial } = {
	{ label = "a ledge in reach", row = "exact", want = "Stand" },
	{ label = "a ledge one quantum too high", row = "past" },
	{ label = "a step the walk climbs", row = "step" },
	{ label = "a wall with no top in reach", row = "halfwall" },
	{ label = "crouched room only", row = "low", want = "Crouch" },
	{ label = "room for no hull", row = "tight" },

	{
		label = "a crouched body",
		row = "plain",
		want = "Crouch",
		set = function (state: any, order: any)
			state.posture = "Crouch"
			order.crouch = true
		end,
	},

	{ label = "a body standing back", row = "plain", want = "Stand", back = BACK },
	{ label = "a body in the way", row = "plain", back = BACK, blocker = true },

	{
		label = "facing away",
		row = "exact",
		set = function (state: any, order: any)
			state.facing = -state.facing
			order.yaw = state.facing
		end,
	},

	{
		label = "a downed body",
		row = "exact",
		set = function (state: any, _: any)
			state.posture = "Downed"
		end,
	},

	{
		label = "a noclip body",
		row = "exact",
		set = function (state: any, _: any)
			state.moveMode = "Noclip"
		end,
	},

	{
		label = "a climber",
		row = "exact",
		set = function (state: any, _: any)
			state.mode = "Ladder"
			state.grounded = false
		end,
	},
}

-- Why any plain field of a state differs from its copy's, or nil
local function changed(state: { [string]: any }, before: { [string]: any }): string?
	for key: string, value: any in state do
		if type(value) ~= "table" and before[key] ~= value then
			return `its {key} went from {before[key]} to {value}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local Course: any = Environment.load(COURSE)
	local Mantle: any = Environment.load(MANTLE)
	local State: any = Environment.load(STATE)
	local World: any = Environment.load(WORLD)

	-- The trial's body at its row and its jump press, in a world of its own with any body in its way
	local function build(trial: Trial): (any, any, any)
		local row: any = Course.rows[trial.row]
		local world: any = Course.world()
		local feet: vector = vector.create(Course.approach - (trial.back or 0), Course.resting, row.center.z)
		local state: any = Course.state(feet, true)
		state.facing = Course.east

		local order: any = Course.command()
		order.yaw = Course.east
		order.jump, order.pressed.jump = true, true

		if trial.set then
			trial.set(state, order)
		end

		if trial.blocker then
			local radius: number = Course.settings.radius
			local ahead: vector = vector.create(feet.x + 2 * radius + GAP, feet.y, feet.z + SIDE)
			World.setBodies(world, { Course.state(ahead, true) })
		end

		return state, order, world
	end

	for _, trial: Trial in TRIALS do
		-- The search alone, which must leave the body as it found it
		local state: any, _: any, world: any = build(trial)
		local before: any = State.new()
		State.copy(state, before)

		local posture: string?, x: number, z: number, rise: number = Mantle.find(state, world)
		local untouched: string? = changed(state, before)
		if untouched then
			return false, `The search for {trial.label} changed the body: {untouched}`
		elseif posture ~= trial.want then
			return false, `The search for {trial.label} gave {posture}, where {trial.want} was expected`
		end

		-- Start applies exactly what the search found, or nothing
		local started: any = build(trial)
		Mantle.start(started, world)
		if posture then
			local at: vector = vector.create(x, state.position.y, z)
			if started.mode ~= "Mantle" or started.posture ~= posture or started.mantleRise ~= rise then
				return false, `Start for {trial.label} gave {started.mode} {started.posture}, not the search's answer`
			elseif started.position ~= at then
				return false,
					`Start for {trial.label} moved the body to {started.position}, where the search found {at}`
			end
		else
			local untouchedStart: string? = changed(started, before)
			if untouchedStart then
				return false, `Start for {trial.label} changed the body though the search found none: {untouchedStart}`
			end
		end

		-- A jump press through the step mantles exactly when the search says it would
		local pressed: any, order: any, pressWorld: any = build(trial)
		Course.advance(pressed, pressWorld, order, 1)
		if (pressed.mode == "Mantle") ~= (posture ~= nil) then
			return false, `A press for {trial.label} left the body in {pressed.mode}, where the search gave {posture}`
		elseif posture and pressed.posture ~= posture then
			return false, `A press for {trial.label} mantled {pressed.posture}, where the search gave {posture}`
		end
	end

	return true, nil
end
