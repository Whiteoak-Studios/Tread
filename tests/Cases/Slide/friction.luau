--[[
    On flat ground a slide loses the game's friction off its speed each
    second and keeps its direction: 6 studs/s a second at 20 Hz is 0.3 a
    tick, each tick's speed on the velocity's 1/64 quanta
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local QUANTUM: number = 1 / 64
local TICKS: number = 10

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local settings: any = Slides.settings()
	local world: any = Slides.world(settings)
	local perTick: number = settings.slide.friction * world.delta

	local state: any, order: any = Slides.sprinting(world, vector.create(0, Slides.resting, 100), 0)
	Slides.crouch(state, world, order)

	for tick: number = 1, TICKS do
		local before: number = Slides.speed(state)
		Slides.advance(state, world, order, 1)
		local lost: number = before - Slides.speed(state)

		if math.abs(lost - perTick) > QUANTUM / 2 then
			return false, `Tick {tick} took {lost} off the speed, where friction takes {perTick}`
		elseif state.mode ~= "Slide" or state.velocity.x ~= 0 then
			return false, `Tick {tick} left the mode {state.mode} and a velocity of {state.velocity}, off its line`
		end
	end

	return true, nil
end
