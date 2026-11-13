--[[
    Crouch held through a landing at speed starts a slide on the first
    ground tick after the air, with no press, while held on any later
    ground tick it starts none
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local SPRINT: number = 18
local DROP: number = 0.1 -- Studs over the floor the body falls from, which one tick in the air covers

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local world: any = Slides.world()

	-- Crouched in the air at a sprint's speed, a tick's fall over the floor, crouch held and never pressed
	local state: any = Slides.state(vector.create(0, Slides.resting + DROP, 100), false)
	state.mode = "Air"
	state.posture = "Crouch"
	state.velocity = vector.create(0, 0, -SPRINT)

	local order: any = Slides.command()
	order.forward = 1
	order.crouch = true

	Slides.advance(state, world, order, 1)
	local landed: string? = Slides.is("the mode on the landing tick", state.mode, "Ground")
		or Slides.is("grounded on the landing tick", state.grounded, true)
		or Slides.is("the ground ticks on the landing tick", state.groundTicks, 1)
	if landed then
		return false, landed
	elseif Slides.speed(state) < Slides.settings().slide.start then
		return false, `It landed at {Slides.speed(state)} studs/s, under the start, so this case proves nothing`
	end

	Slides.advance(state, world, order, 1)
	local slid: string? = Slides.is("the mode on the first ground tick", state.mode, "Slide")
		or Slides.is("the posture", state.posture, "Crouch")
	if slid then
		return false, slid
	end

	-- On the ground for a while, crouch held at a sprint's speed starts nothing
	local held: any = Slides.state(vector.create(20, Slides.resting, 100), true)
	held.posture = "Crouch"
	held.velocity = vector.create(0, 0, -SPRINT)
	held.groundTicks = 10

	local holding: any = Slides.command()
	holding.forward = 1
	holding.crouch = true
	Slides.advance(held, world, holding, 1)

	return Slides.verdict(Slides.is("the mode with crouch held on a later ground tick", held.mode, "Ground"))
end
