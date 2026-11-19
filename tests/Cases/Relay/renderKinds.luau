--[[
    A viewer's render distance caps every kind it is sent: at 400 studs an
    NPC, a sleeper and a body at 350 are sent and each at 450 is not, though
    npcs.range and sleepers.radius reach farther, as a viewer that sent no
    distance shows by being sent all six
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local DISTANCE: number = 400
local INSIDE: number = 350
local OUTSIDE: number = 450 -- Inside the example's 800-stud npcs.range and 500-stud sleepers.radius
local RUNS: number = 3 -- Relay ticks, each enough for a reveal to arrive

local KINDS: { string } = { "Npc", "Sleeper", "Body" }
local AXES: { vector } = { vector.create(1, 0, 0), vector.create(0, 0, 1), vector.create(-1, 0, 0) } -- One a kind

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local short: any = harness:viewer("Short")
	local whole: any = harness:viewer("Whole")

	-- Each kind along its own axis, near and far
	local near: { [string]: number } = {}
	local far: { [string]: number } = {}
	for index: number, kind: string in KINDS do
		near[kind] = harness:spawn(kind, AXES[index] * INSIDE)
		far[kind] = harness:spawn(kind, AXES[index] * OUTSIDE)
	end

	Harness.Relay.setDistance(short.viewer.key, DISTANCE)
	harness:runs(RUNS)

	for _, kind: string in KINDS do
		if not short.drawn[near[kind]] then
			return false, `The viewer at {DISTANCE} studs was not sent the {kind} at {INSIDE}`
		elseif short.drawn[far[kind]] then
			return false, `The viewer at {DISTANCE} studs was sent the {kind} at {OUTSIDE}`
		elseif not whole.drawn[near[kind]] or not whole.drawn[far[kind]] then
			return false, `The viewer that sent no distance was not sent both of the {kind}s`
		end
	end

	return true, nil
end
