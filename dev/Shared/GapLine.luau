--[[
    The gap check's client line: one window's frames by render time and
    whether the target's rig was drawn, its reveal's arrival and the frozen
    rig's two places, packed into the clientCost line both realms read
--]]

--!strict
local CENTI: number = 100 -- Render times are packed in whole hundredths of a relay tick, rounded down
local NONE: string = "-" -- A field with no value
local DRAWN: string = "d" -- A frame whose target rig was drawn
local UNDRAWN: string = "u" -- One whose wasn't
local SEPARATOR: string = "," -- Between the frames
local CUT_ROOM: number = 16 -- Bytes kept free past the head for the count of frames cut
local PLACE_FIGURE: string = "%.2f,%.2f" -- A place's X and Z

-- The line's head, then its frames: each a drawn mark and its render time's step from the frame before
local HEAD: string = "^a=(%S+) f=(%S+) t=(%S+) r=(%-?%d+) c=(%d+) ?(.*)$"
local FRAME: string = "([du])(%-?%d+)"
local PLACE: string = "^(%-?[%d%.]+),(%-?[%d%.]+)$"

-- One frame the client drew while the window was open
export type Frame = {
	render: number, -- Its render time, in relay ticks with their fraction
	drawn: boolean, -- Whether the target's rig stood drawn as the frame ended, between its spawn and its despawn
}

-- Where a rig's root stood across the ground
export type Place = {
	x: number,
	z: number,
}

-- What one window recorded
export type Capture = {
	frames: { Frame },
	arrival: number?, -- The frame the target's reveal arrived in, nil for none
	frozen: Place?, -- Where the frozen rig stood as the window opened, nil for none
	thawed: Place?, -- Where its reveal's first pose put it, nil for none in the window
	cut: number, -- Frames left out past the line's bytes
}

local GapLine = {
	ATTRIBUTE = "TreadGap", -- The Workspace attribute the server opens each window with, its label
	SLOT = "TreadGapSlot", -- The one naming the target's slot
	LINE_BYTES = 2048, -- The clientCost event's line, string(1..2048) in dev/Schemas/Dev.volt
}

local function placeText(place: Place?): string
	if not place then
		return NONE
	end

	return string.format(PLACE_FIGURE, place.x, place.z)
end

local function placeOf(text: string): Place?
	local x: string?, z: string? = string.match(text, PLACE)
	local east: number? = x and tonumber(x)
	local south: number? = z and tonumber(z)
	if east == nil or south == nil then
		return nil
	end

	return { x = east, z = south }
end

--[[
    The capture's line, its frames as many as fit the event's bytes, the
    rest counted as cut, each render time rounded down to the hundredth so
    a frame never moves into a later tick
--]]

function GapLine.encode(capture: Capture): string
	local frames: { Frame } = capture.frames
	local base: number = 0
	if #frames > 0 then
		base = math.floor(frames[1].render * CENTI)
	end

	local arrival: string = NONE
	if capture.arrival ~= nil then
		arrival = tostring(capture.arrival)
	end

	local head: string = `a={arrival} f={placeText(capture.frozen)} t={placeText(capture.thawed)} r={base}`
	local room: number = GapLine.LINE_BYTES - #head - CUT_ROOM
	local tokens: { string } = {}
	local used: number = 0
	local last: number = base
	local cut: number = capture.cut

	for index: number, frame: Frame in frames do
		local at: number = math.floor(frame.render * CENTI)
		local mark: string = frame.drawn and DRAWN or UNDRAWN
		local token: string = `{mark}{at - last}`
		if used + #token + #SEPARATOR > room then
			cut += #frames - index + 1
			break
		end

		table.insert(tokens, token)
		used += #token + #SEPARATOR
		last = at
	end

	return `{head} c={cut} {table.concat(tokens, SEPARATOR)}`
end

-- The capture a line holds, nil for a line that isn't one
function GapLine.decode(line: string): Capture?
	local arrival: string?, frozen: string?, thawed: string?, base: string?, cut: string?, tokens: string? =
		string.match(line, HEAD)
	local at: number? = base and tonumber(base)
	local dropped: number? = cut and tonumber(cut)
	if not arrival or not frozen or not thawed or not tokens or at == nil or dropped == nil then
		return nil
	end

	local frames: { Frame } = {}
	local render: number = at
	for mark: string, step: string in string.gmatch(tokens, FRAME) do
		render += tonumber(step) :: number
		table.insert(frames, { render = render / CENTI, drawn = mark == DRAWN })
	end

	local arrived: number? = nil
	if arrival ~= NONE then
		arrived = tonumber(arrival)
	end

	return {
		frames = frames,
		arrival = arrived,
		frozen = placeOf(frozen),
		thawed = placeOf(thawed),
		cut = dropped,
	}
end

return GapLine
