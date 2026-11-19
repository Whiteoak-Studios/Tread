--[[
    Letting go of crouch ends a slide into the walk, standing where the
    standing hull fits, and pressing sprint ends it crouched while crouch
    stays held; each starts the cooldown
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local settings: any = Slides.settings()
	local world: any = Slides.world(settings)
	local cooldown: number = math.round(settings.slide.cooldown / world.delta)

	-- A slide from a sprint, a few ticks in
	local state: any, order: any = Slides.sprinting(world, vector.create(0, Slides.resting, 100), 0)
	Slides.crouch(state, world, order)
	Slides.advance(state, world, order, 3)
	if state.mode ~= "Slide" then
		return false, `The slide ended before crouch was let go, in {state.mode}`
	end

	-- Crouch let go, with sprint still held: the walk's own tick, standing, at the walk's speed
	order.crouch = false
	Slides.advance(state, world, order, 1)
	local released: string? = Slides.is("the mode once crouch is let go", state.mode, "Ground")
		or Slides.is("the posture once crouch is let go", state.posture, "Stand")
		or Slides.is("the speed once crouch is let go", Slides.speed(state), settings.walk)
		or Slides.is("the cooldown once crouch is let go", state.slideCooldown, cooldown)
	if released then
		return false, released
	end

	-- Sprint pressed with crouch held: the walk's own tick, still crouched
	local pressed: any, pressOrder: any = Slides.sprinting(world, vector.create(20, Slides.resting, 100), 0)
	pressOrder.sprint = false
	Slides.crouch(pressed, world, pressOrder)
	Slides.advance(pressed, world, pressOrder, 2)
	if pressed.mode ~= "Slide" then
		return false, `The second slide ended before sprint was pressed, in {pressed.mode}`
	end

	pressOrder.sprint, pressOrder.pressed.sprint = true, true
	Slides.advance(pressed, world, pressOrder, 1)

	return Slides.verdict(
		Slides.is("the mode once sprint is pressed", pressed.mode, "Ground")
			or Slides.is("the posture once sprint is pressed", pressed.posture, "Crouch")
			or Slides.is("the speed once sprint is pressed", Slides.speed(pressed), settings.crouch)
			or Slides.is("the cooldown once sprint is pressed", pressed.slideCooldown, cooldown)
	)
end
