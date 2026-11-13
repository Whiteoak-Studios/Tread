--[[
    An opening's pair stands along the marker's axis whose shorter side is
    the roomier: the target just inside with its hull centered at the
    marker's height, the viewer out with its eye there, closer in a small room
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")

local Vector3: any = roblox.Vector3
local CFrame: any = roblox.CFrame

-- Frontier Zero's standing hull
local RADIUS: number = 1.39
local STANDING: number = 5
local EYE: number = 4.17

local MARKER: any = CFrame.new(10, 20, 30) -- Unturned, so its right is +X and its look -Z
local JAMB: number = 1.6 -- Studs from the marker to each side of a narrow opening
local OPEN: number = 50 -- Studs to a wall far past every cast
local CLOSE: number = 1e-6

-- Studs to the nearest wall from the marker along each of the four horizontal directions
type Walls = { px: number, nx: number, pz: number, nz: number }

-- One opening and where its pair must stand
type Case = {
	name: string,
	walls: Walls,
	normal: any,
	target: any,
	viewer: any,
}

-- A stand-in for the world's casts: walls square to the axes at the distances given from the marker
local function freeIn(walls: Walls): (origin: any, direction: any) -> number
	return function (_: any, direction: any): number
		local wall: number = walls.nz
		if direction.X > 0 then
			wall = walls.px
		elseif direction.X < 0 then
			wall = walls.nx
		elseif direction.Z > 0 then
			wall = walls.pz
		end

		return math.min(wall, direction.Magnitude)
	end
end

local function near(a: any, b: any): boolean
	return (a - b).Magnitude < CLOSE
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local Reveals: any = loaded.require(server.Reveals)
	local config: any = loaded.require(server.Config.Reveals).openings

	local sizes: { [string]: number } = {
		probe = config.probe,
		view = config.view,
		margin = config.margin,
		inside = config.inside,
		radius = RADIUS,
		standing = STANDING,
		eye = EYE,
	}

	local center: any = MARKER.Position
	local inward: number = RADIUS + config.inside -- 2.89 studs
	local room: number = 7 -- The small room's far wall, along -Z
	local cramped: number = room - RADIUS - config.margin -- 4.61 studs, inside the 12 the view allows
	local targetDrop: any = Vector3.new(0, STANDING / 2, 0)
	local viewerDrop: any = Vector3.new(0, EYE, 0)
	local towardLook: any = Vector3.new(0, 0, -1)
	local towardRight: any = Vector3.new(1, 0, 0)

	local cases: { Case } = {
		{
			-- A doorway in a wall along X: open both ways along Z, a tie the marker's look takes
			name = "doorway",
			walls = { px = JAMB, nx = JAMB, pz = OPEN, nz = OPEN },
			normal = towardLook,
			target = center - towardLook * inward - targetDrop,
			viewer = center + towardLook * config.view - viewerDrop,
		},
		{
			-- The viewer's side a small room, 7 studs to its wall, roomier than the target's 5
			name = "small room",
			walls = { px = JAMB, nx = JAMB, pz = 5, nz = room },
			normal = towardLook,
			target = center - towardLook * inward - targetDrop,
			viewer = center + towardLook * cramped - viewerDrop,
		},
		{
			-- A doorway in a wall along Z, open along X
			name = "turned doorway",
			walls = { px = OPEN, nx = OPEN, pz = JAMB, nz = JAMB },
			normal = towardRight,
			target = center - towardRight * inward - targetDrop,
			viewer = center + towardRight * config.view - viewerDrop,
		},
	}

	for _, case: Case in cases do
		local placed: any = Reveals.place(MARKER, freeIn(case.walls), sizes)

		if not near(placed.normal, case.normal) then
			return false, `The {case.name}'s axis ran along {placed.normal}, not {case.normal}`
		elseif not near(placed.target, case.target) then
			return false, `The {case.name}'s target stood at {placed.target}, not {case.target}`
		elseif not near(placed.viewer, case.viewer) then
			return false, `The {case.name}'s viewer stood at {placed.viewer}, not {case.viewer}`
		end
	end

	-- A marker turned off level has no horizontal axis to find
	local tipped: any = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
	if pcall(Reveals.place, tipped, freeIn(cases[1].walls), sizes) then
		return false, "A marker turned onto its side was placed"
	end

	return true, nil
end
