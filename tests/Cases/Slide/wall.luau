--[[
    A wall takes a slide's speed as it takes a walk's, so a slide run into
    one stops a skin from its face and ends crouched on the ground, its
    cooldown started
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local SKIN: number = 0.02
local TICKS: number = 20 -- Past the slide's reach of the wall, about 7 studs off
local TOLERANCE: number = SKIN / 4

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local settings: any = Slides.settings()
	local world: any = Slides.world(settings)
	local wall: any = Slides.wall
	local face: number = wall.center.z + wall.size.z / 2
	local cooldown: number = math.round(settings.slide.cooldown / world.delta)

	local state: any, order: any = Slides.sprinting(world, vector.create(wall.center.x, Slides.resting, face + 9), 0)
	Slides.crouch(state, world, order)
	if state.mode ~= "Slide" then
		return false, `The crouch press left the mode {state.mode}, so this case proves nothing`
	end

	local ended: number? = nil
	for tick: number = 1, TICKS do
		Slides.advance(state, world, order, 1)
		if state.mode ~= "Slide" then
			ended = tick
			break
		end
	end

	local front: number = state.position.z - settings.radius
	if not ended then
		return false, `It still slid {TICKS} ticks after the crouch, its hull's front at z {front}`
	elseif math.abs(front - (face + SKIN)) > TOLERANCE then
		return false, `It stopped with its hull's front at z {front}, not a skin from the wall's face at {face}`
	end

	return Slides.verdict(
		Slides.is("the mode", state.mode, "Ground")
			or Slides.is("the posture", state.posture, "Crouch")
			or Slides.is("the speed", Slides.speed(state), 0)
			or Slides.is("the cooldown", state.slideCooldown, cooldown)
	)
end
