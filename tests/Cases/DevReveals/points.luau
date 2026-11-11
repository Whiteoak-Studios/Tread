--[[
    A late reveal keeps the point whose ray opened it, that point's height
    and the target's speed from its first sighting, its line names them,
    and a window's summary counts its episodes by the point that opened each
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local TOP_FRONT_LEFT: number = 4 -- (-1, 1, -1) in the harness's points
local BOTTOM_BACK_RIGHT: number = 7 -- (1, -1, 1)
local CENTER: number = 1
local OPENED_HEIGHT: number = 4.95 -- Studs up a 5-stud hull's top corners, pulled 0.05 inside
local LATER_HEIGHT: number = 2.5 -- Its center's
local BOTTOM_HEIGHT: number = 0.05 -- Its bottom corners'
local OPENED_SPEED: number = 18 -- Studs a second across the ground at the run's first sighting
local LATER_SPEED: number = 6 -- And at every one after it
local DISTANCE: number = 10 -- Studs, plus the tick, so each episode's distance names the tick it was read on
local UNSENT: number = 2 -- The tick the target's unsent stretch and its run of visible ticks both begin on

-- A window's episodes by reading and point, and the line the summary gives for them
local LENIENT_POINTS: { number } = { 1, 4, 4, 9, 2 }
local STRICT_POINTS: { number } = { 7, 7, 1 }

local LENIENT_TOP: string = "top corners 3 (top front left 2, top back left 0, top front right 0, top back right 1)"
local LENIENT_BOTTOM: string =
	"bottom corners 1 (bottom front left 1, bottom back left 0, bottom front right 0, bottom back right 0)"
local STRICT_TOP: string = "top corners 0 (top front left 0, top back left 0, top front right 0, top back right 0)"
local STRICT_BOTTOM: string =
	"bottom corners 2 (bottom front left 0, bottom back left 0, bottom front right 0, bottom back right 2)"
local LENIENT_LINE: string = `lenient center 1, {LENIENT_TOP}, {LENIENT_BOTTOM}`
local STRICT_LINE: string = `strict center 1, {STRICT_TOP}, {STRICT_BOTTOM}`
local SUMMARY: string = `G8 late reveals by the point that opened them: {LENIENT_LINE}; {STRICT_LINE}`
local COUNT: string = " %d+" -- Each count in the summary, after its space

-- An episode as the summary reads it, with the rest its line needs
local function episodeAt(reading: string, point: number): { [string]: any }
	return {
		reading = reading,
		viewer = "Viewer",
		target = "Target",
		real = false,
		distance = DISTANCE,
		point = point,
		height = LATER_HEIGHT,
		speed = LATER_SPEED,
		start = 1,
		length = 1,
		reason = "Hidden",
	}
end

-- Why an episode differs from the start, point, height and speed it should carry, or nil when it matches
local function mismatch(episode: any, start: number, point: number, height: number, speed: number): string?
	if episode.start ~= start then
		return `The {episode.reading} episode started at {episode.start}, not {start}`
	elseif episode.point ~= point or episode.height ~= height or episode.speed ~= speed then
		local carried: string = `point {episode.point}, {episode.height} studs up at {episode.speed} studs/s`
		return `The {episode.reading} episode carried {carried}, not point {point}, {height} up at {speed}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local Reveals: any = loaded.require(server.Reveals)
	local grace: number = loaded.require(server.Config.Reveals).grace

	-- 1) Sent, then unsent and visible at once: at the top front left corner first, then the center until strict counts
	local pair: any = Reveals.pair()
	local found: { any } = {}
	local seen: any =
		{ tick = 0, sent = false, visible = false, distance = 0, point = 0, height = 0, speed = 0, reason = "" }

	local last: number = UNSENT + grace + 1
	for tick: number = 1, last do
		local opening: boolean = tick == UNSENT

		seen.tick = tick
		seen.sent = tick < UNSENT
		seen.visible = tick >= UNSENT
		seen.distance = DISTANCE + tick
		seen.point = opening and TOP_FRONT_LEFT or CENTER
		seen.height = opening and OPENED_HEIGHT or LATER_HEIGHT
		seen.speed = opening and OPENED_SPEED or LATER_SPEED
		seen.reason = `R{tick}`

		Reveals.track(pair, seen, grace, found, "Viewer", "Target", false)
	end

	local lenient: any, strict: any = nil, nil
	for _, episode: any in found do
		if episode.reading == "lenient" then
			lenient = episode
		else
			strict = episode
		end
	end

	if #found ~= 2 or not lenient or not strict then
		return false, `The run counted {#found} episodes, not one under each reading`
	end

	-- Lenient keeps its run's first sighting, strict the sighting it opened on
	local failure: string? = mismatch(lenient, UNSENT, TOP_FRONT_LEFT, OPENED_HEIGHT, OPENED_SPEED)
		or mismatch(strict, last, CENTER, LATER_HEIGHT, LATER_SPEED)

	if failure then
		return false, failure
	end

	-- 2) Its line names the point, its height and the speed
	local line: string = Reveals.describe(lenient)
	local named: string = "opened at point 4 (top front left, 4.95 studs up), horizontal speed 18.0 studs/s"
	if string.sub(line, -#named) ~= named then
		return false, `The lenient episode printed "{line}", which does not end "{named}"`
	end

	local bottom: { [string]: any } = episodeAt("strict", BOTTOM_BACK_RIGHT)
	bottom.height = BOTTOM_HEIGHT

	local corner: string = Reveals.describe(bottom)
	if not string.find(corner, "opened at point 7 (bottom back right, 0.05 studs up)", 1, true) then
		return false, `An episode opened at point 7 printed "{corner}"`
	end

	local center: string = Reveals.describe(episodeAt("strict", CENTER))
	if not string.find(center, "opened at point 1 (center, 2.50 studs up)", 1, true) then
		return false, `An episode opened at the center printed "{center}"`
	end

	-- 3) The summary counts a window's episodes by the point that opened each
	local episodes: { any } = {}
	for _, point: number in LENIENT_POINTS do
		table.insert(episodes, episodeAt("lenient", point))
	end

	for _, point: number in STRICT_POINTS do
		table.insert(episodes, episodeAt("strict", point))
	end

	local summary: string = Reveals.byPoint(episodes)
	if summary ~= SUMMARY then
		return false, `The summary read "{summary}", not "{SUMMARY}"`
	end

	-- 4) A window with none counts zero at every point
	local zeros: string = string.gsub(SUMMARY, COUNT, " 0")
	local empty: string = Reveals.byPoint({})
	if empty ~= zeros then
		return false, `A window with no late reveals summed to "{empty}", not "{zeros}"`
	end

	return true, nil
end
