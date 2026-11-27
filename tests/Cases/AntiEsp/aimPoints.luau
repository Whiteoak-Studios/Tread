--[[
    AntiEsp.aimPoints writes the ends a still target's test casts at and
    gives their count, the same ends with no look-ahead for a moving target
    and viewer, and only as many as a shorter posture list holds
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local TOLERANCE: number = 1e-6 -- Studs an end may sit from where it should
local CROUCHED: number = 4 -- The crouched points the cut list keeps

-- Why two lists of ends differ, or nil when they hold the same count of the same ends
local function differ(got: { vector }, count: number, wanted: { vector }): string?
	if count ~= #wanted then
		return `it gave {count} ends, not {#wanted}`
	end

	for index: number = 1, count do
		if vector.magnitude(got[index] - wanted[index]) > TOLERANCE then
			return `its end {index} was {got[index]}, not {wanted[index]}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(function (_: any, server: any)
		local points: { any } = server.antiEsp.aim.Crouch
		for index: number = #points, CROUCHED + 1, -1 do
			points[index] = nil
		end
	end)
	harness.wall = Harness.solid
	local AntiEsp: any = Harness.AntiEsp

	local slot: number, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(12, 0, -40))
	local own: any = harness.states[slot]
	local state: any = harness.states[target]

	AntiEsp.isHidden(viewer, target)
	harness:slice(0)

	local cast: { vector } = {}
	for index: number, ray: any in harness.rays do
		cast[index] = ray.to
	end

	-- The ends the still target's test cast at, from the same eye
	local eye: vector = Harness.Eye.clear(own, harness.world)
	local still: { vector } = {}
	local problem: string? = differ(still, AntiEsp.aimPoints(eye, state, still), cast)
	if problem then
		return false, `For a still target aimPoints wrote other ends than its test cast: {problem}`
	end

	-- Moving, each body, with no push or lead from the look-ahead
	own.velocity = vector.create(0, 0, -5)
	state.velocity = vector.create(6, 0, 8)
	local moving: { vector } = {}
	problem = differ(moving, AntiEsp.aimPoints(eye, state, moving), still)
	if problem then
		return false, `For a moving target aimPoints moved its ends with the look-ahead: {problem}`
	end

	-- Crouched, as many as the cut list holds, the same ends the test casts at
	state.velocity = vector.zero
	state.posture = "Crouch"
	AntiEsp.isHidden(viewer, target)
	AntiEsp.moved(target)
	harness:slice(0.001)

	local crouchCast: { vector } = {}
	for index: number, ray: any in harness.rays do
		crouchCast[index] = ray.to
	end

	local crouched: { vector } = {}
	problem = differ(crouched, AntiEsp.aimPoints(eye, state, crouched), crouchCast)
	if problem then
		return false, `For a crouched target with {CROUCHED} points aimPoints went another way: {problem}`
	elseif #crouchCast ~= CROUCHED then
		return false, `The crouched target's test cast {#crouchCast} rays, not the cut list's {CROUCHED}`
	end

	return true, nil
end
