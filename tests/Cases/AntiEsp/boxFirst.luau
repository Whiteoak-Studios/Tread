--[[
    With verdict memory on, a pair hidden behind one Block part keeps that
    part's box, square or turned, asked of its first ray alone, so its next
    test after its target moved behind it casts no engine ray; off, no ray
    asks the occluder what it met
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local CONSTANTS: string = "src/Constants.luau"
local RATE: number = Environment.load(EXAMPLE).shared().rates.simulation -- The example's server ticks a second
local AGAIN: number = 1 / RATE -- Seconds to a near hidden pair's recheck, at the next tick
local SLICE: number = 60 -- Seconds a slice may take, so neither test runs out on a loaded machine
local WALL_SIZE: any = roblox.Vector3.new(12, 12, 1)
local WALL_AT: any = roblox.Vector3.new(0, 3, -15) -- Between the viewer's eye and every point it aims at
local TARGET: vector = vector.create(0, 0, -30)
local SHIFTED: vector = vector.create(0.5, 0, -30) -- Still behind the wall, so its rays are aimed anew
local ON: boolean = true -- Verdict memory's switch
local OFF: boolean = false

--[[
    The pair's rays at its first test and at a recheck, the recheck's box
    rays, the occluder's calls at each test, and its reason, behind a wall
    of one turn
--]]

local function behind(turn: any, remember: boolean): (number, number, number, number, number, string)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp
	AntiEsp.useMemory(remember)

	local folder: any = harness.server.antiEsp.include[1]
	local wall: any = roblox.Instance.new("Part")
	wall.Size = WALL_SIZE
	wall.CFrame = roblox.CFrame.new(WALL_AT) * turn
	wall.Parent = folder
	harness.wall = Harness.parts(folder)

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", TARGET)

	AntiEsp.isHidden(viewer, target)
	harness:slice(0, SLICE)
	local first: number = #harness.rays
	local firstAsked: number = harness.occluded
	harness:remembered()

	harness:move(target, SHIFTED)
	AntiEsp.isHidden(viewer, target)
	harness:slice(AGAIN, SLICE)
	local _, boxRays: number = harness:remembered()
	local againAsked: number = harness.occluded - firstAsked

	return first, #harness.rays, boxRays, firstAsked, againAsked, AntiEsp.reason(viewer.key, target)
end

return function (): (boolean, string | nil)
	local playerRays: number = Environment.load(CONSTANTS).PLAYER_RAYS
	local turns: { [string]: any } = {
		square = roblox.CFrame.new(),
		turned = roblox.CFrame.Angles(math.rad(15), math.rad(25), math.rad(10)),
	}

	for name: string, turn: any in turns do
		local first: number, second: number, boxRays: number, asked: number, again: number, reason: string =
			behind(turn, ON)
		if first ~= playerRays then
			return false, `Behind the {name} wall the first test cast {first} rays, not every one of its {playerRays}`
		elseif second ~= 0 or boxRays ~= playerRays or reason ~= "Hidden" then
			return false, `Behind the {name} wall the second test cast {second} rays with {boxRays} box rays, {reason}`
		elseif asked ~= 1 or again ~= 0 then
			return false, `Behind the {name} wall the occluder was asked {asked} times and then {again}, not 1 and 0`
		end

		-- Off, the same recheck casts every ray on the engine again, and none asks what it met
		local _, recast: number, offBox: number, offAsked: number, offAgain: number = behind(turn, OFF)
		if recast ~= playerRays or offBox ~= 0 then
			return false, `With memory off the {name} wall's recheck cast {recast} rays and {offBox} box rays`
		elseif offAsked ~= 0 or offAgain ~= 0 then
			return false, `With memory off the {name} wall's tests asked the occluder {offAsked} and {offAgain} times`
		end
	end

	return true, nil
end
