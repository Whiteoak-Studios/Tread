--[[
    Every value a pose draws between two records comes from Math.lerp, from
    the older sample's value to the newer's at the render time's fraction:
    the position's axes, yaw, lean, pitch and head offset, eight and no others
--]]

--!strict
local Environment = require("../../Environment")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local MATH: string = "src/Step/Math.luau"
local SLOT: number = 3
local GENERATION: number = 1
local LEAN_STEPS: number = 127 -- A record's lean, steps to the lean limit
local PITCH_STEPS: number = 127 -- A record's pitch, steps to 90°

type Call = { a: number, b: number, t: number, value: number }

return function (): (boolean, string | nil)
	-- Math as it is, with its lerp counted
	local real: any = Environment.load(MATH)
	local calls: { Call } = {}
	local counted: { [string]: any } = table.clone(real)

	counted.lerp = function (a: number, b: number, t: number): number
		local value: number = real.lerp(a, b, t)
		table.insert(calls, { a = a, b = b, t = t, value = value })

		return value
	end

	local viewer = Viewer.new({ ["ReplicatedStorage.Packages.Tread.Step.Math"] = counted })
	local Interpolate: any = viewer.Interpolate
	local lean: number = viewer.limits.lean

	-- Lean and pitch on whole steps, so each reads back as written
	local older: { [string]: any } = {
		slot = SLOT,
		generation = GENERATION,
		position = vector.create(10, 2, -4),
		yaw = math.rad(30),
		pitch = 40 * (math.pi / 2) / PITCH_STEPS,
		lean = 32 * lean / LEAN_STEPS,
	}
	local newer: { [string]: any } = {
		slot = SLOT,
		generation = GENERATION,
		position = vector.create(11, 3, -6),
		yaw = math.rad(60),
		pitch = 80 * (math.pi / 2) / PITCH_STEPS,
		lean = 64 * lean / LEAN_STEPS,
	}

	viewer.announce(SLOT, GENERATION, "A")
	viewer.send({
		tick = 100,
		reveals = { { slot = SLOT, generation = GENERATION, kind = "Player" } },
		records = { older },
	})
	viewer.send({ tick = 101, records = { newer } })
	viewer.send({ tick = 102 })
	viewer.send({ tick = 103 })

	-- 3 ticks behind 103, then half a tick on
	Interpolate.frame(0)
	Interpolate.frame(0.025)

	table.clear(calls)
	local drawn: boolean, state: any, pitch: number = viewer.pose(SLOT)

	if not drawn then
		return false, "The slot drew nothing between its two records"
	elseif #calls ~= 8 then
		return false, `One pose made {#calls} lerp calls, not one for each of its eight values`
	end

	for index: number, call: Call in calls do
		if call.t ~= 0.5 then
			return false, `Lerp call {index} was at {call.t}, not the render time's fraction 0.5`
		end
	end

	-- In the order the pose makes them: yaw in the record's whole steps of a turn, X, Y, Z, lean, pitch, and the
	-- head offset's yaw and pitch, none while the record's last byte holds its lean
	local yawSteps: number = viewer.Constants.ANGLE_STEPS / (2 * math.pi)
	local olderPitch: number = 40 / (PITCH_STEPS / (math.pi / 2))
	local newerPitch: number = 80 / (PITCH_STEPS / (math.pi / 2))
	local ends: { { number } } = {
		{ math.round(math.rad(30) * yawSteps), math.round(math.rad(60) * yawSteps) },
		{ 10, 11 },
		{ 2, 3 },
		{ -4, -6 },
		{ 32 * lean / LEAN_STEPS, 64 * lean / LEAN_STEPS },
		{ olderPitch, newerPitch },
		{ 0, 0 },
		{ 0, 0 },
	}

	for index: number, pair: { number } in ends do
		local call: Call = calls[index]
		if math.abs(call.a - pair[1]) > 1e-3 or math.abs(call.b - pair[2]) > 1e-3 then
			return false, `Lerp call {index} ran from {call.a} to {call.b}, not from {pair[1]} to {pair[2]}`
		end
	end

	-- Each value drawn is its call's, X, Y and Z held as the vector's float32 holds them
	local position: vector = vector.create(calls[2].value, calls[3].value, calls[4].value)
	local facing: number = (calls[1].value % viewer.Constants.ANGLE_STEPS) / yawSteps

	if state.position ~= position then
		return false, `The pose drew at {state.position}, not at its lerp calls' {position}`
	elseif state.facing ~= facing or state.lean ~= calls[5].value or pitch ~= calls[6].value then
		return false, "The pose's yaw, lean or pitch is not its lerp call's value"
	end

	return true, nil
end
