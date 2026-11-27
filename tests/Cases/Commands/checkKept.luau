--[[
    A command's first copy keeps its check, a later copy the same replaces it
    from a Move not older, lazy decode on or off, and Commands.check gives it
    only while the ring holds the command and its tick ran it
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The first tick stepped
local COUNT: number = 3 -- Commands in each full Move
local SEQUENCE: number = 5 -- The first Moves' acknowledgment
local MOVED: number = 5 -- A differing copy's move steps along X
local USES_BITS: number = 0xF0 -- The fixture game's carried counter past its max of 9, which fails the decode
local SIZE: number = 13 -- Frontier Zero's ring: ticks.ahead's 5 and the 8 ticks a Move carries
local AHEAD: number = 5 -- Frontier Zero's ticks.ahead
local SKIPPED: number = 9 -- The copies lazy decode passes over in the stream below: 3, 3, 0, 2 and 1

-- The check every copy of a command carries in one round of the stream, so the kept check names its round
local function checkOf(number: number, round: number): number
	return number * 10 + round
end

-- Encodes commands newest first from newest with the acknowledgment given and each one's check of the round
local function encode(rig: Intake.Intake, newest: number, count: number, acknowledged: number, round: number): any
	local move: any = rig:encode(rig:commands(newest, count), acknowledged)
	for position: number, wire: any in move.commands do
		wire.check = checkOf(newest - (position - 1), round)
	end

	return move
end

-- The game fields of a wire as a buffer of their own with the carried counter's bits all set
local function overflow(fields: buffer): buffer
	local bytes: buffer = buffer.create(buffer.len(fields))
	buffer.copy(bytes, 0, fields)
	buffer.writeu8(bytes, 0, bit32.bor(buffer.readu8(bytes, 0), USES_BITS))

	return bytes
end

--[[
    The stream with lazy decode on or off: the kept checks of 101 to 103
    after their ticks, and the ticks Commands.check must give nil for, each
    with the reason it failed
--]]

local function stream(rig: Intake.Intake): string?
	local function check(number: number): number?
		return rig.Commands.check(rig.connection, number)
	end

	rig:take(START)

	-- 1) First copies of 103, 102 and 101, and none run yet
	encode(rig, START + COUNT, COUNT, SEQUENCE, 1)
	rig:deliver()

	if check(START + 1) ~= nil then
		return "Commands.check gave a check for a command not yet run"
	end

	-- 2) All three the same from a Move as new, and 3) again from an older one
	encode(rig, START + COUNT, COUNT, SEQUENCE, 2)
	rig:deliver()
	encode(rig, START + COUNT, COUNT, SEQUENCE - 1, 3)
	rig:deliver()

	-- 4) A copy of 103 that differs, from a newer Move
	local move: any = encode(rig, START + COUNT, 1, SEQUENCE + 1, 4)
	move.commands[1].moveX = MOVED
	rig:deliver()

	-- 5) A refused Move: a first copy of 104 that fails, with 103 and 102 the same behind it
	move = encode(rig, START + COUNT + 1, COUNT, SEQUENCE + 2, 5)
	move.commands[1].fields = overflow(move.commands[1].fields)
	rig:deliver()

	-- 6) 101 alone the same, from a Move newer than any taken
	encode(rig, START + 1, 1, SEQUENCE + 3, 6)
	rig:deliver()

	for tick: number = START + 1, START + COUNT do
		local _, standIn: boolean = rig:take(tick)
		if standIn then
			return `Tick {tick} ran a stand-in`
		end
	end

	local kept: { [number]: number } = {
		[START + 1] = checkOf(START + 1, 6),
		[START + 2] = checkOf(START + 2, 2),
		[START + 3] = checkOf(START + 3, 2),
	}

	for number: number, expected: number in kept do
		if check(number) ~= expected then
			return `Commands.check gave command {number} the check {check(number)}, not {expected}`
		end
	end

	local tampered: { number | string } = rig:reported("moveTamper")
	if #tampered ~= 1 or tampered[1] ~= START + COUNT or #rig:reported("schema") ~= 1 then
		return `The stream raised {#tampered} moveTamper and {#rig:reported("schema")} schema reports, not one each`
	end

	-- 7) 104 runs a stand-in, then its first copy comes late, and a first copy of 106 waits for its tick
	local stand: number = START + COUNT + 1
	rig:take(stand)
	if check(stand) ~= nil then
		return "Commands.check gave a check for a tick that ran a stand-in"
	end

	encode(rig, stand + 2, COUNT, SEQUENCE + 4, 7)
	rig:deliver()
	if check(stand) ~= nil then
		return "Commands.check gave a check for a command that came after its tick"
	elseif check(stand + 2) ~= nil then
		return "Commands.check gave a check for a command waiting for its tick"
	end

	rig:take(stand + 1)
	rig:take(stand + 2)
	if check(stand + 2) ~= checkOf(stand + 2, 7) then
		return `Once its tick ran it, Commands.check gave command {stand + 2} {check(stand + 2)}`
	end

	-- 8) A first copy of 114 filed over 101's slot, then dropped, as a teleport drops the queue
	local over: number = START + 1 + SIZE
	for tick: number = stand + 3, over - AHEAD do
		rig:take(tick)
	end

	encode(rig, over, 1, SEQUENCE + 5, 8)
	rig:deliver()
	if check(START + 1) ~= nil then
		return "Commands.check gave a check for a command the ring no longer holds"
	end

	rig.Commands.drop(rig.connection)
	for tick: number = over - AHEAD + 1, over do
		rig:take(tick)
	end

	if check(over) ~= nil then
		return "Commands.check gave a check for a dropped command"
	end

	return nil
end

return function (): (boolean, string | nil)
	local on: Intake.Intake = Intake.new()
	local off: Intake.Intake = Intake.new()
	off.Commands.useLazy(false)

	for _, rig: Intake.Intake in { on, off } do
		local state: string = rig.Commands.lazyOn() and "on" or "off"
		local broken: string? = stream(rig)
		if broken then
			return false, `With lazy decode {state}: {broken}`
		end

		local skipped: number = rig == on and SKIPPED or 0
		if rig.Commands.skipped() ~= skipped then
			return false, `With lazy decode {state}, {rig.Commands.skipped()} copies went unread, not {skipped}`
		end
	end

	return true, nil
end
