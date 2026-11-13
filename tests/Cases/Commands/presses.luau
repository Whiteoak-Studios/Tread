--[[
    Each real command's presses are its buttons held and not held in the
    client's command before it: the one the queue holds, a discarded one
    included, and with none held the last real command that ran
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The first tick stepped
local GAP: number = 30 -- Stand-ins in a row, more than the ring holds behind

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	rig:take(START)

	-- Jump held at 101 and 102, let go at 103 and held again at 104; sprint held from 102
	local commands: { any } = rig:commands(START + 4, 4)
	commands[4].jump = true
	commands[3].jump = true
	commands[3].sprint = true
	commands[2].sprint = true
	commands[1].jump = true
	commands[1].sprint = true
	rig:send(commands)

	local jumps: { boolean } = { true, false, false, true }
	local sprints: { boolean } = { false, true, false, false }
	for ahead: number = 1, 4 do
		local command: any = rig:take(START + ahead)
		if command.pressed.jump ~= jumps[ahead] or command.pressed.sprint ~= sprints[ahead] then
			local pressed: any = command.pressed
			return false, `Command {START + ahead} pressed jump {pressed.jump} and sprint {pressed.sprint}`
		end
	end

	-- 105 lets go of jump after its tick ran, and 106 holds it again: a press against the client's own 105
	rig:take(START + 5)
	commands = rig:commands(START + 6, 2)
	commands[1].jump = true
	rig:send(commands)

	local again: any = rig:take(START + 6)
	if not again.pressed.jump then
		return false, "A jump pressed again after a discarded command let it go was swallowed"
	end

	-- A long gap: with no earlier command held, the last real one, holding jump, is what 106 + GAP + 1 presses against
	for tick: number = START + 7, START + 6 + GAP do
		rig:take(tick)
	end

	local after: any = rig:command(START + 7 + GAP)
	after.jump = true
	rig:send({ after })

	local resumed: any = rig:take(START + 7 + GAP)
	if resumed.pressed.jump then
		return false, "A jump held across a long gap was taken as a new press"
	end

	return true, nil
end
