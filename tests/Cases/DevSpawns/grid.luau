--[[
    The spawn grid covers the city block's spawn area cell by cell at the
    lift above its floor, one point to a player: a player keeps the point
    they hold, a full grid hands out none, and a released point goes next
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local AREA_MIN: Vector3 = roblox.Vector3.new(3830, 0.5, -75) -- The dev place's plaza spawn area
local AREA_MAX: Vector3 = roblox.Vector3.new(3930, 0.5, -15)
local TOLERANCE: number = 1e-6 -- Studs
local RELEASED: number = 7 -- The point index a player gives back
local CENTER: number = 0.5 -- Where along its cell's width each point sits

-- A player stand-in, which the grid only keys on
local function player(index: number): { Name: string }
	return { Name = `Player{index}` }
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local workspace: any = loaded.game:GetService("Workspace")

	local testContent: any = roblox.Instance.new("Folder")
	testContent.Name = "TestContent"
	testContent.Parent = workspace

	local cityBlock: any = roblox.Instance.new("Folder")
	cityBlock.Name = "CityBlock"
	cityBlock:SetAttribute("SpawnAreaMin", AREA_MIN)
	cityBlock:SetAttribute("SpawnAreaMax", AREA_MAX)
	cityBlock.Parent = testContent

	local Spawns: any = loaded.require(server.Spawns)
	local settings: any = loaded.require(server.Config.Spawns)
	Spawns.start()

	local cells: number = settings.columns * settings.rows
	local cellX: number = (AREA_MAX.X - AREA_MIN.X) / settings.columns
	local cellZ: number = (AREA_MAX.Z - AREA_MIN.Z) / settings.rows
	local players: { { Name: string } } = {}

	for index: number = 1, cells do
		local holder: { Name: string } = player(index)
		players[index] = holder

		local at: any = Spawns.take(holder)
		if not at then
			return false, `Point {index} of {cells} was not handed out`
		end

		local column: number = (index - 1) % settings.columns
		local row: number = (index - 1) // settings.columns
		local expected: Vector3 = roblox.Vector3.new(
			AREA_MIN.X + cellX * (column + CENTER),
			AREA_MIN.Y + settings.lift,
			AREA_MIN.Z + cellZ * (row + CENTER)
		)

		if (at.Position - expected).Magnitude > TOLERANCE then
			return false, `Point {index} stood at {at.Position}, not its cell's center {expected}`
		end
	end

	local first: any = Spawns.take(players[1])
	if (first.Position - Spawns.take(players[1]).Position).Magnitude > TOLERANCE then
		return false, "A player who holds a point was handed another"
	end

	local late: { Name: string } = player(cells + 1)
	if Spawns.take(late) ~= nil then
		return false, `A grid of {cells} held points handed out one more`
	end

	local given: any = Spawns.take(players[RELEASED])
	Spawns.release(players[RELEASED])
	Spawns.release(late)

	local back: any = Spawns.take(late)
	if not back or (back.Position - given.Position).Magnitude > TOLERANCE then
		return false, "A released point did not go to the next player"
	end

	return true, nil
end
