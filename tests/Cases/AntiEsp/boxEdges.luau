--[[
    A kept box settles only a finite ray 1/64 stud inside it from outside: a
    grazing ray, an eye inside it, a part under two insets thick and a NaN or
    infinite end go to the engine, and no ball, wedge, mesh or terrain is kept
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local CONSTANTS: string = "src/Constants.luau"
local CASTS: string = "src/Server/AntiEspWorkers/Casts.luau"
local SLICE: number = 60 -- Seconds a slice may take, so no test of a scene's runs out on a loaded machine
local NAN: number = 0 / 0 -- A coordinate no comparison holds for
local AGAIN: number = 1 / 30 -- Seconds to a near hidden pair's recheck, the example's nearRate of 30
local GRAZE: number = 1 / 200 -- Studs under the wall's top the head ray runs, inside the 1/64-stud inset
local HEAD: number = 5 -- The example's standing head-top point, studs above the feet
local WALL_Z: number = -15 -- Where each wall stands between the viewer at the origin and the target
local TARGET_Z: number = -30
local SHIFT: number = 0.5 -- Studs the target steps across, still behind the wall, so its rays are aimed anew
local THIN: number = 1 / 50 -- A wall's thickness under two insets, which no box ray crosses
local ON: boolean = true -- Verdict memory's switch

-- One harness with memory on, a viewer at the origin and a target behind where walls go
local function scene(): (any, any, number, any)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	Harness.AntiEsp.useMemory(ON)

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, TARGET_Z))

	return harness, viewer, target, Harness
end

-- A Block part standing in the harness's include folder, its rays met as the engine meets them
local function wall(harness: any, Harness: any, size: any, center: any): any
	local folder: any = harness.server.antiEsp.include[1]
	local part: any = roblox.Instance.new("Part")
	part.Size = size
	part.CFrame = roblox.CFrame.new(center)
	part.Parent = folder
	harness.wall = Harness.parts(folder)

	return part
end

-- The first test's rays, then the engine rays, box rays and reason of a recheck after the target steps across
local function recheck(harness: any, viewer: any, target: number): (number, number, number, string)
	local AntiEsp: any = harness.AntiEsp

	AntiEsp.isHidden(viewer, target)
	harness:slice(0, SLICE)
	local first: number = #harness.rays
	harness:remembered()

	local at: vector = harness.states[target].position
	harness:move(target, at + vector.create(SHIFT, 0, 0))
	AntiEsp.isHidden(viewer, target)
	harness:slice(AGAIN, SLICE)
	local _, boxRays: number = harness:remembered()

	return first, #harness.rays, boxRays, AntiEsp.reason(viewer.key, target)
end

