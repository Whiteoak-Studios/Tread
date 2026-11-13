--[[
    The calibration takes the bot harness's settings and refuses any of its
    counts at 0 or a fraction, each by name, and its line reads a stand-in
    timing's p50 and p95 by nearest rank with the samples and Heartbeats
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local COUNTS: { string } = { "samples", "perFrame", "bytes", "passes", "casts" }
local FRACTION: number = 2.5

-- Microseconds an operation, out of order so the line sorts them
local STAND_IN: { [string]: any } = {
	loop = { 21.5, 20.25, 22.75, 20.5, 35.125 },
	casts = { 2.5, 3.25, 2.75, 2.0, 2.25 },
	bytes = 1024,
	frames = 50,
	seconds = 0.8,
}

local LINE: string = table.concat({
	"native loop µs a pass of 1024 B p50/p95 21.500/35.125",
	"Blockcast µs a cast p50/p95 2.500/3.250",
	"5 samples each over 0.800 s at 62.50 Heartbeats a second",
}, "; ")

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local Calibration: any = loaded.require(server.Calibration)
	local settings: { [string]: any } = loaded.require(server.Bots.Config).calibration

	-- 1) The harness's own settings pass
	local taken: boolean, refusal: any = pcall(Calibration.check, settings)
	if not taken then
		return false, `The bot harness's calibration settings were refused: {refusal}`
	end

	-- 2) Each count at 0 or a fraction is refused, naming it
	for _, key: string in COUNTS do
		for _, bad: number in { 0, FRACTION } do
			local changed: { [string]: any } = table.clone(settings)
			changed[key] = bad

			local passed: boolean, failure: any = pcall(Calibration.check, changed)
			if passed then
				return false, `A calibration {key} of {bad} was taken`
			elseif not string.find(tostring(failure), key, 1, true) then
				return false, `A calibration {key} of {bad} was refused without its name: {failure}`
			end
		end
	end

	-- 3) The line from a stand-in timing
	local line: string = Calibration.line(STAND_IN)
	if line ~= LINE then
		return false, `The calibration's line read:\n{line}`
	end

	return true, nil
end
