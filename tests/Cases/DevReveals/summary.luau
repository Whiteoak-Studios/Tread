--[[
    The summary line's counts lead with the body set's under each reading,
    which G8's line reads, then the hull set's and the hull-only reveals',
    each for every viewer, real players alone and every seed so far
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local HOURS: number = 2 -- Viewer-hours the window watched
local REAL_HOURS: number = 1 -- Of them, real players'
local POOLED_HOURS: number = 4 -- Every seed's so far

-- The window's episodes, each its set, reading, whether its viewer is real and whether it is hull only
local FOUND: { { any } } = {
	{ "body", "lenient", false, false },
	{ "body", "lenient", false, false },
	{ "body", "lenient", true, false },
	{ "body", "strict", false, false },
	{ "hull", "lenient", false, true },
	{ "hull", "lenient", false, false },
	{ "hull", "strict", true, true },
}

-- An earlier seed's, pooled with the window's
local EARLIER: { { any } } = {
	{ "body", "strict", false, false },
}

local BODY: string = "body lenient 3 (1.50 a viewer-hour), strict 1 (0.50 a viewer-hour); "
	.. "real players alone body lenient 1 (1.00), strict 0 (0.00) a viewer-hour; "
	.. "every seed so far body lenient 0.75, strict 0.50 a viewer-hour"
local HULL: string = "hull lenient 2 (1.00 a viewer-hour), strict 1 (0.50 a viewer-hour); "
	.. "real players alone hull lenient 0 (0.00), strict 1 (1.00) a viewer-hour; "
	.. "every seed so far hull lenient 0.50, strict 0.25 a viewer-hour"
local HULL_ONLY: string = "hull only lenient 1 (0.50 a viewer-hour), strict 1 (0.50 a viewer-hour); "
	.. "real players alone hull only lenient 0 (0.00), strict 1 (1.00) a viewer-hour; "
	.. "every seed so far hull only lenient 0.25, strict 0.25 a viewer-hour"
local LINE: string = `{BODY}; {HULL}; {HULL_ONLY}`
local NONE: string = "body lenient 0 (- a viewer-hour), strict 0 (- a viewer-hour); " -- How an empty window leads

-- Episodes from their rows, with the rest an episode carries
local function episodes(rows: { { any } }): { { [string]: any } }
	local made: { { [string]: any } } = {}
	for _, row: { any } in rows do
		table.insert(made, {
			set = row[1],
			reading = row[2],
			viewer = "Viewer",
			target = "Target",
			real = row[3],
			distance = 10,
			point = 1,
			height = 2.5,
			speed = 0,
			start = 1,
			length = 2,
			reason = "Hidden",
			hullOnly = row[4],
		})
	end

	return made
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local Reveals: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Reveals)

	local found: { { [string]: any } } = episodes(FOUND)
	local pooled: { { [string]: any } } = episodes(EARLIER)
	for _, episode: { [string]: any } in found do
		table.insert(pooled, episode)
	end

	local line: string = Reveals.counts(found, pooled, HOURS, REAL_HOURS, POOLED_HOURS)
	if line ~= LINE then
		return false, `The summary's counts read "{line}", not "{LINE}"`
	end

	-- A window that watched nothing gives each rate as a dash
	local empty: string = Reveals.counts({}, {}, 0, 0, 0)
	if string.find(empty, NONE, 1, true) ~= 1 then
		return false, `An empty window's counts read "{empty}", which does not start "{NONE}"`
	end

	return true, nil
end
