--[[
    A slide that leaves a ledge with no jump ends in the air with its
    velocity and starts no cooldown, so landing with crouch held and its
    speed still past the start slides on
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local SPEED: number = 24 -- Fast enough to keep past the start of 15 through the drop's ticks in the air
local AHEAD: number = 3 -- Studs from the ledge's edge it slides from
local LIMIT: number = 20 -- Ticks it is stepped at most before it lands
local QUANTUM: number = 1 / 64

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local settings: any = Slides.settings()
	local world: any = Slides.world(settings)
	local friction: number = settings.slide.friction * world.delta
	local ledge: any = Slides.ledge
	local edge: number = ledge.center.z - ledge.size.z / 2
	local top: number = Slides.resting + Slides.ledgeDrop

	local state: any = Slides.state(vector.create(ledge.center.x, top, edge + AHEAD), true)
	state.mode = "Slide"
	state.posture = "Crouch"
	state.velocity = vector.create(0, 0, -SPEED)

	local order: any = Slides.command()
	order.forward = 1
	order.crouch = true

	-- Off the edge with no jump: the air, the slide's own velocity for the tick kept, and no cooldown
	local left: boolean = false
	local before: number = SPEED
	for _ = 1, LIMIT do
		before = Slides.speed(state)
		Slides.advance(state, world, order, 1)
		if state.mode == "Air" then
			left = true
			break
		elseif state.mode ~= "Slide" then
			return false, `It ended in {state.mode} before it left the ledge`
		end
	end

	if not left then
		return false, `It was still on the ledge after {LIMIT} ticks`
	elseif state.slideCooldown ~= 0 or state.jumps ~= 0 then
		return false, `Leaving the ledge started a cooldown of {state.slideCooldown} or a jump`
	elseif math.abs(Slides.speed(state) - (before - friction)) > QUANTUM then
		return false, `It left the ledge at {Slides.speed(state)}, not its slide's {before} less a tick's friction`
	end

	-- It lands, then slides on from the first ground tick
	for _ = 1, LIMIT do
		Slides.advance(state, world, order, 1)
		if state.mode ~= "Air" then
			break
		end
	end

	if state.mode ~= "Ground" or state.position.y > Slides.resting + Slides.ledgeDrop / 2 then
		return false, `It came down in {state.mode} at y {state.position.y}, not on the floor`
	end

	Slides.advance(state, world, order, 1)

	return Slides.verdict(
		Slides.is("the mode after the landing", state.mode, "Slide")
			or Slides.is("the cooldown", state.slideCooldown, 0)
	)
end
