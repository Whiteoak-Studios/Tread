--[[
    The server compares no check: later copies with other checks, as a
    client that replayed sends, raise no moveTamper and are passed over
    unread like any copy the same, while a moved copy is still reported
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The first tick stepped
local COUNT: number = 3 -- Commands in each Move
local LARGEST: number = 2 ^ 32 - 1
local MOVED: number = 5 -- A differing copy's move steps along X

-- Encodes commands newest first from newest, sets each one's check, and delivers them from the rig's bot
local function send(rig: Intake.Intake, newest: number, check: (position: number) -> number): any
	local move: any = rig:encode(rig:commands(newest, COUNT))
	for position: number, wire: any in move.commands do
		wire.check = check(position)
	end

	rig:deliver()

	return move
end

-- Runs the stream with lazy decode on or off, and gives how far Commands.skipped rose at the repeat, or why it failed
local function stream(rig: Intake.Intake): (number, string?)
	rig:take(START)

	-- First copies of 103, 102 and 101
	send(rig, START + COUNT, function (position: number): number
		return position
	end)

	-- All three again with new checks, the largest u32 among them
	local before: number = rig.Commands.skipped()
	send(rig, START + COUNT, function (position: number): number
		return LARGEST - position + 1
	end)

	local rise: number = rig.Commands.skipped() - before
	if #rig:reported("moveTamper") ~= 0 then
		return rise, "A copy that differed only in its check was reported as tampered"
	end

	-- A copy of 103 whose move differs, with the first copy's check
	local move: any = rig:encode(rig:commands(START + COUNT, 1))
	move.commands[1].moveX = MOVED
	move.commands[1].check = 1
	rig:deliver()

	local tampered: { number | string } = rig:reported("moveTamper")
	if #tampered ~= 1 or tampered[1] ~= START + COUNT then
		return rise, `A moved copy with the first copy's check raised {#tampered} moveTamper reports`
	end

	for tick: number = START + 1, START + COUNT do
		local command: any, standIn: boolean = rig:take(tick)
		if standIn or command.number ~= tick or command.right ~= 0 then
			return rise, `Tick {tick} ran other than its first copy`
		end
	end

	return rise, nil
end

return function (): (boolean, string | nil)
	local on: Intake.Intake = Intake.new()
	local rise: number, broken: string? = stream(on)
	if broken then
		return false, `With lazy decode on: {broken}`
	elseif rise ~= COUNT then
		return false, `With lazy decode on, the copies with new checks raised Commands.skipped by {rise}, not {COUNT}`
	end

	local off: Intake.Intake = Intake.new()
	off.Commands.useLazy(false)
	rise, broken = stream(off)
	if broken then
		return false, `With lazy decode off: {broken}`
	elseif rise ~= 0 then
		return false, `With lazy decode off, Commands.skipped rose by {rise}`
	end

	return true, nil
end
