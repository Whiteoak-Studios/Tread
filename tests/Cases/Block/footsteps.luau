--[[
    A footstep entry holds the step's exact position at the record's
    precision across the ±8,192-stud bound and the height window, each of
    its four kinds in X's top 4 bits, and the ground's material
--]]

--!strict
local Environment = require("../../Environment")
local Same = require("../../Fixtures/Codec/Same")

local BLOCK: string = "src/Codec/Block.luau"
local STEP: number = 1 / 64
local HEIGHT_STEP: number = 1 / 32

return function (): (boolean, string | nil)
	local Block: any = Environment.load(BLOCK)
	local roblox: any = require("@lune/roblox")
	local materials: { any } = roblox.Enum.Material:GetEnumItems()

	local function step(at: vector, kind: string, material: any): { [string]: any }
		return { at = at, kind = kind, material = material }
	end

	local rows: { { any } } = {
		{ step(vector.create(-8192, -1024, -8192), "Walk", roblox.Enum.Material.Air) },
		{ step(vector.create(8192 - STEP, 1024 - HEIGHT_STEP, 8192 - STEP), "Sprint", roblox.Enum.Material.Grass) },
		{ step(vector.create(STEP, HEIGHT_STEP, -STEP), "Jump", roblox.Enum.Material.Concrete) },
		{ step(vector.create(0, 0, 0), "Land", roblox.Enum.Material.Water) },
		{
			step(vector.create(9000, 2000, -9000), "Walk", roblox.Enum.Material.Sand),
			step(vector.create(8192 - STEP, 1024 - HEIGHT_STEP, -8192), "Walk", roblox.Enum.Material.Sand),
		},
	}

	-- Every material there is, each kept by its Enum value
	for index: number, material: any in materials do
		table.insert(rows, { step(vector.create(index, index, index), "Walk", material) })
	end

	local data: buffer = buffer.create(12)
	for index: number, row: { any } in rows do
		buffer.fill(data, 0, 0xEE)
		Block.writeFootstep(row[1], data, 1)
		if buffer.readu8(data, 0) ~= 0xEE or buffer.readu8(data, 11) ~= 0xEE then
			return false, `Footstep {index} wrote outside its 10 B`
		end

		local into: { [string]: any } = step(vector.zero, "Walk", roblox.Enum.Material.Air)
		Block.readFootstep(data, 1, into)

		local differs: string? = Same(row[2] or row[1], into, `footstep {index}`)
		if differs then
			return false, differs
		end
	end

	-- The kind in X's top 4 bits and Z's top 4 bits 0: a Land at the origin of Grass
	Block.writeFootstep(step(vector.zero, "Land", roblox.Enum.Material.Grass), data, 0)
	if buffer.readu8(data, 2) ~= 0x38 or buffer.readu8(data, 5) ~= 0x08 then
		return false, `The Land's X and Z top bytes are {buffer.readu8(data, 2)} and {buffer.readu8(data, 5)}`
	elseif buffer.readu16(data, 8) ~= roblox.Enum.Material.Grass.Value then
		return false, "The footstep's material isn't its Enum value"
	end

	return true, nil
end
