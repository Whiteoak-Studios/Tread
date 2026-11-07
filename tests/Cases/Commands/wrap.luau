--[[
    Commands numbered 65535, 0 and 1 run on the ticks after 65534, whether
    the ticks taken wrap or count on, and the ahead limit and late commands
    count across the wrap
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local WRAP: number = 2 ^ 16 -- A command number is a u16
local BEFORE: number = WRAP - 2 -- The tick stepped when the commands arrive

-- Takes the three ticks after BEFORE, written by step, and names the first that ran anything but its own command
local function runs(rig: Intake.Intake, step: (ahead: number) -> number): string?
	for ahead: number = 1, 3 do
		local command: any, standIn: boolean = rig:take(step(ahead))
		local expected: number = (BEFORE + ahead) % WRAP

		if standIn then
			return `Tick {step(ahead)} ran a stand-in, where command {expected} was filed`
		elseif command.number ~= expected then
			return `Tick {step(ahead)} ran command {command.number}, not {expected}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	-- Ticks that count on past the wrap
	local rig: Intake.Intake = Intake.new()
	rig:take(BEFORE)
	rig:send(rig:commands(BEFORE + 3, 3))

	local problem: string? = runs(rig, function (ahead: number): number
		return BEFORE + ahead
	end)

	if problem then
		return false, problem
	end

	local standIn: any, isStandIn: boolean = rig:take(BEFORE + 4)
	if not isStandIn or standIn.number ~= (BEFORE + 4) % WRAP then
		return false, `The stand-in after the wrap is numbered {standIn.number}, not {(BEFORE + 4) % WRAP}`
	end

	-- 6 ticks ahead of the newest stepped, and 5 behind it, each across the wrap
	rig:send(rig:commands(BEFORE + 10, 1))
	rig:send(rig:commands(BEFORE - 1, 1))

	local ahead: { number | string } = rig:reported("ahead")
	local late: { number | string } = rig:reported("late")
	if #ahead ~= 1 or ahead[1] ~= 6 then
		return false, `A command 6 ahead across the wrap was reported ahead {#ahead} times, measuring {ahead[1]}`
	elseif #late ~= 1 or late[1] ~= 6 then
		return false, `A command whose tick ran 5 ticks ago across the wrap was reported late {#late} times`
	end

	-- Ticks that wrap with the command numbers
	rig = Intake.new()
	rig:take(BEFORE)
	rig:send(rig:commands(BEFORE + 3, 3))

	problem = runs(rig, function (ahead: number): number
		return (BEFORE + ahead) % WRAP
	end)

	if problem then
		return false, `With wrapping ticks: {problem}`
	end

	return true, nil
end
