--[[
    Engine.occlusion refuses an include that is no list or holds anything
    but Instances, naming antiEsp.include and the entry, and with a list of
    Instances reaches for the engine's raycast, which Lune lacks
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local ENGINE: string = "src/Step/Engine.luau"
local ENGINE_ABSENT: string = "attempt to index nil with 'new'" -- Lune's failure at RaycastParams.new, which it lacks

return function (): (boolean, string | nil)
	local Engine: any = Environment.load(ENGINE)
	local folder: any = roblox.Instance.new("Folder")

	local rows: { { any } } = {
		{ "no include", "antiEsp.include must be a list of Instances", nil },
		{ "a string", "antiEsp.include must be a list of Instances", "Occluders" },
		{ "a list holding a number", "antiEsp.include[2] must be an Instance", { folder, 7 } },
		{ "a list of Instances", ENGINE_ABSENT, { folder } },
	}

	for _, row: { any } in rows do
		local refused: boolean, why: string = Refuses(row[2], Engine.occlusion, row[3])
		if not refused then
			return false, `Engine.occlusion of {row[1]} went another way: {why}`
		end
	end

	-- The step's casts still name their own key
	local refused: boolean, why: string = Refuses("collision.include[1] must be an Instance", Engine.collision, { 7 })
	if not refused then
		return false, `Engine.collision of a list holding a number went another way: {why}`
	end

	return true, nil
end
