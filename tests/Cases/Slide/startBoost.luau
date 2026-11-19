--[[
    A slide starts in the body's direction at its speed plus the boost, but
    never past the greater of its speed and the sprint plus the boost: a
    body below the sprint gains the boost up to that, and one past it none
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local SLIDE: string = "src/Step/Slide.luau"
local BOOST: number = 3
local CLOSE: number = 1e-5 -- Past a vector's float32 rounding

-- A speed carried in and the speed the start gives it, at the fixture's sprint of 18 studs/s
type Row = { speed: number, boost: number, started: number }

local ROWS: { Row } = {
	{ speed = 16, boost = BOOST, started = 19 }, -- Below the sprint, the whole boost
	{ speed = 20, boost = BOOST, started = 21 }, -- Past the sprint, up to the sprint plus the boost
	{ speed = 24, boost = BOOST, started = 24 }, -- Past the sprint plus the boost, nothing
	{ speed = 18, boost = 0, started = 18 }, -- No boost, never faster than the body already moved
}

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local Slide: any = Environment.load(SLIDE)

	for _, row: Row in ROWS do
		local settings: any = Slides.settings({ boost = row.boost })
		local state: any = Slides.state(vector.create(0, Slides.resting, 100), true)

		-- Three parts across to four along, so the direction it keeps is no axis's
		local across: number, along: number = 0.6, -0.8
		state.velocity = vector.create(across * row.speed, 0, along * row.speed)
		Slide.start(state, settings)

		local speed: number = Slides.speed(state)
		local velocity: vector = state.velocity
		if math.abs(speed - row.started) > CLOSE then
			return false, `From {row.speed} with a boost of {row.boost} it started at {speed}, not {row.started}`
		elseif math.abs(velocity.x / speed - across) > CLOSE or math.abs(velocity.z / speed - along) > CLOSE then
			return false, `From {row.speed} it started along {velocity / speed}, not its own direction`
		elseif state.mode ~= "Slide" or velocity.y ~= 0 then
			return false, `The start left the mode {state.mode} and a rise of {velocity.y}`
		end
	end

	return true, nil
end
