--[[
    With every character on one team, no game call between a deferred
    tick's two parts and no viewer near its budget, the split sends every
    block and Owner message byte for byte as without it, a deferred one later
--]]

--!strict
local SplitSide = require("../../Fixtures/Server/SplitSide")

local TICKS: number = 25
local FULL_AT: number = 23 -- A deferred tick the client files no command for, so it goes as a whole OwnerState
local ACK_BYTES: number = 5 -- An acknowledgment's: an OwnerState's command, tick and queue depth
local TEAM: number = 7
local NAMES: { string } = { "Client", "Seen", "Hidden", "Moderator" }

type Driven = SplitSide.Driven

-- A side on the workers, its characters on one team, run its ticks
local function run(split: boolean): Driven
	local driven: Driven = SplitSide.new({ split = split, workers = true, checks = true })
	driven.full[FULL_AT] = true

	for _, name: string in NAMES do
		driven.side.characters[name]:setTeam(TEAM)
	end

	SplitSide.ticks(driven, TICKS)

	return driven
end

-- Why the first list's entries differ from the second's, or nil when they match, length included
local function same(what: string, off: { string }, on: { string }): string?
	if #off ~= #on then
		return `The client had {#off} {what} without the split and {#on} with it`
	end

	for index: number = 1, #off do
		if off[index] ~= on[index] then
			return `The client's {what} {index} differs with the split`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local off: Driven = run(false)
	local on: Driven = run(true)

	local why: string? = same("blocks", off.side.blocks, on.side.blocks)
		or same("Owner messages", off.side.owners, on.side.owners)
	if why then
		return false, why
	end

	-- Each tick's blocks and acknowledgment come a Heartbeat later once it defers, and a whole OwnerState never does
	local offSplit: { { string } } = SplitSide.segments(off.side)
	local onSplit: { { string } } = SplitSide.segments(on.side)

	for tick: number = 1, TICKS do
		local later: number = tick >= SplitSide.CALM and 1 or 0

		for _, kind: string in { "relay", "owner" } do
			local offBeats: { number }, sizes: { number } = SplitSide.found(offSplit, kind, tick)
			local onBeats: { number } = SplitSide.found(onSplit, kind, tick)
			local whole: boolean = kind == "owner" and sizes[1] ~= nil and sizes[1] > ACK_BYTES
			local shift: number = whole and 0 or later

			if #offBeats == 0 or #offBeats ~= #onBeats then
				return false,
					`Tick {tick} gave the client {#offBeats} {kind} arrivals without the split, {#onBeats} with`
			end

			for index: number, beat: number in offBeats do
				if onBeats[index] ~= beat + shift then
					local at: string = `at Heartbeat {onBeats[index]}, not {beat + shift}`
					return false, `Tick {tick}'s {kind} arrival {index} came with the split {at}`
				end
			end
		end
	end

	local reported: { number | string } = on.side.rig:reported("stage")
	if #reported ~= 0 or #off.side.rig:reported("stage") ~= 0 then
		return false, "The stages reported failures"
	end

	return true, nil
end
