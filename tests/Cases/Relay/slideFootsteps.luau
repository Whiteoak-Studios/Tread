--[[
    A culled enemy's crouch slide reaches the viewer as Sprint footstep
    entries at the sprint's stride, heard to the sprint's range past the
    walk's, where a crouched walk over the same ground is silent
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local QUANTUM: number = 1 / 64
local START: number = 50 -- Studs from the viewer, inside the sprint's 60 and past the walk's 40
local SLIDE_TICK: number = 0.75 -- A 15 studs/s slide at a 20 Hz relay
local SPRINT_STRIDE: number = 6
local TICKS: number = 12 -- 9 studs, one stride and a half, all inside the sprint's range

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")

	-- A crouched walk first, which steps silently
	local slot: number = harness:spawn("Player", vector.create(START, 0, 0))
	local state: any = harness.states[slot]
	state.posture = "Crouch"

	harness:hide(client, slot, true)
	harness:run()

	local x: number = START
	for _ = 1, TICKS do
		x += SLIDE_TICK
		state.position = vector.create(x, 0, 0)
		harness:run()

		if #client.seen.footsteps ~= 0 then
			return false, "A culled enemy's crouched walk made a footstep entry"
		end
	end

	-- Sliding over the same stretch back toward the viewer, with sprint never set
	state.mode = "Slide"
	harness:run()

	local from: number = x
	local steps: { any } = {}
	for _ = 1, TICKS do
		x -= SLIDE_TICK
		state.position = vector.create(x, 0, 0)
		harness:run()

		if Harness.count(client.seen.records, slot) + Harness.count(client.seen.reveals, slot) ~= 0 then
			return false, "The culled sliding enemy was sent its record"
		end

		table.move(client.seen.footsteps, 1, #client.seen.footsteps, #steps + 1, steps)
	end

	local slid: number = from - x
	if #steps ~= slid // SPRINT_STRIDE then
		return false, `Sliding {slid} studs gave {#steps} footstep entries, not one a {SPRINT_STRIDE}-stud stride`
	end

	for index: number, step: any in steps do
		local at: vector = vector.create(from - SPRINT_STRIDE * index, 0, 0)

		if vector.magnitude(step.at - at) > QUANTUM or step.kind ~= "Sprint" then
			return false, `Slide step {index} is a {step.kind} at {step.at}, not a sprint at {at}`
		end
	end

	return true, nil
end
