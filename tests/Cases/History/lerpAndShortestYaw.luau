--[[
    A read between samples interpolates through Math.lerp, the place and the
    yaw alike, and the yaw takes the shortest arc across the wrap through
    Sequence.difference: from 350° to 10° it passes 0°, never 180°
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local MATH: string = "src/Step/Math.luau"
local SEQUENCE: string = "src/Codec/Sequence.luau"
local STATE: string = "src/Step/State.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local MATH_PATH: string = "ReplicatedStorage.Packages.Tread.Step.Math"
local SEQUENCE_PATH: string = "ReplicatedStorage.Packages.Tread.Codec.Sequence"
local SLOT: number = 40
local STEPS: number = 65536 -- A u16 yaw's steps of the turn
local NEAR: number = 1e-9

return function (): (boolean, string | nil)
	local RealMath: any = Environment.load(MATH)
	local RealSequence: any = Environment.load(SEQUENCE)
	local lerps: { { number } } = {}
	local differences: { { number } } = {}

	-- The real modules, each with the one function recorded on every call
	local Recorded: any = table.clone(RealMath)
	Recorded.lerp = function (a: number, b: number, t: number): number
		table.insert(lerps, { a, b, t })
		return RealMath.lerp(a, b, t)
	end

	local Differenced: any = table.clone(RealSequence)
	Differenced.difference = function (a: number, b: number): number
		table.insert(differences, { a, b })
		return RealSequence.difference(a, b)
	end

	local History: any = Environment.load(HISTORY, { [MATH_PATH] = Recorded, [SEQUENCE_PATH] = Differenced })
	local State: any = Environment.load(STATE)
	local Example: any = Environment.load(EXAMPLE)
	History.start(Example.shared(), Example.server())

	local from: number = math.round(350 / 360 * STEPS)
	local to: number = math.round(10 / 360 * STEPS)

	local state = State.new()
	state.position = vector.create(0, 2, 0)
	state.facing = from / STEPS * 2 * math.pi
	History.write(SLOT, 30, state, 0)

	state.position = vector.create(2, 2, -4)
	state.facing = to / STEPS * 2 * math.pi
	History.write(SLOT, 31, state, 0)

	table.clear(lerps)
	table.clear(differences)

	local half = History.sampleAt(SLOT, 30.5)
	if half == nil then
		return false, "A read between the two samples answered nil"
	end

	-- The two ends sum to a whole turn, so their shortest arc's middle is 0°
	local fromNorth: number = math.min(half.yaw, 2 * math.pi - half.yaw)
	if fromNorth > NEAR then
		return false, `Between 350° and 10° the yaw read {math.deg(half.yaw)}°, not 0°`
	elseif half.position ~= vector.create(1, 2, -2) then
		return false, `Half way between the samples read {half.position}, not (1, 2, -2)`
	end

	local found: { [string]: boolean } = {}
	local arc: number = RealSequence.difference(to, from)

	for _, call: { number } in lerps do
		if call[1] == 0 and call[2] == 2 and call[3] == 0.5 then
			found.x = true
		elseif call[1] == 0 and call[2] == -4 and call[3] == 0.5 then
			found.z = true
		elseif call[1] == from and call[2] == from + arc and call[3] == 0.5 then
			found.yaw = true
		end
	end

	for _, call: { number } in differences do
		if call[1] == to and call[2] == from then
			found.arc = true
		end
	end

	if not (found.x and found.z) then
		return false, `The place went between its samples without Math.lerp(0, 2, 0.5) and Math.lerp(0, -4, 0.5)`
	elseif not found.arc then
		return false, `The yaw's arc was not Sequence.difference({to}, {from})`
	elseif not found.yaw then
		return false, `The yaw went between its samples without Math.lerp({from}, {from + arc}, 0.5)`
	end

	return true, nil
end
