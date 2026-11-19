--[[
    The spawn grid refuses to start in a place with no city block or with
    a corner of its spawn area missing, naming what is, refuses a take
    before the start, and a second start
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local CORNER: Vector3 = roblox.Vector3.new(3830, 0.5, -75)

-- The dev place's spawn grid in a fresh game whose test content holds a city block with the attributes given, or
-- no city block when given none
local function spawns(attributes: { [string]: any }?): any
	local loaded: Harness.Loaded = Harness.load()
	local workspace: any = loaded.game:GetService("Workspace")

	if attributes then
		local testContent: any = roblox.Instance.new("Folder")
		testContent.Name = "TestContent"
		testContent.Parent = workspace

		local cityBlock: any = roblox.Instance.new("Folder")
		cityBlock.Name = "CityBlock"
		cityBlock.Parent = testContent

		for name: string, value: any in attributes do
			cityBlock:SetAttribute(name, value)
		end
	end

	return loaded.require(loaded.game:GetService("ServerScriptService").Server.Spawns)
end

-- Why a start did not refuse naming the text, or nil when it did
local function refused(Spawns: any, text: string): string?
	local started: boolean, failure: any = pcall(Spawns.start)
	if started then
		return `A start ran where it should have refused naming {text}`
	elseif not string.find(tostring(failure), text, 1, true) then
		return `A start was refused as "{failure}", naming no {text}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local problem: string? = refused(spawns(nil), "CityBlock")
		or refused(spawns({ SpawnAreaMin = CORNER }), "SpawnAreaMax")
		or refused(spawns({ SpawnAreaMin = CORNER, SpawnAreaMax = "Plaza" }), "SpawnAreaMax")
	if problem then
		return false, problem
	end

	local Spawns: any = spawns({ SpawnAreaMin = CORNER, SpawnAreaMax = CORNER + roblox.Vector3.one })
	local early: boolean = pcall(Spawns.take, { Name = "Early" })
	if early then
		return false, "A take ran before the start"
	end

	Spawns.start()

	local again: boolean = pcall(Spawns.start)
	if again then
		return false, "A second start ran"
	end

	return true, nil
end
