--[[
    The body set's open ticks the client drew no frame in: the tracker keeps
    the open ticks whole and in order, and each meets a frame's render time
    by the wire's 16 bits, across the wrap too
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local WRAP: number = 2 ^ 16 -- A block's relay tick is a u16

type Frame = { render: number, drawn: boolean }

-- One tick as the tracker sees it, only whether the target stood in the zone and the body set found it varying
type Tick = { tick: number, zone: boolean, body: boolean }

local function frame(render: number, drawn: boolean): Frame
	return { render = render, drawn = drawn }
end

-- Whether two lists hold the same numbers in the same order
local function same(given: { number }, expected: { number }): boolean
	if #given ~= #expected then
		return false
	end

	for index: number, value: number in expected do
		if given[index] ~= value then
			return false
		end
	end

	return true
end

-- A list of ticks as the case's failures print it
local function listed(values: { number }): string
	if #values == 0 then
		return "none"
	end

	local parts: { string } = {}
	for _, value: number in values do
		table.insert(parts, tostring(value))
	end

	return table.concat(parts, ", ")
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local Gap: any = loaded.require(server.Gap)

	-- 1) A crossing starts with no open ticks and nothing judged
	local crossing: any = Gap.crossing("pass", "near", 1, 1)
	if #crossing.bodyTicks ~= 0 or crossing.unwatched ~= nil then
		return false, `A new crossing held the ticks {listed(crossing.bodyTicks)}, and unwatched {crossing.unwatched}`
	end

	-- 2) The tracker keeps the body set's open ticks in the zone as the server counts them, past the wrap, in order: not
	-- one outside the zone, not one the body set was blocked in, and the one it reopened on after closing
	local ticks: { Tick } = {
		{ tick = WRAP - 3, zone = false, body = true },
		{ tick = WRAP - 2, zone = true, body = false },
		{ tick = WRAP - 1, zone = true, body = true },
		{ tick = WRAP, zone = true, body = true },
		{ tick = WRAP + 1, zone = true, body = false },
		{ tick = WRAP + 2, zone = true, body = true },
		{ tick = WRAP + 3, zone = false, body = true },
	}

	for _, at: Tick in ticks do
		Gap.track(crossing, {
			tick = at.tick,
			zone = at.zone,
			hull = false,
			body = at.body,
			reason = "Clear",
			revealed = nil,
			hid = false,
		})
	end

	local expected: { number } = { WRAP - 1, WRAP, WRAP + 2 }
	if not same(crossing.bodyTicks, expected) then
		return false, `The tracker kept the open ticks {listed(crossing.bodyTicks)}, not {listed(expected)}`
	end

	-- 3) Across the wrap: the server's ticks 65534 to 65538 against a client whose render times are their wrapped
	-- values. Frames in 65535, 65536 (two of them) and 65538, drawn or not, leave 65534 and 65537, in order
	local open: { number } = { WRAP - 2, WRAP - 1, WRAP, WRAP + 1, WRAP + 2 }
	local frames: { Frame } = {
		frame(WRAP - 0.6, false),
		frame(0.2, true),
		frame(0.7, true),
		frame(2.5, false),
	}

	local unwatched: { number } = Gap.unwatched(frames, open)
	expected = { WRAP - 2, WRAP + 1 }
	if not same(unwatched, expected) then
		return false, `Frames across the wire's wrap left {listed(unwatched)} unwatched, not {listed(expected)}`
	end

	-- 4) No frames leave every tick unwatched, and no ticks leave none
	unwatched = Gap.unwatched({}, open)
	if not same(unwatched, open) then
		return false, `No frames left {listed(unwatched)} unwatched, not {listed(open)}`
	end

	unwatched = Gap.unwatched(frames, {})
	if #unwatched ~= 0 then
		return false, `No ticks left {listed(unwatched)} unwatched, not none`
	end

	return true, nil
end
