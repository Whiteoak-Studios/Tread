--[[
    A crouch pressed in a sprint at 18 studs/s starts a slide on that tick:
    crouched, in its direction, its first tick's friction taken, with
    allow.slide true for the rules on the press and the mode Slide after
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local FIRST: number = 1133 / 64 -- 18 less a tick's 0.3 of friction, on the velocity's 1/64 quanta

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local permits: { boolean } = {}
	local modes: { string } = {}

	local world: any = Slides.world(nil, function (step: any, allow: any): number
		table.insert(permits, allow.slide)
		table.insert(modes, step.mode)

		return math.huge
	end)

	local state: any, order: any = Slides.sprinting(world, vector.create(0, Slides.resting, 100), 0)
	if Slides.speed(state) ~= 18 or state.mode ~= "Ground" then
		return false, `The sprint ran at {Slides.speed(state)} in {state.mode}, so this case proves nothing`
	end

	local before: number = #permits
	Slides.crouch(state, world, order)

	local started: string? = Slides.is("the mode", state.mode, "Slide")
		or Slides.is("the posture", state.posture, "Crouch")
		or Slides.is("the speed after its first tick", Slides.speed(state), FIRST)
		or Slides.is("the velocity's x", state.velocity.x, 0)
		or Slides.is("the velocity's y", state.velocity.y, 0)
		or Slides.is("grounded", state.grounded, true)
		or Slides.is("allow.slide on the press", permits[before + 1], true)
		or Slides.is("the cooldown", state.slideCooldown, 0)
	if started then
		return false, started
	end

	Slides.advance(state, world, order, 1)

	return Slides.verdict(
		Slides.is("the rules' mode on the next tick", modes[#modes], "Slide")
			or Slides.is("allow.slide while it slides", permits[#permits], false)
	)
end
