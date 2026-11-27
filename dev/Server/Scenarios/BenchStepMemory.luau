--[[
    The step benchmark's verdict memory run: Rooms150's walls built on its
    rooms' lines among the city block's occluders, checked against anti-ESP's
    own query, the memory run among them, and the walls taken down after
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Tread = require(ReplicatedStorage.Packages.Tread)

local Engine = require(ReplicatedStorage.Packages.Tread.Step.Engine)

local BenchStep = require(ServerScriptService.Server.Scenarios.BenchStep)
local Cells = require(ServerScriptService.Server.Bots.Cells)
local Config = require(ServerScriptService.Server.Bots.Config)
local Game = require(ServerScriptService.Server.Game)

local LOAD: string = require(ServerScriptService.Server.Bots.Config).step.memory.scenario
local ROOMS: Config.Group = require(ServerScriptService.Server.Bots.Config).scenarios[LOAD].groups[1]
local TITLE: string = "Step benchmark verdict memory run"
local FOLDER: string = "BenchStepMemory" -- The walls' folder, named for the run that builds it
local WALL: string = "Wall"

-- The city block's occluder folder, on anti-ESP's include list in the dev place, nil while the place has none
local function occludersOf(): Instance?
	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	local cityBlock: Instance? = testContent and testContent:FindFirstChild("CityBlock")

	return cityBlock and cityBlock:FindFirstChild("Occluders")
end

-- The walls on the rooms' lines in a folder of their own, each a Block part only anti-ESP's rays meet
local function built(): Folder
	local folder: Folder = Instance.new("Folder")
	folder.Name = FOLDER

	for _, wall: Cells.Wall in Cells.walls(ROOMS.spawn, ROOMS.count) do
		local part: Part = Instance.new("Part")
		part.Name = WALL
		part.Shape = Enum.PartType.Block
		part.Size = wall.size
		part.CFrame = CFrame.new(wall.center)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = true
		part.CanTouch = false
		part.Parent = folder
	end

	return folder
end

--[[
    Builds the walls among the city block's occluders and runs the memory
    run among them, once anti-ESP's query, built before the walls from the
    include list the dev server started with, is open between the rooms'
    first two cells at a standing body's eye and blocked there once the
    walls stand. The walls go whatever happened, and a throw fails the run
--]]

return function (): (boolean, string | nil)
	local occluders: Instance? = occludersOf()
	if not occluders then
		return false, `{TITLE}: Workspace.TestContent.CityBlock.Occluders is missing, so walls there would block no ray`
	end

	local _, shared: Tread.Shared, settings: Tread.ServerSettings = Game.get()
	local blocked: (origin: vector, direction: vector) -> boolean = Engine.occlusion(settings.antiEsp.include)
	local area: Config.Area = ROOMS.spawn
	local from: Config.Area = Cells.cell(area, ROOMS.count, 1)
	local to: Config.Area = Cells.cell(area, ROOMS.count, 2)
	local origin: vector = vector.create(from.center.X, area.center.Y + shared.step.eyeStanding, from.center.Z)
	local direction: vector = vector.create(to.center.X - from.center.X, 0, to.center.Z - from.center.Z)

	if blocked(origin, direction) then
		return false, `{TITLE}: anti-ESP's query between its first two rooms was blocked before any wall stood`
	end

	local folder: Folder = built()
	folder.Parent = occluders

	local ran: boolean, passed: any, line: any = pcall(function (): (boolean, string | nil)
		if not blocked(origin, direction) then
			return false, `{TITLE}: its walls left anti-ESP's query between its first two rooms open`
		end

		return BenchStep("memory")
	end)

	folder:Destroy()

	if not ran then
		return false, `{TITLE} threw: {passed}`
	end

	return passed == true, line
end
