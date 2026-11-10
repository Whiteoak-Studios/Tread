--[[
    On flat ground a slide from a sprint at 18 studs/s ends crouched on its
    41st tick at 20 Hz, about 24 studs on, with its cooldown started: it
    ends once its speed is below the stop of 6, not at it
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"

-- Each tick takes 0.3 off the speed, which rounds to 19/64 on the velocity's 1/64 quanta, so after 40 ticks it runs
-- at 1152/64 - 40 × 19/64 = 392/64, 6.125, still at least the stop, and on the 41st at 373/64, 5.828125, below it.
-- The tick that starts the slide is its first, so it ends on its 41st. Each tick moves at its own speed, so it
-- covers the sum of (1152 - 19 n) / 64 × 0.05 over n from 1 to 41, 30,873 / 1,280, about 24.12 studs
local TICKS: number = 41
local LAST_SPEED: number = 373 / 64
local SHORTEST: number = 23.5 -- The research's 24 studs, within half a stud
local LONGEST: number = 24.5
local LIMIT: number = 60 -- Ticks it is stepped at most, past where it ends

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local settings: any = Slides.settings()
	local world: any = Slides.world(settings)
	local cooldown: number = math.round(settings.slide.cooldown / world.delta)

	local state: any, order: any = Slides.sprinting(world, vector.create(0, Slides.resting, 100), 0)
	local from: vector = state.position
	Slides.crouch(state, world, order)

	local ticks: number = 1
	while state.mode == "Slide" and ticks < LIMIT do
		Slides.advance(state, world, order, 1)
		ticks += 1
	end

	local moved: vector = state.position - from
	local covered: number = math.sqrt(moved.x * moved.x + moved.z * moved.z)
	if ticks ~= TICKS then
		return false, `It ended after {ticks} ticks, not on its {TICKS}th`
	elseif covered < SHORTEST or covered > LONGEST then
		return false, `It covered {covered} studs, outside {SHORTEST} to {LONGEST}`
	end

	return Slides.verdict(
		Slides.is("the mode", state.mode, "Ground")
			or Slides.is("the posture", state.posture, "Crouch")
			or Slides.is("the last tick's speed", Slides.speed(state), LAST_SPEED)
			or Slides.is("the cooldown", state.slideCooldown, cooldown)
	)
end
