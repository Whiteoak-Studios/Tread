--[[
    A command arriving after its tick ran a stand-in is discarded, never
    runs and is reported late and lateShot once, copies and commands older
    than the ring holds included
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The first tick stepped
local FROZEN: number = 130 -- The tick the server reaches while the client is frozen

-- Two shots, each a group the fixture game declares
local SHOTS: { { [string]: number } } = {
	{ sequence = 1, fraction = 0, yaw = 10, class = 1 },
	{ sequence = 2, fraction = -5, yaw = 20, class = 0 },
}

-- Names the first measurement that differs between two lists, or nil when they match
local function differs(actual: { number | string }, expected: { number }): string?
	if #actual ~= #expected then
		return `{#actual} were reported, not {#expected}`
	end

	for index: number, value: number in expected do
		if actual[index] ~= value then
			return `report {index} measured {actual[index]}, not {value}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()

	for tick: number = START, START + 2 do
		rig:take(tick)
	end

	-- Every one of these arrives after its tick ran with a stand-in
	local commands: { any } = rig:commands(START + 2, 3)
	commands[2].fields.shots = SHOTS
	rig:send(commands)
	rig:send(commands)

	local late: string? = differs(rig:reported("late"), { 1, 2, 3 })
	if late then
		return false, `Three late commands sent twice: {late}`
	end

	local shots: string? = differs(rig:reported("lateShot"), { #SHOTS })
	if shots then
		return false, `A late command with {#SHOTS} shots: {shots}`
	end

	local _: any, standIn: boolean = rig:take(START + 3)
	if not standIn or rig.Commands.depth(rig.connection) ~= 0 then
		return false, "A discarded command was queued to run"
	end

	-- The client freezes while the server runs on, then sends commands far older than the ring holds
	for tick: number = START + 4, FROZEN do
		rig:take(tick)
	end

	rig:send(rig:commands(START + 3, 1))
	rig:send(rig:commands(START + 4, 2))

	late = differs(rig:reported("late"), { 1, 2, 3, FROZEN - (START + 3) + 1, FROZEN - (START + 4) + 1 })
	if late then
		return false, `After a freeze, two new commands and a copy: {late}`
	end

	return true, nil
end
