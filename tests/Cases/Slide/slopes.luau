--[[
    A slope adds the game's share of gravity along the ground: down a 10
    degree ramp a slide from a sprint holds its speed within half a stud a
    second, and down a 25 degree one it gains to the top speed and holds it
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local SECOND: number = 20 -- Ticks at 20 Hz
local HOLDS: number = 0.5 -- Studs/s the gentle ramp's speed may move by over a second
local SETTLE: number = 10 -- Ticks a body built over a ramp falls onto it in
local SPRINT_TICKS: number = 3
local FROM_TOP: number = 14 -- Studs down the tilt from a ramp's top it is built at
local RAMP_LENGTH: number = 90 -- Each fixture ramp's length up its tilt
local LIFT: number = 0.5 -- Studs over the ramp's face it is built at
local LIMIT: number = 40 -- Ticks the steep ramp is slid, past the 20 or so the top speed takes and short of its foot

-- A body sprinting down a ramp toward -X once it has settled onto it, and its command
local function down(Slides: any, world: any, ramp: any): (any, any)
	local tilt: number = math.rad(ramp.tilt)
	local x: number = Slides.rampFoot + (RAMP_LENGTH - FROM_TOP) * math.cos(tilt)
	local face: number = Slides.floor + (x + Slides.settings().radius - Slides.rampFoot) * math.tan(tilt)
	local state: any = Slides.state(vector.create(x, face + LIFT, ramp.center.z), false)

	local order: any = Slides.command()
	order.yaw = Slides.west
	Slides.advance(state, world, order, SETTLE)

	order.forward = 1
	order.sprint = true
	Slides.advance(state, world, order, SPRINT_TICKS)

	return state, order
end

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local settings: any = Slides.settings()

	-- About 10 degrees: the slope's push all but matches the friction
	local world: any = Slides.world(settings)
	local gentle: any, gentleOrder: any = down(Slides, world, Slides.ramps.gentle)
	Slides.crouch(gentle, world, gentleOrder)
	if gentle.mode ~= "Slide" then
		return false, `The press on the gentle ramp left the mode {gentle.mode}`
	end

	local first: number = Slides.speed(gentle)
	Slides.advance(gentle, world, gentleOrder, SECOND)
	local after: number = Slides.speed(gentle)
	if gentle.mode ~= "Slide" or math.abs(after - first) > HOLDS then
		return false, `Down 10 degrees it went from {first} to {after} in {gentle.mode} over a second`
	end

	-- 25 degrees: it gains to the top speed and never passes it
	local steepWorld: any = Slides.world(settings)
	local steep: any, steepOrder: any = down(Slides, steepWorld, Slides.ramps.steep)
	Slides.crouch(steep, steepWorld, steepOrder)

	local top: number = Slides.speed(steep)
	local held: number = 0
	for _ = 1, LIMIT do
		Slides.advance(steep, steepWorld, steepOrder, 1)
		local speed: number = Slides.speed(steep)
		if steep.mode ~= "Slide" then
			return false, `Down 25 degrees the slide ended in {steep.mode} at {speed}`
		elseif speed > settings.slide.max then
			return false, `Down 25 degrees it ran at {speed}, past the top speed of {settings.slide.max}`
		elseif speed > top then
			top = speed
		end

		if speed == settings.slide.max then
			held += 1
		end
	end

	if held == 0 then
		return false, `Down 25 degrees it reached {top}, never the top speed of {settings.slide.max}`
	end

	return true, nil
end
