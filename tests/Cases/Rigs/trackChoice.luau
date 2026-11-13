--[[
    The track a step state picks: the mode first, then the posture, with
    idle and walk from the horizontal speed and sprint from its flag
--]]

--!strict
local Environment = require("../../Environment")

local ANIMATE: string = "src/Client/Rigs/Animate.luau"
local STATE: string = "src/Step/State.luau"

type Trial = { mode: string, posture: string, velocity: vector, sprint: boolean, expected: string }

local STILL: vector = vector.zero
local AHEAD: vector = vector.create(0, 0, -10)
local SIDEWAYS: vector = vector.create(3, 0, 0)
local RISING: vector = vector.create(0, 25, 0)
local FALLING: vector = vector.create(4, -30, 0)
local CLIMBING: vector = vector.create(0, 3, 0)

local TRIALS: { Trial } = {
	{ mode = "Ground", posture = "Stand", velocity = STILL, sprint = false, expected = "idle" },
	{ mode = "Ground", posture = "Stand", velocity = STILL, sprint = true, expected = "idle" },
	{ mode = "Ground", posture = "Stand", velocity = AHEAD, sprint = false, expected = "walk" },
	{ mode = "Ground", posture = "Stand", velocity = SIDEWAYS, sprint = false, expected = "walk" },
	{ mode = "Ground", posture = "Stand", velocity = AHEAD, sprint = true, expected = "sprint" },
	{ mode = "Ground", posture = "Crouch", velocity = STILL, sprint = false, expected = "crouchIdle" },
	{ mode = "Ground", posture = "Crouch", velocity = AHEAD, sprint = true, expected = "crouchWalk" },
	{ mode = "Ground", posture = "Downed", velocity = STILL, sprint = false, expected = "downed" },
	{ mode = "Ground", posture = "Downed", velocity = AHEAD, sprint = false, expected = "crawl" },
	{ mode = "Air", posture = "Stand", velocity = RISING, sprint = false, expected = "jump" },
	{ mode = "Air", posture = "Crouch", velocity = FALLING, sprint = false, expected = "fall" },
	{ mode = "Air", posture = "Stand", velocity = STILL, sprint = false, expected = "fall" },
	{ mode = "Swim", posture = "Stand", velocity = STILL, sprint = false, expected = "swimIdle" },
	{ mode = "Swim", posture = "Downed", velocity = AHEAD, sprint = true, expected = "swim" },
	{ mode = "Swim", posture = "Stand", velocity = RISING, sprint = false, expected = "swimIdle" },
	{ mode = "Ladder", posture = "Stand", velocity = CLIMBING, sprint = false, expected = "climb" },
	{ mode = "Ladder", posture = "Crouch", velocity = STILL, sprint = false, expected = "climb" },
	{ mode = "Mantle", posture = "Crouch", velocity = CLIMBING, sprint = false, expected = "mantle" },
}

return function (): (boolean, string | nil)
	local Animate = Environment.load(ANIMATE)
	local State = Environment.load(STATE)

	for _, trial: Trial in TRIALS do
		local state = State.new()
		state.mode = trial.mode
		state.posture = trial.posture
		state.velocity = trial.velocity
		state.sprint = trial.sprint

		local chosen: string = Animate.choose(state)
		if chosen ~= trial.expected then
			local given: string = `{trial.mode}, {trial.posture}, velocity {trial.velocity}, sprint {trial.sprint}`
			return false, `{given} picked {chosen}, not {trial.expected}`
		end
	end

	return true, nil
end
