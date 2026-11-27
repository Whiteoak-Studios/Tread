--[[
    Engine.casts builds the step's casts from a game's collision key: its
    own functions crossed over through wrap, engine casts over its include
    list when it gives none, and a refusal for neither, part of the four or
    a key that is no table
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local ENGINE: string = "src/Step/Engine.luau"
local ENGINE_ABSENT: string = "attempt to index nil with 'new'" -- Lune's failure at RaycastParams.new, which it lacks
local DISTANCE: number = 2.5

local function cast(): nil
	return nil
end

return function (): (boolean, string | nil)
	local Engine: any = Environment.load(ENGINE)
	local Vector3: any = roblox.Vector3

	-- The game's own four: each cast hands the game a Vector3 and crosses its hit back onto vector
	local handed: any = nil
	local collision: any = Engine.casts({
		ray = function (origin: any, _: any): any
			handed = origin

			return {
				distance = DISTANCE,
				position = Vector3.new(1, 2, 3),
				normal = Vector3.new(0, 1, 0),
				material = roblox.Enum.Material.Grass,
			}
		end,
		sweep = cast,
		rest = cast,
		sphere = cast,
	})

	local hit: any = collision.ray(vector.create(4, 5, 6), vector.create(0, -1, 0))
	if handed ~= Vector3.new(4, 5, 6) then
		return false, `The game's ray was handed {handed}, not the cast's origin as a Vector3`
	elseif not hit or hit.position ~= vector.create(1, 2, 3) or hit.distance ~= DISTANCE then
		return false, "The game's hit didn't come back crossed onto vector"
	end

	collision.destroy()

	-- An include list and none of the functions: engine casts, which check the list, then reach for the engine
	local folder: any = roblox.Instance.new("Folder")
	local rows: { { any } } = {
		{ "an include list", ENGINE_ABSENT, { include = { folder } } },
		{ "an include list holding a number", "collision.include[1] must be an Instance", { include = { 7 } } },
		{ "neither", "none of the four functions and no include list", {} },
		{ "a ray alone", "collision.sweep must be a function", { ray = cast, include = { folder } } },
		{ "a sphere alone", "collision.ray must be a function", { sphere = cast } },
		{ "a number", "collision must be a table", 5 },
	}

	for _, row: { any } in rows do
		local refused: boolean, why: string = Refuses(row[2], Engine.casts, row[3])
		if not refused then
			return false, `Engine.casts of {row[1]} went another way: {why}`
		end
	end

	return true, nil
end
