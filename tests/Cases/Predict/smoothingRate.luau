--[[
    Over one second the visual error offset shrinks to the same share at 30
    and at 144 frames a second, e^(-decay) of where it started, since each
    frame takes off the fraction its own time gives
--]]

--!strict
local Environment = require("../../Environment")
local Harness = require("../../Fixtures/Predict/Harness")

local GEOMETRY: string = "tests/Fixtures/Step/Geometry.luau"

local RATES: { number } = { 30, 144 } -- Frames a second
local SPAN: number = 1 -- Seconds of frames the offset shrinks over
local SPAWN_X: number = -20 -- On the fixture floor, clear of every other part around the origin's z
local SHIFT: number = 1 -- Studs along +Z the server's state sits from the prediction, onto z = 0
local TOLERANCE: number = 1e-3 -- The share of the offset two runs may differ by, from float32 rounding each frame

-- Stands still, the game's declared fields at rest, so the predicted path holds at z = 0 after the correction
local function stand(command: any, _: number)
	command.fields.slot = 0
	command.fields.shots = {}
end

--[[
    The offset left along Z after a second of frames at a rate, from one a
    stud long, and the decay it shrank at. The body stands at z = 0, so its
    drawn z is the offset alone
--]]

local function left(rate: number, floor: number): (number, number, number)
	local rig: any = Harness.new({ spawn = vector.create(SPAWN_X, floor, -SHIFT) })
	rig.input = stand
	rig.spawn()
	rig.frames(4)

	local server: any = rig.twin(2)
	server.position += vector.create(0, 0, SHIFT)
	rig.Predict.receive(rig.owner(server, 2))

	local start: number = rig.Predict.state().position.z
	rig.frames(rate * SPAN, 1 / rate)

	return start, rig.Predict.state().position.z, rig.settings.smoothing.decay
end

return function (): (boolean, string | nil)
	local Geometry: any = Environment.load(GEOMETRY)
	local shares: { number } = {}

	for _, rate: number in RATES do
		local start: number, after: number, decay: number = left(rate, Geometry.floor)
		if start ~= -SHIFT then
			return false, `At {rate} frames a second the correction drew the body at z {start}, not {-SHIFT}`
		end

		local share: number = after / start
		local wanted: number = math.exp(-decay * SPAN)
		if math.abs(share - wanted) > TOLERANCE * wanted then
			return false, `At {rate} frames a second {share} of the offset was left after {SPAN} s, not {wanted}`
		end

		table.insert(shares, share)
	end

	local slow: number, fast: number = shares[1], shares[2]
	if math.abs(slow - fast) > TOLERANCE * fast then
		return false, `{RATES[1]} frames a second left {slow} of the offset and {RATES[2]} left {fast}`
	end

	return true, nil
end
