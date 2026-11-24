--[[
    A test a kept answer settles casts nothing, so it stays out of the
    slice's mean: after a run of them, the one test that cast sets the mean,
    and a second like it, which would end past the budget, waits
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local CONSTANTS: string = "src/Constants.luau"
local AGAIN: number = 1 / 30 -- Seconds to a near hidden pair's recheck, the example's nearRate of 30
local SLICE: number = 60 -- Seconds the first slice may take, so none of its tests runs out on a loaded machine

-- Seconds of os.clock each slow ray takes, every one of a test's rays blocked: long enough that the budget, ROOM slow
-- tests of it, outlasts a stall on a loaded machine before the first of them starts
local SPIN: number = 0.05
local ROOM: number = 1.5 -- Slow tests the budget holds: one ends inside it, and a second would end past it
local KEPT: number = 20 -- Still targets a kept answer settles, each nearer than the two that step
local SPACING: number = 2 -- Studs between the still targets along X
local NEAREST: number = 5 -- Studs from the viewer to the first of them
local STEPPERS: { vector } = { vector.create(0, 0, -100), vector.create(0, 0, -110) } -- Nearer first
local STEP: vector = vector.create(0.5, 0, 0) -- Each stepper's move, so its rays are aimed and cast anew
local ON: boolean = true -- Verdict memory's switch

return function (): (boolean, string | nil)
	local playerRays: number = Environment.load(CONSTANTS).PLAYER_RAYS
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp
	AntiEsp.useMemory(ON)
	harness.wall = Harness.solid

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local targets: { number } = {}
	for index: number = 1, KEPT do
		table.insert(targets, harness:body("Player", vector.create(NEAREST + (index - 1) * SPACING, 0, 0)))
	end

	local steppers: { number } = {}
	for _, at: vector in STEPPERS do
		local slot: number = harness:body("Player", at)
		table.insert(targets, slot)
		table.insert(steppers, slot)
	end

	local function ask()
		for _, target: number in targets do
			AntiEsp.isHidden(viewer, target)
		end
	end

	-- 1) Every pair tested, hidden, and its answer kept
	ask()
	harness:slice(0, SLICE)
	harness:remembered()

	-- 2) The steppers move, every ray turns slow, and the slice has room for one slow test but not two
	for _, slot: number in steppers do
		harness:move(slot, harness.states[slot].position + STEP)
	end

	harness.wall = function (_: vector, _: vector): boolean
		local began: number = os.clock()
		while os.clock() < began + SPIN do
			continue
		end

		return true
	end

	local budget: number = ROOM * playerRays * SPIN
	ask()
	harness:slice(AGAIN, budget)
	local kept: number = harness:remembered()

	if kept ~= KEPT then
		return false, `The slice settled {kept} still pairs by their kept answers, not all {KEPT}`
	elseif #harness.rays ~= playerRays then
		local tests: string = `{#harness.rays} rays, not the nearer stepper's {playerRays}`
		return false, `After {KEPT} kept answers the slice cast {tests}, so the kept ones set its mean`
	end

	return true, nil
end
