--[[
    A slide's speed is held to the game's top speed on every tick, and the
    rules' speed cap bounds no slide
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local FAST: number = 40 -- Past the dev place's top speed of 27
local CAP: number = 4 -- A rules cap under every speed here

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local settings: any = Slides.settings()
	local world: any = Slides.world(settings, function (_: any, _: any): number
		return CAP
	end)

	local state: any = Slides.state(vector.create(0, Slides.resting, 100), true)
	state.mode = "Slide"
	state.posture = "Crouch"
	state.velocity = vector.create(0, 0, -FAST)

	local order: any = Slides.command()
	order.forward = 1
	order.crouch = true
	Slides.advance(state, world, order, 1)

	local held: string? = Slides.is("the mode", state.mode, "Slide")
		or Slides.is("the speed held to the top", Slides.speed(state), settings.slide.max)
	if held then
		return false, held
	end

	-- The next tick takes its friction from the top speed, past the rules' cap
	Slides.advance(state, world, order, 1)
	local speed: number = Slides.speed(state)
	if speed >= settings.slide.max or speed <= CAP then
		return false, `The tick after the top speed ran at {speed}, outside the friction's fall from it`
	end

	return true, nil
end
