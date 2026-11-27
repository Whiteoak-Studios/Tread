--[[
    A jump ends a slide into the air with its horizontal velocity, held to
    the slide's top speed, rising at the jump's speed, and starts the
    cooldown, in whole ticks of the game's seconds
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local FAST: number = 30 -- Past the dev place's top speed of 27

-- A sliding body moving ahead at a speed, and its command with crouch held
local function sliding(Slides: any, speed: number): (any, any)
	local state: any = Slides.state(vector.create(0, Slides.resting, 100), true)
	state.mode = "Slide"
	state.posture = "Crouch"
	state.velocity = vector.create(0, 0, -speed)

	local order: any = Slides.command()
	order.forward = 1
	order.crouch = true

	return state, order
end

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local settings: any = Slides.settings()
	local world: any = Slides.world(settings)
	local cooldown: number = math.round(settings.slide.cooldown / world.delta)

	-- From 18, it leaves at 18, with no friction taken on the jump's tick
	local state: any, order: any = sliding(Slides, 18)
	order.jump, order.pressed.jump = true, true
	Slides.advance(state, world, order, 1)

	local jumped: string? = Slides.is("the mode", state.mode, "Air")
		or Slides.is("the jumps", state.jumps, 1)
		or Slides.is("the rise", state.velocity.y, settings.jump)
		or Slides.is("the horizontal speed", Slides.speed(state), 18)
		or Slides.is("the cooldown", state.slideCooldown, cooldown)
	if jumped then
		return false, jumped
	end

	-- From past the top speed, it leaves held to it
	local fast: any, fastOrder: any = sliding(Slides, FAST)
	fastOrder.jump, fastOrder.pressed.jump = true, true
	Slides.advance(fast, world, fastOrder, 1)

	return Slides.verdict(
		Slides.is("the fast slide's mode", fast.mode, "Air")
			or Slides.is("the fast slide's horizontal speed", Slides.speed(fast), settings.slide.max)
			or Slides.is("the fast slide's cooldown", fast.slideCooldown, cooldown)
	)
end
