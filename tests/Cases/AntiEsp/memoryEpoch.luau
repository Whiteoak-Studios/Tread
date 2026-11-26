--[[
    Each move of the geometry epoch, an occluder added to or removed from
    the include list, the list's folder moved, occludersChanged and turning
    memory on again, drops every kept answer and box, so the next tests
    cast all their rays
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local CONSTANTS: string = "src/Constants.luau"
local RATE: number = Environment.load(EXAMPLE).shared().rates.simulation -- The example's server ticks a second
local AGAIN: number = 1 / RATE -- Seconds to a near hidden pair's recheck, at the next tick
local VISIBLE_AGAIN: number = 0.5 -- And a visible pair's, its visibleRate of 2
local SLICE: number = 60 -- Seconds a slice may take, so no pair's test runs out on a loaded machine
local SHIFT: vector = vector.create(0.5, 0, 0) -- The shifted target's step, still behind the wall
local FAR: any = roblox.Vector3.new(500, 0, 500) -- Where an added or removed occluder stands, clear of every ray
local ON: boolean = true -- Verdict memory's switch

-- What one run's two rechecks cast: engine rays, box rays and kept tests at each
type Run = {
	hiddenRays: number,
	hiddenBox: number,
	hiddenKept: number,
	allRays: number,
	allBox: number,
	allKept: number,
}

-- A part standing far off in a folder
local function far(folder: any): any
	local part: any = roblox.Instance.new("Part")
	part.CFrame = roblox.CFrame.new(FAR)
	part.Parent = folder

	return part
end

--[[
    A viewer, a target behind a Block wall that steps across before the
    first recheck, one that stays behind it and one in the open, through a
    first test and two rechecks, the trigger run before each recheck
--]]

local function run(trigger: ((harness: any, folder: any) -> ())?): Run
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp
	AntiEsp.useMemory(ON)

	local folder: any = harness.server.antiEsp.include[1]
	local wall: any = roblox.Instance.new("Part")
	wall.Size = roblox.Vector3.new(30, 12, 1)
	wall.CFrame = roblox.CFrame.new(0, 3, -15)
	wall.Parent = folder
	harness.wall = Harness.parts(folder)

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local shifted: number = harness:body("Player", vector.create(-5, 0, -30))
	local stays: number = harness:body("Player", vector.create(5, 0, -30))
	local open: number = harness:body("Player", vector.create(0, 0, 30))
	local targets: { number } = { shifted, stays, open }

	local function slice(now: number): (number, number, number)
		for _, target: number in targets do
			AntiEsp.isHidden(viewer, target)
		end

		harness:slice(now, SLICE)
		local kept: number, boxRays: number = harness:remembered()

		return #harness.rays, boxRays, kept
	end

	slice(0)
	if trigger then
		trigger(harness, folder)
	end

	harness:move(shifted, harness.states[shifted].position + SHIFT)
	local hiddenRays: number, hiddenBox: number, hiddenKept: number = slice(AGAIN)

	if trigger then
		trigger(harness, folder)
	end

	local allRays: number, allBox: number, allKept: number = slice(VISIBLE_AGAIN)

	return {
		hiddenRays = hiddenRays,
		hiddenBox = hiddenBox,
		hiddenKept = hiddenKept,
		allRays = allRays,
		allBox = allBox,
		allKept = allKept,
	}
end

return function (): (boolean, string | nil)
	local playerRays: number = Environment.load(CONSTANTS).PLAYER_RAYS

	-- With the epoch where it was, the shifted pair's box settles its rays and the still pairs keep their answers
	local control: Run = run(nil)
	if control.hiddenRays ~= 0 or control.hiddenBox ~= playerRays or control.hiddenKept ~= 1 then
		local counts: string = `{control.hiddenRays} rays, {control.hiddenBox} box rays and {control.hiddenKept} kept`
		return false, `With no trigger the hidden rechecks gave {counts}, not 0, {playerRays} and 1`
	elseif control.allRays ~= 0 or control.allBox ~= 0 or control.allKept ~= 3 then
		return false,
			`With no trigger the second rechecks gave {control.allRays} rays and {control.allKept} kept, not 0 and 3`
	end

	local triggers: { [string]: (harness: any, folder: any) -> () } = {
		["an occluder added"] = function (_: any, folder: any)
			folder.DescendantAdded:Fire(far(folder))
		end,

		["an occluder removed"] = function (_: any, folder: any)
			local gone: any = far(folder)
			folder.DescendantRemoving:Fire(gone)
			gone.Parent = nil
		end,

		-- As the engine fires it once the listed folder, or any ancestor of it, takes a new Parent
		["the include folder moved"] = function (_: any, folder: any)
			folder.AncestryChanged:Fire(folder, nil)
		end,

		["occludersChanged"] = function (harness: any, _: any)
			harness.AntiEsp.occludersChanged()
		end,

		["memory turned on again"] = function (harness: any, _: any)
			harness.AntiEsp.useMemory(ON)
		end,
	}

	-- Every hidden ray cast at the first recheck and every ray at the second, with no box and nothing kept
	for name: string, trigger: (harness: any, folder: any) -> () in triggers do
		local after: Run = run(trigger)
		if after.hiddenRays ~= 2 * playerRays or after.hiddenBox ~= 0 or after.hiddenKept ~= 0 then
			local counts: string = `{after.hiddenRays} rays, {after.hiddenBox} box rays and {after.hiddenKept} kept`
			return false, `After {name} the hidden rechecks gave {counts}, not {2 * playerRays}, 0 and 0`
		elseif after.allRays ~= 2 * playerRays + 1 or after.allBox ~= 0 or after.allKept ~= 0 then
			local counts: string = `{after.allRays} rays, {after.allBox} box rays and {after.allKept} kept`
			return false, `After {name} again the second rechecks gave {counts}, not {2 * playerRays + 1}, 0 and 0`
		end
	end

	return true, nil
end
