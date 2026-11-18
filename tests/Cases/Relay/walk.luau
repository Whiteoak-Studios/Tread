--[[
    Seeded layouts through the relay harness, idle, a fight, wide sleepers
    and tap sinks, give every block, frame and keyframe the digests pinned
--]]

--!strict
local Layouts = require("../../Fixtures/Relay/Layouts")

local EXPECTED: { [string]: string } = Layouts.EXPECTED -- The digests each layout is pinned to

type Result = Layouts.Result

return function (): (boolean, string | nil)
	local idled: Result = Layouts.idle()
	local fought: Result = Layouts.fight()
	local fielded: Result = Layouts.field()
	local tapped: Result = Layouts.taps()

	-- Each layout reaches what it is there for, so its digest pins it
	if idled.reveals == 0 or idled.changes == 0 then
		return false, "The idle layout revealed nothing or sent no still repeat"
	elseif fought.hides == 0 or fought.changes == 0 or fought.footsteps == 0 then
		return false, "The fight hid no one, sent no change or heard no step"
	elseif fielded.reveals == 0 or fielded.hides == 0 then
		return false, "The field's bodies never came into range or never left it"
	elseif fielded.jumped == 0 then
		return false, "The field's jump put no pair a client draws out of range"
	elseif fielded.stale ~= 0 then
		return false,
			`{fielded.stale} of the {fielded.jumped} pairs the jump put out of range were still drawn after its run`
	elseif tapped.withheld == 0 or tapped.frames == 0 then
		return false, "The tapped fight sent its moderator no withheld block or its sinks no frame"
	end

	for name: string, result: Result in { idle = idled, fight = fought, field = fielded, taps = tapped } do
		if result.digest ~= EXPECTED[name] then
			return false,
				`The {name} layout's blocks, frames and keyframes digest to {result.digest}, not {EXPECTED[name]}`
		end
	end

	return true, nil
end
