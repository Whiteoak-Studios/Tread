--[[
    Volt's traffic is read once a turn and only by a turn that needs room:
    a viewer sent a moving player reads it once a run however much it
    places, one with nothing due never does, until a player comes near it
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WARM: number = 3 -- Runs for the moving player's reveal to be acknowledged
local RUNS: number = 10
local CLOSE: number = 10 -- Studs from its viewer the moving player stands, inside the near tier
local WALK: number = 0.8 -- Studs it moves a run, so its record changes every run
local AWAY: vector = vector.create(4000, 0, 0) -- Past relevancy.leave from everything else

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()

	-- Every read of the harness's traffic counted, which the relay's traffic function makes once a call
	local reads: number = 0
	rawset(harness, "traffic", nil)
	setmetatable(harness, {
		__index = function (_: any, key: string): any
			if key == "traffic" then
				reads += 1

				return 0
			end

			return Harness[key]
		end,
	})

	local busy: any = harness:viewer("Busy")
	busy.viewer.slot = harness:spawn("Player", vector.zero)

	local idle: any = harness:viewer("Idle")
	idle.viewer.position = AWAY

	local walker: number = harness:spawn("Player", vector.create(CLOSE, 0, 0))

	harness:runs(WARM)
	if not busy.drawn[walker] then
		return false, "The busy viewer was never sent the moving player"
	end

	reads = 0
	for run: number = 1, RUNS do
		harness.states[walker].position = vector.create(CLOSE, 0, run * WALK)
		harness:run()
	end

	if reads ~= RUNS then
		return false, `{RUNS} runs with one viewer due read Volt's traffic {reads} times, not once a run`
	end

	-- A player beside the idle viewer leaves the busy one's relevancy, so both have something due
	reads = 0
	harness.states[walker].position = AWAY + vector.create(CLOSE, 0, 0)
	harness:run()

	if reads ~= #harness.viewers then
		return false,
			`A run with a hide due to one viewer and a reveal to the other read Volt's traffic {reads} times, not once each`
	elseif not idle.drawn[walker] then
		return false, "The idle viewer was not sent the player that came near it"
	end

	return true, nil
end