return function (): (boolean, string | nil)
	local playerRays: number = Environment.load(CONSTANTS).PLAYER_RAYS

	-- 1) The head ray runs level, GRAZE under the wall's top, so only it goes to the engine
	local harness: any, viewer: any, target: number, Harness: any = scene()
	local eye: vector = Harness.Eye.clear(harness.states[viewer.slot], harness.world)
	harness:move(target, vector.create(0, eye.y - HEAD, TARGET_Z))

	local top: number = eye.y + GRAZE
	wall(harness, Harness, roblox.Vector3.new(12, 10, 1), roblox.Vector3.new(0, top - 5, WALL_Z))

	local first: number, second: number, boxRays: number, reason: string = recheck(harness, viewer, target)
	if first ~= playerRays then
		return false, `Under the grazed wall the first test cast {first} rays, not {playerRays}`
	elseif second ~= 1 or boxRays ~= playerRays - 1 or reason ~= "Hidden" then
		return false, `The grazing head ray's recheck cast {second} engine rays and {boxRays} box rays, {reason}`
	end

	-- 2) An eye that steps inside the kept box casts every ray on the engine, which passes through what it starts in
	harness, viewer, target, Harness = scene()
	wall(harness, Harness, roblox.Vector3.new(12, 12, 4), roblox.Vector3.new(0, 3, WALL_Z))
	harness.AntiEsp.isHidden(viewer, target)
	harness:slice(0, SLICE)
	harness:remembered()

	harness:move(viewer.slot, vector.create(0, 0, WALL_Z), viewer)
	harness.AntiEsp.moved(viewer.slot)
	harness.AntiEsp.isHidden(viewer, target)
	harness:slice(AGAIN, SLICE)
	local _, inside: number = harness:remembered()
	reason = harness.AntiEsp.reason(viewer.key, target)

	if #harness.rays == 0 or inside ~= 0 or reason ~= "Clear" then
		return false,
			`From inside the kept box {#harness.rays} engine rays and {inside} box rays left the pair {reason}`
	end

	-- 3) A wall thinner than two insets is kept, and settles no ray
	harness, viewer, target, Harness = scene()
	wall(harness, Harness, roblox.Vector3.new(12, 12, THIN), roblox.Vector3.new(0, 3, WALL_Z))
	first, second, boxRays, reason = recheck(harness, viewer, target)
	if second ~= playerRays or boxRays ~= 0 or reason ~= "Hidden" then
		return false, `Behind the thin wall the recheck cast {second} engine rays and {boxRays} box rays, {reason}`
	end

	-- 4) What blocks every ray is a ball, a wedge, a mesh or terrain, so no box is kept and the recheck casts them all;
	-- each part stands across every ray, so a box kept of it would settle them
	local ball: any = roblox.Instance.new("Part")
	ball.Shape = roblox.Enum.PartType.Ball

	local blockers: { [string]: any } = {
		ball = ball,
		wedge = roblox.Instance.new("WedgePart"),
		mesh = roblox.Instance.new("MeshPart"),
		terrain = roblox.Instance.new("Terrain"),
	}

	for name: string, blocker: any in blockers do
		if not blocker:IsA("Terrain") then
			blocker.Size = roblox.Vector3.new(12, 12, 1)
			blocker.CFrame = roblox.CFrame.new(0, 3, WALL_Z)
		end

		harness, viewer, target = scene()
		harness.wall = function (_: vector, _: vector): any
			return blocker
		end

		first, second, boxRays, reason = recheck(harness, viewer, target)
		if first ~= playerRays or second ~= playerRays or boxRays ~= 0 or reason ~= "Hidden" then
			return false, `Behind the {name} the recheck cast {second} engine rays and {boxRays} box rays, {reason}`
		end
	end

	-- 5) A segment through a wall's kept box crosses it while every part of it is finite, and never with a NaN or
	-- infinite end or origin, which memory off would hand the engine
	local Casts: any = Environment.load(CASTS)
	local box: buffer = buffer.create(Casts.BOX_BYTES)
	local kept: any = roblox.Instance.new("Part")
	kept.Size = roblox.Vector3.new(12, 12, 1)
	kept.CFrame = roblox.CFrame.new(0, 3, WALL_Z)
	Casts.writeBox(box, 0, kept)

	local from: vector = vector.create(0, 3, 0)
	local to: vector = vector.create(0, 3, TARGET_Z)
	if not Casts.crosses(box, 0, from, to) then
		return false, "The finite segment through the kept box did not cross it"
	end

	local segments: { [string]: { vector } } = {
		["a NaN end on x"] = { from, vector.create(NAN, to.y, to.z) },
		["a NaN end on y"] = { from, vector.create(to.x, NAN, to.z) },
		["an end at infinity on x"] = { from, vector.create(math.huge, to.y, to.z) },
		["an end at minus infinity on z"] = { from, vector.create(to.x, to.y, -math.huge) },
		["a NaN origin on x"] = { vector.create(NAN, from.y, from.z), to },
		["an origin at infinity on x"] = { vector.create(math.huge, from.y, from.z), to },
	}

	for name: string, segment: { vector } in segments do
		if Casts.crosses(box, 0, segment[1], segment[2]) then
			return false, `The segment with {name} crossed the kept box`
		end
	end

	return true, nil
end
