--[[
    Commands refuses a Move or a take before start, a second start, a tick
    not whole or not after the last taken, and anything but a connection,
    and answers for a connection it never heard of with nothing
--]]

--!strict
local Environment = require("../../Environment")
local Intake = require("../../Fixtures/Commands/Intake")
local Refuses = require("../../Fixtures/Codec/Refuses")

local COMMANDS: string = "src/Server/Commands.luau"
local START: number = 100 -- The first tick stepped

return function (): (boolean, string | nil)
	local unstarted: any = Environment.load(COMMANDS)
	local stranger: any = { player = { Name = "Stranger" } }

	local refused: boolean, why: string = Refuses("before Commands.start", unstarted.receive, stranger, 0, 0, 0, 0, {})
	if not refused then
		return false, `A Move was taken in before start: {why}`
	end

	refused, why = Refuses("before Commands.start", unstarted.take, stranger, START)
	if not refused then
		return false, `A take ran before start: {why}`
	end

	local rig: Intake.Intake = Intake.new()
	local Commands: any = rig.Commands

	refused, why = Refuses("runs once", Commands.start, rig.shared, rig.layout)
	if not refused then
		return false, `Commands started twice: {why}`
	end

	refused, why = Refuses("whole tick", Commands.take, rig.connection, START + 0.5)
	if not refused then
		return false, `A take for half a tick ran: {why}`
	end

	rig:take(START)

	refused, why = Refuses("not after the last tick", Commands.take, rig.connection, START)
	if not refused then
		return false, `A tick was taken twice: {why}`
	end

	refused, why = Refuses("not after the last tick", Commands.take, rig.connection, START - 1)
	if not refused then
		return false, `A tick before the last one taken was taken: {why}`
	end

	refused, why = Refuses("connection record", Commands.receive, nil, 0, 0, 0, 0, {})
	if not refused then
		return false, `A Move from no connection was taken in: {why}`
	end

	local sequence: number, mask: number = Commands.acknowledged(stranger)
	if sequence ~= 0 or mask ~= 0 or Commands.depth(stranger) ~= 0 or Commands.delay(stranger) ~= 0 then
		return false, "A connection Commands never heard of acknowledged or queued something"
	end

	Commands.drop(stranger)
	Commands.remove(stranger)

	return true, nil
end
