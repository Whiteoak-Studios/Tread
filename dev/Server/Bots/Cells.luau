--[[
    The even grid a group's bodies lay out on over an area: as many columns
    as the count's square root rounded up and the rows it needs, each body's
    cell filled a row at a time from the low corner, and walls on its lines
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Bots.Config)

local WALLS: Config.Walls = require(ServerScriptService.Server.Bots.Config).step.walls
local SINK: number = require(ServerScriptService.Server.Bots.Config).spawn.sink
local CELL_CENTER: number = 0.5 -- Where in its column and row a cell's center sits

type Area = Config.Area

-- A wall's center and its size along each axis, in studs
export type Wall = { center: Vector3, size: Vector3 }

local Cells = {}

-- The grid count bodies take over an area: its columns and rows, and a cell's width along X and depth along Z
local function grid(area: Area, count: number): (number, number, number, number)
	local columns: number = math.ceil(math.sqrt(count))
	local rows: number = math.ceil(count / columns)

	return columns, rows, area.size.X / columns, area.size.Y / rows
end

-- The cell of the body at that place, from 1, among count bodies, at the area's height
function Cells.cell(area: Area, count: number, place: number): Area
	local columns: number, _: number, width: number, depth: number = grid(area, count)
	local column: number = (place - 1) % columns
	local row: number = (place - 1) // columns

	local x: number = area.center.X - area.size.X / 2 + (column + CELL_CENTER) * width
	local z: number = area.center.Z - area.size.Y / 2 + (row + CELL_CENTER) * depth

	return { center = Vector3.new(x, area.center.Y, z), size = Vector2.new(width, depth) }
end

--[[
    The walls on every line of the grid count bodies take over an area, the
    columns' edges first, each as long as its line and one thickness more so
    the corners close, standing on the floor a run lays under the area
--]]

function Cells.walls(area: Area, count: number): { Wall }
	local columns: number, rows: number, width: number, depth: number = grid(area, count)
	local lowX: number = area.center.X - area.size.X / 2
	local lowZ: number = area.center.Z - area.size.Y / 2
	local height: number = area.center.Y - SINK + WALLS.height / 2
	local walls: { Wall } = {}

	for column: number = 0, columns do
		table.insert(walls, {
			center = Vector3.new(lowX + column * width, height, area.center.Z),
			size = Vector3.new(WALLS.thickness, WALLS.height, area.size.Y + WALLS.thickness),
		})
	end

	for row: number = 0, rows do
		table.insert(walls, {
			center = Vector3.new(area.center.X, height, lowZ + row * depth),
			size = Vector3.new(area.size.X + WALLS.thickness, WALLS.height, WALLS.thickness),
		})
	end

	return walls
end

return Cells
