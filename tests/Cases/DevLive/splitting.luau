--[[
    A report splits into pieces no larger than the server's piece size,
    which stays inside the runReport event's bound, that join back byte for
    byte, none cut inside a UTF-8 character, and an empty text into none
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local LIVE_RUNS: string = "dev/Shared/LiveRuns.luau"
local CONFIG: string = "dev/Server/Config/Live.luau"
local EVENT_BYTES: number = 4000 -- The runReport event's text, string(0..4000) in dev/Schemas/Dev.volt

-- 18 B of one-, two-, three- and four-byte characters, so cuts at a 4,000 B size fall inside characters
local UNIT: string = "ab日本語é😀\n"
local UNITS: number = 1500 -- 27,000 B, past six pieces
local STRAY: string = "\x80" -- A continuation byte with no character to start it
local STRAYS: number = 9000

-- Why the pieces of a text fail, nil when they pass
local function check(text: string, pieces: { string }, size: number): string?
	for index: number, piece: string in pieces do
		if #piece > size then
			return `Piece {index} carries {#piece} B, past the piece size of {size} B`
		elseif #piece == 0 then
			return `Piece {index} is empty`
		end
	end

	if table.concat(pieces) ~= text then
		return "The pieces did not join back byte for byte"
	end

	return nil
end

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local LiveRuns: any = place.load(LIVE_RUNS)
	local size: number = place.load(CONFIG).pieceBytes

	if size > EVENT_BYTES then
		return false, `The server's piece size of {size} B is past the runReport event's {EVENT_BYTES} B`
	end

	-- 1) Text of many-byte characters: whole characters in every piece, joining back
	local text: string = string.rep(UNIT, UNITS)
	local pieces: { string } = LiveRuns.split(text, size)
	local failure: string? = check(text, pieces, size)
	if failure then
		return false, failure
	end

	local backedOff: boolean = false
	for index: number, piece: string in pieces do
		if utf8.len(piece) == nil then
			return false, `Piece {index} is cut inside a UTF-8 character`
		elseif index < #pieces and #piece < size then
			backedOff = true
		end
	end

	if not backedOff then
		return false, "No cut fell inside a character, so the case proves nothing of the backing off"
	end

	-- 2) An empty text gives no piece
	local empty: { string } = LiveRuns.split("", size)
	if #empty ~= 0 then
		return false, `An empty text split into {#empty} pieces`
	end

	-- 3) Malformed text, a run of continuation bytes, still ends and joins back
	local strays: string = string.rep(STRAY, STRAYS)
	local strayFailure: string? = check(strays, LiveRuns.split(strays, size), size)
	if strayFailure then
		return false, `A run of stray continuation bytes: {strayFailure}`
	end

	-- 4) A size under one character's most bytes, or not whole, is refused
	if pcall(LiveRuns.split, text, 3) or pcall(LiveRuns.split, text, 4.5) then
		return false, "The split took a piece size of 3 B or 4.5 B"
	end

	return true, nil
end
