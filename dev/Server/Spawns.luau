--[[
    The plaza's spawn points: a grid over the spawn area the city block's
    attributes give, each point held by one player from their join until
    they leave, so no two characters are built in one place
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local COLUMNS: number = require(ServerScriptService.Server.Config.Spawns).columns
local ROWS: number = require(ServerScriptService.Server.Config.Spawns).rows
local LIFT: number = require(ServerScriptService.Server.Config.Spawns).lift
local CELL_CENTER: number = 0.5 -- Where in its cell along each axis a point sits

local Points: { CFrame } = {} -- Row by row from the area's low corner, each facing along -Z
local Holders: { [number]: Player } = {} -- Each held point's player, by the point's index
local Held: { [Player]: number } = {} -- Each holding player's point index

local Spawns = {}

-- One of the city block's corners of its spawn area, by the attribute's name, erroring when the place lacks it
local function corner(cityBlock: Instance, name: string): Vector3
	local value: any = cityBlock:GetAttribute(name)
	if typeof(value) ~= "Vector3" then
		error(`{cityBlock:GetFullName()} has no Vector3 attribute {name}, so the dev game has no spawn area`, 3)
	end

	return value
end

--[[
    Lays the grid over the spawn area Workspace.TestContent.CityBlock's
    SpawnAreaMin and SpawnAreaMax give, at the lift above its floor, and
    errors when the place has no city block or the block has no area. It
    runs once a server, before the first take
--]]

function Spawns.start()
	if #Points > 0 then
		error("Spawns.start runs once a server, and it has already run", 2)
	end

	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	local cityBlock: Instance? = testContent and testContent:FindFirstChild("CityBlock")
	if not cityBlock then
		error("Workspace.TestContent.CityBlock is missing, so the dev game has no spawn area", 2)
	end

	local low: Vector3 = corner(cityBlock, "SpawnAreaMin")
	local high: Vector3 = corner(cityBlock, "SpawnAreaMax")
	local span: Vector3 = high - low

	for row: number = 1, ROWS do
		for column: number = 1, COLUMNS do
			local x: number = low.X + span.X * (column - CELL_CENTER) / COLUMNS
			local z: number = low.Z + span.Z * (row - CELL_CENTER) / ROWS
			table.insert(Points, CFrame.new(x, low.Y + LIFT, z))
		end
	end
end

--[[
    The point a joining player's character is built at: the one they hold
    already, else the first free one, which they hold until released, or
    nil when every point is held
--]]

function Spawns.take(player: Player): CFrame?
	if #Points == 0 then
		error("Spawns.take ran before Spawns.start", 2)
	end

	local index: number? = Held[player]
	if index then
		return Points[index]
	end

	for free: number = 1, #Points do
		if Holders[free] == nil then
			Holders[free] = player
			Held[player] = free

			return Points[free]
		end
	end

	return nil
end

--[[
    Frees the point a player who left held, for the next to join. A player
    who holds none is left as it is
--]]

function Spawns.release(player: Player)
	local index: number? = Held[player]
	if index then
		Holders[index] = nil
		Held[player] = nil
	end
end

return Spawns
