--[[
    Commands.skipped rises by exactly the copies the ring holds the same of
    inside its window, by none before a tick has run or with lazy decode
    off, and Commands.lazyOn follows Commands.useLazy
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The first tick stepped
local SIZE: number = 13 -- Frontier Zero's ring: ticks.ahead's 5 and the 8 ticks a Move carries
local OTHER_YAW: number = 1 -- Radians, a differing copy's

-- How far Commands.skipped rises at each Move of the stream below with lazy decode on
local RISES: { number } = { 0, 0, 0, 3, 1, 0, 1, 3, 4, 0 }

-- Sends commands from the rig's bot, and adds how far Commands.skipped rose to rises
local function send(rig: Intake.Intake, rises: { number }, commands: { any })
	local before: number = rig.Commands.skipped()
	rig:send(commands)

	table.insert(rises, rig.Commands.skipped() - before)
end

--[[
    The hand-built stream, every command at rest, so each copy of one is the
    same as its first unless a step changes it. Gives each Move's rise, and
    the reason when a tick ran anything but its own command
--]]

local function stream(rig: Intake.Intake): ({ number }, string?)
	local rises: { number } = {}

	-- 1 and 2) Before any tick has run, twice
	send(rig, rises, rig:commands(START + 3, 3))
	send(rig, rises, rig:commands(START + 3, 3))

	-- 3) First copies of 103, 102 and 101 into an empty ring, and 4) all three again
	rig:take(START)
	send(rig, rises, rig:commands(START + 3, 3))
	send(rig, rises, rig:commands(START + 3, 3))

	-- 5) A first copy of 104, a copy of 103 that differs, and 102 the same
	local differing: { any } = rig:commands(START + 4, 3)
	differing[2].yaw = OTHER_YAW
	send(rig, rises, differing)

	-- 6) 107 and 106 past the ahead limit and a first copy of 105, and 7) all three again
	send(rig, rises, rig:commands(START + 7, 3))
	send(rig, rises, rig:commands(START + 7, 3))

	for tick: number = START + 1, START + 4 do
		local command: any, standIn: boolean = rig:take(tick)
		if standIn then
			return rises, `Tick {tick} ran a stand-in, where its command was filed`
		elseif command.number ~= tick then
			return rises, `Tick {tick} ran command {command.number}, not its own`
		end
	end

	-- 8) 105 waiting for its tick and 104 and 103 run, all held
	send(rig, rises, rig:commands(START + 5, 3))

	for tick: number = START + 5, START + 9 do
		rig:take(tick)
	end

	-- 9) First copies of 108, 107 and 106 after their ticks, 105 to 102 held, and 101 at the ring's far edge
	send(rig, rises, rig:commands(START + 8, 8))

	-- 10) A first copy of 114, whose slot still holds 101 with the same wire
	send(rig, rises, rig:commands(START + SIZE + 1, 1))

	return rises, nil
end

return function (): (boolean, string | nil)
	local on: Intake.Intake = Intake.new()
	if not on.Commands.lazyOn() then
		return false, "Lazy decode was off from start"
	end

	local off: Intake.Intake = Intake.new()
	off.Commands.useLazy(false)
	if off.Commands.lazyOn() then
		return false, "Commands.lazyOn gave true after Commands.useLazy(false)"
	end

	local rises: { number }, broken: string? = stream(on)
	if broken then
		return false, `With lazy decode on: {broken}`
	elseif #rises ~= #RISES then
		return false, `The stream sent {#rises} Moves, not {#RISES}`
	end

	for index: number, rise: number in RISES do
		if rises[index] ~= rise then
			return false, `Move {index} raised Commands.skipped by {rises[index]}, not {rise}`
		end
	end

	local offRises: { number }, offBroken: string? = stream(off)
	if offBroken then
		return false, `With lazy decode off: {offBroken}`
	end

	for index: number, rise: number in offRises do
		if rise ~= 0 then
			return false, `With lazy decode off, Move {index} raised Commands.skipped by {rise}`
		end
	end

	if #on.heard ~= #off.heard then
		return false, `Lazy decode on fired {#on.heard} reports and off {#off.heard}`
	end

	for index: number, heard: Intake.Heard in on.heard do
		local other: Intake.Heard = off.heard[index]
		if heard.kind ~= other.kind or heard.measurement ~= other.measurement then
			return false, `Report {index} was {heard.kind} {heard.measurement} on, {other.kind} {other.measurement} off`
		end
	end

	off.Commands.useLazy(true)
	if not off.Commands.lazyOn() then
		return false, "Commands.lazyOn gave false after Commands.useLazy(true)"
	end

	local took: boolean = pcall(on.Commands.useLazy, "on")
	if took then
		return false, "Commands.useLazy took a string"
	end

	return true, nil
end
