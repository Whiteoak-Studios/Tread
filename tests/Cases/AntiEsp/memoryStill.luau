--[[
    With verdict memory on, a still pair's recheck casts nothing and keeps
    its verdict, visible or hidden, where off it casts again; and nothing is
    kept past a new life, a change of kind or a reused pair index
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local VISIBLE_AGAIN: number = 0.5 -- Seconds to a visible pair's recheck, the example's visibleRate of 2
local RATE: number = Environment.load(EXAMPLE).shared().rates.simulation -- The example's server ticks a second
local HIDDEN_AGAIN: number = 1 / RATE -- And a near hidden pair's, at the next tick
local NEXT: number = 1 / 60 -- Seconds to a slice after a change that makes the pair due at once
local SLICE: number = 60 -- Seconds a slice and its lying share may take, so no test runs out on a loaded machine
local ON: boolean = true -- Verdict memory's switch
local OFF: boolean = false

-- One harness with a viewer and two still targets, one behind a wall that blocks every ray to it, and memory set
local function scene(remember: boolean): (any, any, number, number)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.lyingShare = SLICE
	end)
	Harness.AntiEsp.useMemory(remember)

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local seen: number = harness:body("Player", vector.create(20, 0, 0))
	local walled: number = harness:body("Player", vector.create(-20, 0, 0))

	harness.wall = function (origin: vector, direction: vector): boolean
		return (origin + direction).x < 0
	end

	return harness, viewer, seen, walled
end

-- Both pairs asked, then a slice at a time, giving the rays it cast and each pair's reason after it
local function slice(harness: any, viewer: any, seen: number, walled: number, now: number): (number, string, string)
	local AntiEsp: any = harness.AntiEsp
	AntiEsp.isHidden(viewer, seen)
	AntiEsp.isHidden(viewer, walled)
	harness:slice(now, SLICE)

	return #harness.rays, AntiEsp.reason(viewer.key, seen), AntiEsp.reason(viewer.key, walled)
end

return function (): (boolean, string | nil)
	local remembering: any, viewer: any, seen: number, walled: number = scene(ON)
	local AntiEsp: any = remembering.AntiEsp

	local rays: number, seenReason: string, walledReason: string = slice(remembering, viewer, seen, walled, 0)
	if rays == 0 or seenReason ~= "Clear" or walledReason ~= "Hidden" then
		return false, `The first slice cast {rays} rays, with the pairs {seenReason} and {walledReason}`
	end

	local tests: number = AntiEsp.counts()
	remembering:remembered()

	-- The hidden pair's recheck: kept, so no ray, and the visible pair isn't due yet
	rays, seenReason, walledReason = slice(remembering, viewer, seen, walled, HIDDEN_AGAIN)
	local kept: number, boxRays: number = remembering:remembered()
	if rays ~= 0 or walledReason ~= "Hidden" or AntiEsp.counts() ~= tests + 1 then
		return false, `The hidden pair's second test cast {rays} rays and left it {walledReason}`
	elseif kept ~= 1 or boxRays ~= 0 then
		return false,
			`memory gave {kept} kept tests and {boxRays} box rays after the hidden pair's second test, not 1 and 0`
	end

	-- Both rechecks due together, both kept
	rays, seenReason, walledReason = slice(remembering, viewer, seen, walled, VISIBLE_AGAIN)
	kept = remembering:remembered()
	if rays ~= 0 or seenReason ~= "Clear" or walledReason ~= "Hidden" or AntiEsp.counts() ~= tests + 3 then
		return false, `The visible pair's second test cast {rays} rays, with the pairs {seenReason} and {walledReason}`
	elseif kept ~= 2 or AntiEsp.rays() == 0 then
		return false, `memory gave {kept} kept tests for both rechecks, not 2`
	end

	-- With memory off, the same slices cast every recheck's rays again
	local forgetting: any, other: any, otherSeen: number, otherWalled: number = scene(OFF)
	slice(forgetting, other, otherSeen, otherWalled, 0)
	local again: number = slice(forgetting, other, otherSeen, otherWalled, HIDDEN_AGAIN)
	local both: number = slice(forgetting, other, otherSeen, otherWalled, VISIBLE_AGAIN)

	if again == 0 or both == 0 or forgetting:remembered() ~= 0 then
		return false, `With memory off the rechecks cast {again} and {both} rays`
	end

	-- A new life, a sleep and a wake, and the viewer leaving and asking again each leave nothing kept to settle with
	local Slots: any = remembering.Slots
	local changes: { [string]: (at: number) -> () } = {
		["a new life"] = function (_: number)
			remembering:reborn(walled)
		end,

		-- Tested once as a sleeper between the two
		["a sleep and a wake"] = function (at: number)
			Slots.setEntry(walled, { kind = "Sleeper", rig = "A" })
			slice(remembering, viewer, seen, walled, at)
			Slots.setEntry(walled, { kind = "Player", rig = "A" })
		end,

		["the viewer leaving"] = function (_: number)
			AntiEsp.leave(viewer.key)
		end,
	}

	local now: number = VISIBLE_AGAIN
	for name: string, change: (at: number) -> () in changes do
		-- Kept first, so the change is all that drops it
		now += VISIBLE_AGAIN
		slice(remembering, viewer, seen, walled, now)
		if remembering:remembered() == 0 then
			return false, `Before {name} the pairs kept nothing`
		end

		now += NEXT
		change(now)
		now += NEXT
		rays = slice(remembering, viewer, seen, walled, now)
		kept = remembering:remembered()

		if rays == 0 or kept ~= 0 then
			return false, `After {name} the walled pair's test cast {rays} rays and kept {kept}`
		end
	end

	return true, nil
end
