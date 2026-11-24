--[[
    A still target with a velocity never keeps; at zero velocity its rays
    read no look-ahead, so a viewer whose look-ahead changes keeps while its
    eye and drift hold bit for bit, a moving viewer's too, and not after
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local AGAIN: number = 1 / 30 -- Seconds to a near hidden pair's recheck, the example's nearRate of 30
local SLICE: number = 60 -- Seconds a slice may take, so no recheck's test runs out on a loaded machine
local RECHECKS: number = 4
local PUSH: vector = vector.create(0, 0, -3) -- A target pressed into a wall, its velocity set while it stays put
local STRIDE: vector = vector.create(2, 0, 0) -- A viewer's velocity, which its drift reads
local ON: boolean = true -- Verdict memory's switch
local OFF: boolean = false

-- A harness with memory set, a viewer at the origin and a target 30 studs off behind a wall that blocks every ray
local function scene(remember: boolean): (any, any, number)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	Harness.AntiEsp.useMemory(remember)
	harness.wall = Harness.solid

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -30))

	return harness, viewer, target
end

-- One recheck: the pair asked and a slice, giving the rays it cast and its kept tests
local function recheck(harness: any, viewer: any, target: number, now: number): (number, number)
	harness.AntiEsp.isHidden(viewer, target)
	harness:slice(now, SLICE)

	local kept: number = harness:remembered()

	return #harness.rays, kept
end

-- Every logged ray's origin and end the same, bit for bit
local function sameRays(rays: { any }, others: { any }): boolean
	if #rays ~= #others then
		return false
	end

	for index: number, ray: any in rays do
		local other: any = others[index]
		if ray.origin ~= other.origin or ray.to ~= other.to or 1 / ray.to ~= 1 / other.to then
			return false
		end
	end

	return true
end

return function (): (boolean, string | nil)
	-- 1) A target that stays put with a velocity is aimed afresh at every recheck, its ends led by that velocity
	local harness: any, viewer: any, target: number = scene(ON)
	harness.states[target].velocity = PUSH
	recheck(harness, viewer, target, 0)

	for index: number = 1, RECHECKS do
		local rays: number, kept: number = recheck(harness, viewer, target, index * AGAIN)
		if rays == 0 or kept ~= 0 then
			return false, `Recheck {index} of a still target with a velocity cast {rays} rays and kept {kept}`
		end
	end

	-- 2) With its velocity at zero the target's rays are the same bits at either look-ahead, which a velocity changes
	local forgetting: any, other: any, still: number = scene(OFF)
	forgetting.AntiEsp.isHidden(other, still)
	forgetting:slice(0, SLICE)
	local before: { any } = table.clone(forgetting.rays)

	forgetting.Connections.remove(other.key)
	forgetting.AntiEsp.isHidden(other, still)
	forgetting:slice(AGAIN, SLICE)
	if not sameRays(before, forgetting.rays) then
		return false, "With the target's velocity at zero, the look-ahead the viewer lost changed its rays"
	end

	forgetting.states[still].velocity = PUSH
	forgetting.Connections.add(other.key)
	forgetting.AntiEsp.isHidden(other, still)
	forgetting:slice(2 * AGAIN, SLICE)
	local led: { any } = table.clone(forgetting.rays)

	forgetting.Connections.remove(other.key)
	forgetting.AntiEsp.isHidden(other, still)
	forgetting:slice(3 * AGAIN, SLICE)
	if sameRays(led, forgetting.rays) then
		return false, "With the target moving, the look-ahead the viewer lost left its rays as they were"
	end

	-- 3) A still viewer whose look-ahead changes keeps, its drift zero at either
	harness, viewer, target = scene(ON)
	recheck(harness, viewer, target, 0)
	harness.Connections.remove(viewer.key)

	local rays: number, kept: number = recheck(harness, viewer, target, AGAIN)
	if rays ~= 0 or kept ~= 1 then
		return false, `A still viewer that lost its look-ahead cast {rays} rays and kept {kept}`
	end

	-- 4) A viewer with a velocity keeps while its eye and drift hold, and not once its look-ahead moves its drift
	harness.states[viewer.slot].velocity = STRIDE
	recheck(harness, viewer, target, 2 * AGAIN)

	rays, kept = recheck(harness, viewer, target, 3 * AGAIN)
	if rays ~= 0 or kept ~= 1 then
		return false, `A moving viewer whose eye and drift held cast {rays} rays and kept {kept}`
	end

	harness.Connections.add(viewer.key)
	rays, kept = recheck(harness, viewer, target, 4 * AGAIN)
	if rays == 0 or kept ~= 0 then
		return false, `A moving viewer whose look-ahead moved its drift cast {rays} rays and kept {kept}`
	end

	return true, nil
end
