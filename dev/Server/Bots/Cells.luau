--[[
    One body's cell of an area its group lays out on an even grid: as many
    columns as the count's square root rounded up and the rows it needs,
    filled a row at a time from the area's low corner, the last row in part
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)

local CELL_CENTER: number = 0.5 -- Where in its column and row a cell's center sits

type Area = Config.Area

-- The cell of the body at that place, from 1, among count bodies, at the area's height
return function (area: Area, count: number, place: number): Area
	local columns: number = math.ceil(math.sqrt(count))
	local rows: number = math.ceil(count / columns)
	local width: number = area.size.X / columns
	local depth: number = area.size.Y / rows
	local column: number = (place - 1) % columns
	local row: number = (place - 1) // columns

	local x: number = area.center.X - area.size.X / 2 + (column + CELL_CENTER) * width
	local z: number = area.center.Z - area.size.Y / 2 + (row + CELL_CENTER) * depth

	return { center = Vector3.new(x, area.center.Y, z), size = Vector2.new(width, depth) }
end
