--[[
    P10's count of one box's answers: settled when the bounds query found
    nothing, unsound when settled with the exact check inside, Terrain-only
    when it found Terrain alone, which is never settled
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local BOUNDS: string = "dev/Server/Parallel/Bounds.luau"
local SEPARATOR: string = ", "

-- Stand-ins for what the bounds query finds, the Terrain told apart by being itself
local TERRAIN: any = { Name = "Terrain" }
local WALL: any = { Name = "Wall" }
local FLOOR: any = { Name = "Floor" }

-- One box: its center, whether the exact check found something inside, what the bounds query found, and the answer
type Box = {
	center: vector,
	inside: boolean,
	found: { any },
	answer: boolean,
}

local SIZE: vector = vector.create(4, 5, 4)

-- Worked out by hand: boxes 1, 2 and 7 settled, 2 and 7 of them unsound, and 4 and 6 Terrain-only
local BOXES: { Box } = {
	{ center = vector.create(1, 2, 3), inside = false, found = {}, answer = false },
	{ center = vector.create(10.5, 2.25, -7), inside = true, found = {}, answer = false },
	{ center = vector.create(20, 2, 3), inside = true, found = { WALL }, answer = true },
	{ center = vector.create(30, 2, 3), inside = false, found = { TERRAIN }, answer = true },
	{ center = vector.create(40, 2, 3), inside = true, found = { TERRAIN, WALL }, answer = true },
	{ center = vector.create(50, 2, 3), inside = true, found = { TERRAIN }, answer = true },
	{ center = vector.create(0, 0, 0), inside = true, found = {}, answer = false },
	{ center = vector.create(60, 2, 3), inside = false, found = { WALL, FLOOR }, answer = true },
}

local COUNTS: string = "8 boxes, 3 settled, 5 inside, 2 unsound, 2 Terrain-only"
local FIRST: string = "center (10.500, 2.250, -7.000), size (4.000, 5.000, 4.000)" -- Box 2's, the first unsound

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared

	-- The dev shared table stands in empty, since counting reads nothing of it
	local results: { [any]: any } = { [shared.Dev.Config] = {} }
	local Bounds: any =
		Kit.loader(dataModel, { [server.Parallel.Bounds] = BOUNDS }, results, loaded.require)(server.Parallel.Bounds)

	local source: any = { name = "S3", boxes = 0, settled = 0, inside = 0, unsound = 0, terrain = 0 }

	-- 1) Each box's answer is whether the bounds query found anything, Terrain included
	for index: number, box: Box in BOXES do
		local answer: boolean = Bounds.count(source, box.center, SIZE, box.inside, box.found, TERRAIN)
		if answer ~= box.answer then
			return false, `Box {index} answered {answer}, not {box.answer}`
		end
	end

	-- 2) The counts are the hand-worked ones
	local counted: { string } = {
		`{source.boxes} boxes`,
		`{source.settled} settled`,
		`{source.inside} inside`,
		`{source.unsound} unsound`,
		`{source.terrain} Terrain-only`,
	}

	if table.concat(counted, SEPARATOR) ~= COUNTS then
		return false, `The source counted {table.concat(counted, SEPARATOR)}, not {COUNTS}`
	end

	-- 3) The first unsound box is named by its center and size, and a later one leaves it
	if source.first ~= FIRST then
		return false, `The first unsound box was named "{source.first}", not "{FIRST}"`
	end

	return true, nil
end
