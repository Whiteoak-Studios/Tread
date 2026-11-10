--[[
    A sink that throws stops nothing: the viewer is still sent its blocks,
    the sinks beside it on the same viewer and on another still hear every
    frame, and it keeps being called each tick until it is disconnected
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local RUNS: number = 4

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local Taps: any = Harness.Taps

	local client: any = harness:viewer("Viewer")
	local other: any = harness:viewer("Other")
	harness:spawn("Player", vector.create(10, 0, 0))

	local throws: number = 0
	local beside: number = 0
	local elsewhere: number = 0

	local stopThrowing: () -> () = Taps.observe(client.viewer.key, function ()
		throws += 1
		error("This sink throws on purpose, to show the others still hear")
	end)
	Taps.observe(client.viewer.key, function ()
		beside += 1
	end)
	Taps.observe(other.viewer.key, function ()
		elsewhere += 1
	end)

	for run: number = 1, RUNS do
		harness:run()

		if throws ~= run or beside ~= run or elsewhere ~= run then
			return false, `After run {run} the sinks heard {throws}, {beside} and {elsewhere} frames, not {run} each`
		elseif #client.seen.sizes == 0 and run == 1 then
			return false, "The viewer was sent no block on a run whose sink threw"
		end
	end

	stopThrowing()
	harness:run()
	if throws ~= RUNS or beside ~= RUNS + 1 then
		return false, "The disconnected sink still heard, or the one beside it stopped"
	end

	return true, nil
end
