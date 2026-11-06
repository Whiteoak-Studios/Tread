--[[
    A stand-in repeats the last real command's held inputs for ticks.standIn
    ticks, never a press, then stops its move and sprint, each reported with
    the run so far, and the real command after them reports the gap
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")
local Same = require("../../Fixtures/Codec/Same")

local START: number = 100 -- The first tick stepped
local STAND_IN: number = 2 -- Frontier Zero's ticks.standIn
local RATE: number = 20 -- Its rates.simulation
local CLOSE: number = 1e-9 -- How near a reported gap in seconds must be

-- What each stand-in keeps of the real command, and what it never repeats
local HELD: { string } = { "crouch", "aim", "yaw", "pitch", "lean", "headYaw", "headPitch" }
local MOVING: { string } = { "forward", "right", "sprint" }

-- Names the first of keys whose value differs between a stand-in and the command it stands in for, or nil
local function differs(standIn: any, real: any, keys: { string }): string?
	for _, key: string in keys do
		if standIn[key] ~= real[key] then
			return `{key} is {standIn[key]}, where the real command's was {real[key]}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	rig:take(START)

	local command: any = rig:command(START + 1)
	command.forward = 0.6
	command.right = 0.8
	command.jump = true
	command.crouch = true
	command.sprint = true
	command.aim = true
	command.yaw = 1
	command.pitch = 0.3
	command.lean = 10
	command.headYaw = 30
	command.headPitch = -15
	command.fields.slot = 5
	command.fields.reload = true
	command.fields.uses = 3
	command.fields.shots = { { sequence = 1, fraction = 0, yaw = 10, class = 1 } }
	command.fields.seed = 123
	command.fields.offset = -7
	rig:send({ command })

	local real: any, realStandIn: boolean = rig:take(START + 1)
	if realStandIn then
		return false, "The tick with a filed command ran a stand-in"
	end

	-- Copies, since the queue reuses the real command's table
	local levels: { [string]: any } = table.clone(real)
	local fields: { [string]: any } = {
		slot = 5,
		reload = false,
		uses = 0,
		shots = {},
		seed = 123,
		offset = -7,
		fixed = 7,
	}

	local first: any = nil
	for ahead: number = 1, STAND_IN + 1 do
		local tick: number = START + 1 + ahead
		local standIn: any, isStandIn: boolean, wait: number = rig:take(tick)

		if not isStandIn or wait ~= 0 then
			return false, `Tick {tick}, with no command, did not run a stand-in that waited 0`
		elseif standIn.number ~= tick then
			return false, `The stand-in for tick {tick} is numbered {standIn.number}`
		end

		first = first or standIn
		if standIn ~= first then
			return false, "A run of stand-ins made a new table for one of them"
		end

		local pressed: any = standIn.pressed
		if standIn.jump or pressed.jump or pressed.crouch or pressed.sprint or pressed.aim then
			return false, `The stand-in for tick {tick} pressed something`
		end

		local kept: string? = differs(standIn, levels, HELD)
		if kept then
			return false, `The stand-in for tick {tick}: {kept}`
		end

		local moved: string?
		if ahead <= STAND_IN then
			moved = differs(standIn, levels, MOVING)
		elseif standIn.forward ~= 0 or standIn.right ~= 0 or standIn.sprint then
			moved = `it moves {standIn.forward}, {standIn.right} with sprint {standIn.sprint} past the window`
		end

		if moved then
			return false, `The stand-in for tick {tick}: {moved}`
		end

		local differsField: string? = Same(fields, standIn.fields, "fields")
		if differsField then
			return false, `The stand-in for tick {tick} carries the wrong game fields: {differsField}`
		end
	end

	rig:send({ rig:command(START + STAND_IN + 3) })
	rig:take(START + STAND_IN + 3)

	local standIns: { number | string } = rig:reported("standIn")
	local expected: { number } = { 1, 1, 2, 3 }
	if #standIns ~= #expected then
		return false, `{#standIns} stand-ins were reported, not {#expected}`
	end

	for index: number, count: number in expected do
		if standIns[index] ~= count then
			return false, `Stand-in report {index} counted {standIns[index]} in a row, not {count}`
		end
	end

	local gaps: { number | string } = rig:reported("gap")
	local ended: { number } = { 1 / RATE, (STAND_IN + 1) / RATE }
	if #gaps ~= #ended then
		return false, `{#gaps} gaps were reported, not {#ended}`
	end

	for index: number, seconds: number in ended do
		local gap: any = gaps[index]
		if type(gap) ~= "number" or math.abs(gap - seconds) > CLOSE then
			return false, `Gap {index} measured {gap} s, not {seconds}`
		end
	end

	return true, nil
end
