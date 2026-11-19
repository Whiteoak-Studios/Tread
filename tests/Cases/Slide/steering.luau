--[[
    A slide's direction turns toward the move input by at most the game's
    steer, 60 degrees a second, so 3 a tick at 20 Hz, with its speed kept,
    and once it lies along the input it stays there
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local SPEED: number = 18
local TURNED: number = 10 -- Ticks of turning measured, 30 degrees at 3 a tick
local ALONG: number = 40 -- Ticks after which it lies along the input, past the 30 a quarter turn takes
local CLOSE: number = 0.05 -- Degrees a tick's turn may sit from the steer's, the velocity's 1/64 quanta at 18 studs/s
local QUANTUM: number = 1 / 64

-- The direction's angle on the ground, in degrees from -Z toward +X
local function angleOf(velocity: vector): number
	return math.deg(math.atan2(velocity.x, -velocity.z))
end

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)

	-- No friction, so the speed it keeps is the steering's alone
	local settings: any = Slides.settings({ friction = 0 })
	local world: any = Slides.world(settings)
	local perTick: number = settings.slide.steer * world.delta

	local state: any = Slides.state(vector.create(-20, Slides.resting, 100), true)
	state.mode = "Slide"
	state.posture = "Crouch"
	state.velocity = vector.create(0, 0, -SPEED)

	-- Looking along -Z with the move input to the right, along +X
	local order: any = Slides.command()
	order.right = 1
	order.crouch = true

	local angle: number = 0
	local speed: number = SPEED
	for tick: number = 1, TURNED do
		Slides.advance(state, world, order, 1)

		local turned: number = angleOf(state.velocity) - angle
		local kept: number = Slides.speed(state) - speed
		angle += turned
		speed += kept

		if math.abs(turned - perTick) > CLOSE then
			return false, `Tick {tick} turned it {turned} degrees, not the steer's {perTick}`
		elseif math.abs(kept) > QUANTUM then
			return false, `Tick {tick} of turning changed its speed by {kept}`
		end
	end

	Slides.advance(state, world, order, ALONG - TURNED)

	local velocity: vector = state.velocity
	if velocity.z ~= 0 or math.abs(velocity.x - SPEED) > QUANTUM then
		return false, `{ALONG} ticks in, it slid at {velocity}, not along the input at its {SPEED}`
	end

	return Slides.verdict(Slides.is("the mode", state.mode, "Slide"))
end
