--[[
    With the split engaged on the workers, a tick's whole OwnerState leaves
    on its own Heartbeat, the dispatch runs on the next and its blocks and
    acknowledgment leave on the one after, each in an order a client takes
--]]

--!strict
local SplitSide = require("../../Fixtures/Server/SplitSide")

local TICKS: number = 25
local FULL_AT: number = 23 -- A deferred tick the client files no command for, so it steps a stand-in and goes whole
local ACK_BYTES: number = 5 -- An acknowledgment's: an OwnerState's command, tick and queue depth

type Driven = SplitSide.Driven

-- The Heartbeat a tick's arrival of a kind came in, or why it came in none or several
local function only(split: { { string } }, kind: string, tick: number): (number?, number, string?)
	local beats: { number }, sizes: { number } = SplitSide.found(split, kind, tick)
	if #beats == 0 then
		return nil, 0, `tick {tick} gave the client no {kind}`
	end

	for _, beat: number in beats do
		if beat ~= beats[1] then
			return nil, 0, `tick {tick}'s {kind} arrivals came at Heartbeats {beats[1]} and {beat}`
		end
	end

	if kind == "owner" and #beats ~= 1 then
		return nil, 0, `tick {tick} sent the client {#beats} Owner messages, not one`
	end

	return beats[1], sizes[1], nil
end

-- Why a tick's flags, dispatch, blocks and Owner message came other than where the split puts them, or nil
local function check(driven: Driven, split: { { string } }, tick: number): string?
	local Tick: any = driven.side.Tick
	local engaged: boolean = tick >= SplitSide.CALM
	local own: number = SplitSide.place(tick, 1)

	-- Deferred, the tick runs alone, its rest holds on the next Heartbeat and its finish ends the hold on the one after
	local flags: { number } = engaged and { Tick.TICKED, Tick.DEFERRED + Tick.HELD, Tick.POLLED + Tick.RELEASED }
		or { Tick.TICKED + Tick.HELD, Tick.POLLED + Tick.RELEASED, 0 }
	for place: number, expected: number in flags do
		local got: number = driven.flags[SplitSide.place(tick, place)]
		if got ~= expected then
			return `Tick {tick}'s Heartbeat {place} of three had the flags {got}, not {expected}`
		end
	end

	local dispatched: number?, _, missing: string? = only(split, "dispatch", tick)
	if missing then
		return missing
	end

	local blocked: number?, _, absent: string? = only(split, "relay", tick)
	if absent then
		return absent
	end

	local owned: number?, bytes: number, unsent: string? = only(split, "owner", tick)
	if unsent then
		return unsent
	end

	local later: number = engaged and 1 or 0
	local full: boolean = tick == 1 or tick == FULL_AT

	if dispatched ~= own + later then
		return `Tick {tick} was dispatched at Heartbeat {dispatched}, not {own + later}`
	elseif blocked ~= own + 1 + later then
		return `Tick {tick}'s blocks came at Heartbeat {blocked}, not {own + 1 + later}`
	elseif full and (bytes <= ACK_BYTES or owned ~= own) then
		return `Tick {tick}'s whole OwnerState came at Heartbeat {owned} as {bytes} B, not at its own, {own}`
	elseif not full and (bytes ~= ACK_BYTES or owned ~= blocked) then
		return `Tick {tick}'s Owner message came at Heartbeat {owned} as {bytes} B, not acknowledged with its blocks`
	end

	return nil
end

-- Why the client heard an Owner message no newer than one before, or a block older than one before, or nil
local function ordered(arrivals: { string }): string?
	local owner: number = 0
	local relay: number = 0

	for _, arrival: string in arrivals do
		local kind: string?, at: string? = arrival:match("^(%a+) (%d+)")
		local tick: number = tonumber(at) or 0
		if kind == "owner" then
			if tick <= owner then
				return `The client heard tick {tick}'s Owner message after tick {owner}'s`
			end

			owner = tick
		elseif kind == "relay" then
			if tick < relay then
				return `The client heard tick {tick}'s block after tick {relay}'s`
			end

			relay = tick
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local driven: Driven = SplitSide.new({ split = true, workers = true, checks = true })
	driven.full[FULL_AT] = true
	SplitSide.ticks(driven, TICKS)

	local split: { { string } } = SplitSide.segments(driven.side)
	for tick: number = 1, TICKS do
		local wrong: string? = check(driven, split, tick)
		if wrong then
			return false, wrong
		end
	end

	local unordered: string? = ordered(driven.side.arrivals)
	if unordered then
		return false, unordered
	end

	local reported: { number | string } = driven.side.rig:reported("stage")
	if #reported ~= 0 then
		return false, `The stages reported {#reported} failures, the first {reported[1]}`
	end

	return true, nil
end
