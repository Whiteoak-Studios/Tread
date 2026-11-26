--[[
    A crossing's printed line from ticks tracked as the server sees them
    and the client's frames carried through its line and back: every field
    with a known answer, a reveal with no past, and a crossing with nothing
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local RATE: number = 20 -- Relay ticks a second, which the hold counts by
local LINE_BYTES: number = 2048 -- The clientCost event's line
local MANY: number = 1000 -- Frames past what one line carries
local STEP: number = 100.25 -- Relay ticks between those frames, so each packs to seven bytes

type Frame = { render: number, drawn: boolean }

-- One tick as the check fills it for the tracker
type Seen = {
	tick: number,
	zone: boolean,
	hull: boolean,
	body: boolean,
	reason: string,
	revealed: { number }?,
	hid: boolean,
}

-- The near crossing: Hidden before the zone, found and its reveal riding with three past records at 202, the hull's
-- rays open 205 to 208 and the body's 206 and 207, Clear to 219, held, and the hide riding at 230
local TICKS: { Seen } = {}

local function add(from: number, to: number, zone: boolean, hull: boolean, body: boolean, reason: string, hid: boolean)
	for tick: number = from, to do
		table.insert(
			TICKS,
			{ tick = tick, zone = zone, hull = hull, body = body, reason = reason, revealed = nil, hid = hid }
		)
	end
end

add(200, 200, false, false, false, "Hidden", false)
add(201, 201, true, false, false, "Hidden", false)
add(202, 204, true, false, false, "Clear", false)
add(205, 205, true, true, false, "Clear", false)
add(206, 207, true, true, true, "Clear", false)
add(208, 208, true, true, false, "Clear", false)
add(209, 210, true, false, false, "Clear", false)
add(211, 219, false, false, false, "Clear", false)
add(220, 229, false, false, false, "Hold", false)
add(230, 231, false, false, false, "Hidden", true)
TICKS[3].revealed = { 3, 2, 1 }

-- The client's frames, a quarter-tick multiple each so they pack exactly: undrawn, then drawn from the reveal's
-- arrival at the third, undrawn once more in tick 206 while both sets' rays are open, then drawn again
local RENDERS: { number } = { 198, 198.75, 199.5, 200.25, 201, 201.75, 202.5, 203.25, 204, 204.75, 205.5, 206.25, 207 }
local UNDRAWN: { [number]: boolean } = { [1] = true, [2] = true, [12] = true }
local ARRIVAL: number = 3

local NEAR: string = "GapCrossing viewer 60 path 2 (near) crossing 1 along +Z: entered 205 (body 206), "
	.. "found 202 (-3 from entered), rode 202 with past 3 (ages 3, 2, 1), client 13 frames, "
	.. "reveal arrived at render 199.50, frame 3, drawn at frame 3 (0 after), "
	.. "off 198.00-198.75 on 199.50-205.50 off 206.25-206.25 on 207.00-207.00, "
	.. "frozen at (1999.50, -2027.25), thawed at (1999.50, -2003.75), lateFrames 1 (hull set 1), "
	.. "jump behind the walls true, closed 209 (body 208), hide rode 230, hold 0.55 s from the last Clear, "
	.. "G8 body episodes lenient 0 strict 0"

local BARE: string = "GapCrossing viewer 300 path 30 (far) crossing 2 along -Z: entered - (body -), found 202, "
	.. "rode 202 with past 0 (relay.past is off), client missing: Mike sent no line within 3 s, "
	.. "closed - (body -), hide rode -, hold - from the last Clear, G8 body episodes lenient 0 strict 0"

local EMPTY: string = "GapCrossing viewer 60 path 30 (near) crossing 3 along +Z: entered - (body -), found -, "
	.. "no reveal rode, client missing: no line came, closed - (body -), hide rode -, hold - from the last Clear, "
	.. "G8 body episodes lenient 0 strict 0"

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local Gap: any = loaded.require(dataModel:GetService("ServerScriptService").Server.Gap)
	local GapLine: any = loaded.require(dataModel:GetService("ReplicatedStorage").Shared.Dev.GapLine)

	-- 1) The client's capture through its line and back, each frame's render time and draw kept
	local frames: { Frame } = {}
	for index: number, render: number in RENDERS do
		table.insert(frames, { render = render, drawn = not UNDRAWN[index] })
	end

	local sent: any = {
		frames = frames,
		arrival = ARRIVAL,
		frozen = { x = 1999.5, z = -2027.25 },
		thawed = { x = 1999.5, z = -2003.75 },
		cut = 0,
	}

	local capture: any = GapLine.decode(GapLine.encode(sent))
	if not capture or capture.arrival ~= ARRIVAL or capture.cut ~= 0 or #capture.frames ~= #frames then
		return false, "The client's capture didn't come back through its line whole"
	elseif capture.frozen.x ~= 1999.5 or capture.frozen.z ~= -2027.25 or capture.thawed.z ~= -2003.75 then
		return false, "The frozen rig's places didn't come back through the line"
	end

	for index: number, frame: Frame in frames do
		local back: Frame = capture.frames[index]
		if back.render ~= frame.render or back.drawn ~= frame.drawn then
			return false, `Frame {index} came back at {back.render}, drawn {back.drawn}`
		end
	end

	-- 2) Frames past the line's bytes are cut and counted, the rest kept; no frames and no line carry what they hold
	local many: { Frame } = {}
	for index: number = 1, MANY do
		table.insert(many, { render = index * STEP, drawn = false })
	end

	local long: string = GapLine.encode({ frames = many, arrival = nil, frozen = nil, thawed = nil, cut = 0 })
	local cut: any = GapLine.decode(long)
	if #long > LINE_BYTES or not cut or #cut.frames == 0 or #cut.frames + cut.cut ~= MANY then
		return false, `A capture of {MANY} frames packed to {#long} B and came back as {cut and #cut.frames} frames`
	end

	local none: any =
		GapLine.decode(GapLine.encode({ frames = {}, arrival = nil, frozen = nil, thawed = nil, cut = 0 }))
	if not none or #none.frames ~= 0 or none.arrival ~= nil or none.frozen ~= nil then
		return false, "A capture with no frames didn't come back empty"
	elseif GapLine.decode("no line of the gap check") ~= nil then
		return false, "A line that isn't one decoded to a capture"
	end

	-- 3) The near crossing tracked tick by tick, its frames judged as the check judges them, and its line
	local crossing: any = Gap.crossing("viewer 60 path 2", "near", 1, 1)
	for _, seen: Seen in TICKS do
		Gap.track(crossing, seen)
	end

	local late: number, drawnAt: number? = Gap.judge(capture.frames, capture.arrival, crossing.bodyOpen)
	crossing.client = capture
	crossing.late = late
	crossing.hullLate = Gap.judge(capture.frames, capture.arrival, crossing.open)
	crossing.drawnAt = drawnAt
	crossing.jump = Gap.behind(capture.frozen, capture.thawed, function (place: any): boolean
		return place.z < -2001
	end)

	local line: string = Gap.line(crossing, RATE, true)
	if line ~= NEAR then
		return false, `The near crossing printed "{line}", not "{NEAR}"`
	end

	-- 4) A reveal with no past while relay.past is off, and no line from the client
	local bare: any = Gap.crossing("viewer 300 path 30", "far", 2, -1)
	Gap.track(
		bare,
		{ tick = 201, zone = true, hull = false, body = false, reason = "Hidden", revealed = nil, hid = false }
	)
	Gap.track(
		bare,
		{ tick = 202, zone = true, hull = false, body = false, reason = "Clear", revealed = {}, hid = false }
	)
	bare.missing = "Mike sent no line within 3 s"

	line = Gap.line(bare, RATE, false)
	if line ~= BARE then
		return false, `A reveal with no past printed "{line}", not "{BARE}"`
	end

	-- 5) A crossing that saw nothing at all
	line = Gap.line(Gap.crossing("viewer 60 path 30", "near", 3, 1), RATE, true)
	if line ~= EMPTY then
		return false, `An empty crossing printed "{line}", not "{EMPTY}"`
	end

	return true, nil
end
