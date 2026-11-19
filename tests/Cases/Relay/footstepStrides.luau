--[[
    A culled enemy walking or sprinting inside earshot reaches the viewer as
    footstep entries in its record's place: one each time it covers its
    gait's stride, each at the exact place the stride ended, with its kind
    and ground material
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local GRASS: any = roblox.Enum.Material.Grass -- The ground the harness stands every body on
local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local QUANTUM: number = 1 / 64
local START: number = 10
local WALK_TICK: number = 0.5 -- The example's 10 studs/s walk at a 20 Hz relay
local SPRINT_TICK: number = 0.9 -- And its 18 studs/s sprint
local WALK_STRIDE: number = 4.5
local SPRINT_STRIDE: number = 6
local TICKS: number = 30

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", vector.create(START, 0, 0))

	harness:hide(client, slot, true)
	harness:run()

	local steps: { any } = {}
	local x: number = START

	for _ = 1, TICKS do
		x += WALK_TICK
		harness.states[slot].position = vector.create(x, 0, 0)
		harness:run()

		if Harness.count(client.seen.records, slot) + Harness.count(client.seen.reveals, slot) ~= 0 then
			return false, "The culled enemy was sent its record"
		end

		table.move(client.seen.footsteps, 1, #client.seen.footsteps, #steps + 1, steps)
	end

	local walked: number = x - START
	if #steps ~= walked // WALK_STRIDE then
		return false, `Walking {walked} studs gave {#steps} footstep entries, one a {WALK_STRIDE}-stud stride`
	end

	for index: number, step: any in steps do
		local at: vector = vector.create(START + WALK_STRIDE * index, 0, 0)

		if vector.magnitude(step.at - at) > QUANTUM then
			return false, `Footstep {index} fell at {step.at}, not where its stride ended, {at}`
		elseif step.kind ~= "Walk" or step.material ~= GRASS then
			return false, `Footstep {index} is a {step.kind} on {step.material}, not a walk on grass`
		end
	end

	-- Sprinting, the stride is the sprint's and the steps keep falling where each one ends
	local state: any = harness.states[slot]
	local covered: number = walked % WALK_STRIDE
	local from: number = x
	state.sprint = true
	steps = {}

	for _ = 1, TICKS do
		x += SPRINT_TICK
		state.position = vector.create(x, 0, 0)
		harness:run()
		table.move(client.seen.footsteps, 1, #client.seen.footsteps, #steps + 1, steps)
	end

	local sprinted: number = x - from
	if #steps ~= (covered + sprinted) // SPRINT_STRIDE then
		return false, `Sprinting {sprinted} studs gave {#steps} footstep entries, one a {SPRINT_STRIDE}-stud stride`
	end

	for index: number, step: any in steps do
		local at: vector = vector.create(from - covered + SPRINT_STRIDE * index, 0, 0)

		if vector.magnitude(step.at - at) > QUANTUM or step.kind ~= "Sprint" then
			return false, `Sprint step {index} is a {step.kind} at {step.at}, not a sprint at {at}`
		end
	end

	return true, nil
end
