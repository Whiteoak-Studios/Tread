--[[
    AntiEsp.memory gives totals since start that no read takes from: 0 while
    memory is off, a kept test and box rays only while it is on, the same
    from two reads in a row, and held where they stood once it is off again
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local CONSTANTS: string = "src/Constants.luau"
local RATE: number = Environment.load(EXAMPLE).shared().rates.simulation -- The example's server ticks a second
local AGAIN: number = 1 / RATE -- Seconds to a near hidden pair's recheck, at the next tick
local SLICE: number = 60 -- Seconds a slice may take, so no recheck's test runs out on a loaded machine
local RECHECKS: number = 3 -- Rechecks run in each stretch with memory off
local WALL_SIZE: any = roblox.Vector3.new(12, 12, 1)
local WALL_AT: any = roblox.Vector3.new(0, 3, -15) -- Between the viewer's eye and every point it aims at
local TARGET: vector = vector.create(0, 0, -30)
local SHIFTED: vector = vector.create(0.5, 0, -30) -- Still behind the wall, so its rays are aimed anew
local ON: boolean = true -- Verdict memory's switch
local OFF: boolean = false

return function (): (boolean, string | nil)
	local playerRays: number = Environment.load(CONSTANTS).PLAYER_RAYS
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp

	local folder: any = harness.server.antiEsp.include[1]
	local wall: any = roblox.Instance.new("Part")
	wall.Size = WALL_SIZE
	wall.CFrame = roblox.CFrame.new(WALL_AT)
	wall.Parent = folder
	harness.wall = Harness.parts(folder)

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", TARGET)

	-- The pair asked and tested at its next near recheck
	local now: number = 0
	local function recheck()
		AntiEsp.isHidden(viewer, target)
		harness:slice(now, SLICE)
		now += AGAIN
	end

	-- 1) Off: a still pair's rechecks keep nothing
	for _ = 1, RECHECKS do
		recheck()
	end

	local kept: number, boxRays: number = AntiEsp.memory()
	if kept ~= 0 or boxRays ~= 0 then
		return false, `With memory off the counts were {kept} kept tests and {boxRays} box rays, not 0 and 0`
	end

	-- 2) On: the first test casts and keeps its answer and the wall's box, and the still recheck after it is kept
	AntiEsp.useMemory(ON)
	recheck()
	recheck()

	kept, boxRays = AntiEsp.memory()
	if kept ~= 1 or boxRays ~= 0 then
		return false, `After a still recheck with memory on the counts were {kept} and {boxRays}, not 1 and 0`
	end

	local keptAgain: number, boxAgain: number = AntiEsp.memory()
	if keptAgain ~= kept or boxAgain ~= boxRays then
		return false, `A second read in a row gave {keptAgain} and {boxAgain}, not the first's {kept} and {boxRays}`
	end

	-- 3) The target steps, still behind the wall, so the kept box blocks every ray with no engine ray
	harness:move(target, SHIFTED)
	recheck()

	kept, boxRays = AntiEsp.memory()
	if kept ~= 1 or boxRays ~= playerRays then
		return false, `Once the target stepped the counts were {kept} and {boxRays}, not 1 and {playerRays}`
	end

	-- 4) Off again: the stepped-back target's rechecks leave the totals where they stood
	AntiEsp.useMemory(OFF)
	harness:move(target, TARGET)

	for _ = 1, RECHECKS do
		recheck()
	end

	local keptAfter: number, boxAfter: number = AntiEsp.memory()
	if keptAfter ~= kept or boxAfter ~= boxRays then
		return false, `With memory off again the counts moved to {keptAfter} and {boxAfter} from {kept} and {boxRays}`
	end

	return true, nil
end
