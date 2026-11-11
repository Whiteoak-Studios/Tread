--[[
    A body late reveal's line names its set and its point by the body
    point's name, with no hull-only mark, and a window's summary counts the
    body set's reveals by those names ahead of the hull set's points
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

-- The dev place's body points, in the order its aim lists them
local NAMES: { string } =
	{ "head-top", "left shoulder", "right shoulder", "torso", "left lower leg", "right lower leg" }

local UPS: { number } = { 5, 4, 4, 3, 1, 1 } -- Each one's height over the feet, standing
local LENIENT_POINTS: { number } = { 1, 2, 2, 6 }
local STRICT_POINTS: { number } = { 4 }

local LENIENT: string =
	"body lenient head-top 1, left shoulder 2, right shoulder 0, torso 0, left lower leg 0, right lower leg 1"
local STRICT: string =
	"body strict head-top 0, left shoulder 0, right shoulder 0, torso 1, left lower leg 0, right lower leg 0"
local HULL_ZEROS: string = "center 0, top corners 0 (top front left 0, top back left 0, top front right 0, "
	.. "top back right 0), bottom corners 0 (bottom front left 0, bottom back left 0, bottom front right 0, "
	.. "bottom back right 0)"

-- A body episode at a point, with the rest its line needs
local function episodeAt(reading: string, point: number): { [string]: any }
	return {
		set = "body",
		reading = reading,
		viewer = "Viewer",
		target = "Target",
		real = false,
		distance = 12,
		point = point,
		height = UPS[point],
		speed = 0,
		start = 3,
		length = 2,
		reason = "Hidden",
		hullOnly = false,
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local Reveals: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Reveals)

	-- 1) Each body point's line names it, its height with it, and carries no hull-only mark
	for point: number, name: string in NAMES do
		local line: string = Reveals.describe(episodeAt("lenient", point))
		local named: string =
			string.format("opened at point %d (%s, %.2f studs up), horizontal", point, name, UPS[point])

		if string.find(line, "G8 body lenient late reveal: ", 1, true) ~= 1 then
			return false, `A body episode printed "{line}", which does not name its set first`
		elseif not string.find(line, named, 1, true) then
			return false, `A body episode at point {point} printed "{line}", which does not name it "{name}"`
		end
	end

	-- 2) The summary counts the body set's reveals by name, ahead of the hull set's points
	local episodes: { any } = {}
	for _, point: number in LENIENT_POINTS do
		table.insert(episodes, episodeAt("lenient", point))
	end

	for _, point: number in STRICT_POINTS do
		table.insert(episodes, episodeAt("strict", point))
	end

	local summary: string = Reveals.byPoint(episodes)
	local hull: string = `hull lenient {HULL_ZEROS}; hull strict {HULL_ZEROS}`
	local expected: string = `G8 late reveals by the point that opened them: {LENIENT}; {STRICT}; {hull}`
	if summary ~= expected then
		return false, `The summary read "{summary}", not "{expected}"`
	end

	return true, nil
end
