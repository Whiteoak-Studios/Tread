--[[
    The gap check's layout from its config: two 45-stud walls 12 tall with a
    2-stud gap and each occluder 0.2 inside, four passes at 62 to 330 studs
    each starting in the open, and every place inside Tread's wire bounds
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local DevClient = require("../../Fixtures/DevClient/Harness")
local DevServer = require("../../Fixtures/DevServer/Harness")
local DevShared = require("../../Fixtures/DevShared/Harness")

local SETTINGS: string = "dev/Server/Config/Tread.luau"
local LENGTH: number = 45 -- Studs each wall runs along the line
local HEIGHT: number = 12
local GAP: number = 2
local INSET: number = 0.2 -- Studs each occluder sits inside its wall on every face
local CLOSE: number = 1e-4 -- Studs, inside a Vector3's 32-bit float at these sizes

-- Each pass's viewer studs from the wall line and its path's behind it, their sum, and whether it is near
local PASSES: { { viewer: number, behind: number, distance: number, near: boolean } } = {
	{ viewer = 60, behind = 2, distance = 62, near = true },
	{ viewer = 60, behind = 30, distance = 90, near = true },
	{ viewer = 300, behind = 2, distance = 302, near = false },
	{ viewer = 300, behind = 30, distance = 330, near = false },
}

-- The folders the dev server's settings take from Workspace, each a path below it
local OCCLUDERS: { { string } } = {
	{ "TestContent", "CityBlock", "Occluders" },
	{ "TestContent", "Monuments", "Occluders" },
}

local function near(a: number, b: number): boolean
	return math.abs(a - b) <= CLOSE
end

-- The dev server's settings, loaded with the occluder folders they read from Workspace
local function settingsOf(): { [string]: any }
	local place: DevClient.Game = DevClient.new()
	local workspace: any = place.game:GetService("Workspace")

	for _, path: { string } in OCCLUDERS do
		local parent: any = workspace
		for _, name: string in path do
			local folder: any = parent:FindFirstChild(name)
			if not folder then
				folder = roblox.Instance.new("Folder")
				folder.Name = name
				folder.Parent = parent
			end

			parent = folder
		end
	end

	return place.load(SETTINGS)
end

return function (): (boolean, string | nil)
	local loaded: DevServer.Loaded = DevServer.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local Gap: any = loaded.require(server.Gap)
	local config: any = loaded.require(server.Config.GapCrossing)
	local step: any = DevShared.load().shared.step
	local settings: { [string]: any } = settingsOf()
	local Constants: any = DevClient.new().tread("Constants")

	local layout: any = Gap.layout(config)
	local center: any = layout.center

	-- 1) Two walls in line along Z at the center's X, each standing on the floor's top, the gap between them centered
	if #layout.walls ~= 2 or #layout.occluders ~= 2 then
		return false, `The layout has {#layout.walls} walls and {#layout.occluders} occluders, not 2 and 2`
	end

	local first: any, second: any = layout.walls[1], layout.walls[2]
	for index: number, wall: any in layout.walls do
		local size: any = wall.size
		if not near(size.Z, LENGTH) or not near(size.Y, HEIGHT) or not near(wall.center.X, center.X) then
			return false, `Wall {index} is {size} at {wall.center}, not {LENGTH} long and {HEIGHT} tall on the line`
		elseif not near(wall.center.Y - size.Y / 2, center.Y) then
			return false, `Wall {index} stands from {wall.center.Y - size.Y / 2}, not the floor's top at {center.Y}`
		end

		local occluder: any = layout.occluders[index]
		local inside: any = size - occluder.size
		if occluder.center ~= wall.center then
			return false, `Occluder {index} is centered at {occluder.center}, not its wall's {wall.center}`
		elseif not near(inside.X, 2 * INSET) or not near(inside.Y, 2 * INSET) or not near(inside.Z, 2 * INSET) then
			return false, `Occluder {index} is {occluder.size} inside its wall's {size}, not {INSET} in on every face`
		end
	end

	local lowEdge: number = first.center.Z + first.size.Z / 2
	local highEdge: number = second.center.Z - second.size.Z / 2
	if not near(highEdge - lowEdge, GAP) or not near((lowEdge + highEdge) / 2, center.Z) then
		return false,
			`The walls leave {highEdge - lowEdge} studs between Z {lowEdge} and {highEdge}, not {GAP} at the center`
	end

	-- 2) The four passes: each viewer out along -X looking toward the walls, its path behind them, inside the first
	-- band, near ones inside anti-ESP's near radius and far ones past it
	if #layout.passes ~= #PASSES then
		return false, `The layout has {#layout.passes} passes, not {#PASSES}`
	end

	local firstBand: number = settings.tiers.edges[1].enter
	local nearRadius: number = settings.antiEsp.nearRadius
	local ends: number = GAP / 2 + LENGTH -- The walls' far ends from the gap's middle
	for index: number, expected: { viewer: number, behind: number, distance: number, near: boolean } in PASSES do
		local pass: any = layout.passes[index]
		local spot: any = center - roblox.Vector3.new(expected.viewer, 0, 0)
		if pass.spot ~= spot or pass.path ~= center.X + expected.behind or pass.distance ~= expected.distance then
			return false,
				`Pass {index} stands the viewer at {pass.spot} and its path at X {pass.path}, {pass.distance} away`
		elseif pass.look ~= roblox.Vector3.new(1, 0, 0) then
			return false, `Pass {index} sets the viewer down looking along {pass.look}, not toward the walls`
		elseif pass.distance >= firstBand or (pass.distance <= nearRadius) ~= expected.near then
			return false,
				`Pass {index}'s target, {pass.distance} away, isn't where it should be against {firstBand} and {nearRadius}`
		end

		-- Its path starts and ends with the whole hull in the open, past where the walls hide it from the viewer
		local shadow: number = ends * expected.distance / expected.viewer
		if not near(pass.shadow, shadow) then
			return false, `Pass {index} reads the walls' shadow on its path as {pass.shadow} studs, not {shadow}`
		elseif not (pass.reach >= shadow + step.radius) then
			return false,
				`Pass {index}'s path runs {pass.reach} studs, inside the walls' shadow of {shadow} and a hull's half`
		end
	end

	-- 3) The floor's top is the center's height and holds every spot and path end with a hull to spare
	local floor: any = layout.floor
	local half: any = floor.size / 2
	if not near(floor.center.Y + half.Y, center.Y) then
		return false, `The floor's top is at {floor.center.Y + half.Y}, not {center.Y}`
	end

	local places: { any } = {}
	for _, pass: any in layout.passes do
		table.insert(places, pass.spot)
		table.insert(places, roblox.Vector3.new(pass.path, center.Y, center.Z - pass.reach))
		table.insert(places, roblox.Vector3.new(pass.path, center.Y, center.Z + pass.reach))
	end

	for _, place: any in places do
		local offset: any = place - floor.center
		if math.abs(offset.X) + step.radius > half.X or math.abs(offset.Z) + step.radius > half.Z then
			return false, `A body at {place} would stand off the floor at {floor.center}, {floor.size}`
		end
	end

	-- 4) Every place inside the wire's bounds: across by PLAY_BOUND, and the feet, the eye and the hull's top by the
	-- record's height window, and the sprint inside the velocity limit
	local bound: number = Constants.PLAY_BOUND
	for _, corner: number in { -1, 1 } do
		local x: number = floor.center.X + corner * half.X
		local z: number = floor.center.Z + corner * half.Z
		if math.abs(x) > bound or math.abs(z) > bound then
			return false, `The floor's corner at X {x}, Z {z} lies past the play bound of {bound}`
		end
	end

	for _, height: number in { center.Y, center.Y + step.eyeStanding, center.Y + step.standing } do
		if height < Constants.HEIGHT_MIN or height > Constants.HEIGHT_MAX then
			return false, `A body's height of {height} lies outside {Constants.HEIGHT_MIN} to {Constants.HEIGHT_MAX}`
		end
	end

	if not (step.sprint < Constants.VELOCITY_LIMIT) then
		return false, `The sprint of {step.sprint} studs/s is past the velocity limit of {Constants.VELOCITY_LIMIT}`
	end

	return true, nil
end
