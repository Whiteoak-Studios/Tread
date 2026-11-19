--[[
    Public.new sets every field of the public state, each of the type a
    game reads it as, at rest, and each call makes its own state and its
    own two boxes
--]]

--!strict
local Environment = require("../../Environment")

local PUBLIC: string = "src/Step/Public.luau"

-- Every field of the public State and the type it holds
local FIELDS: { [string]: string } = {
	root = "Vector3",
	facing = "number",
	velocity = "Vector3",
	grounded = "boolean",
	groundNormal = "Vector3",
	groundMaterial = "EnumItem",
	mode = "string",
	posture = "string",
	moveMode = "string",
	eye = "Vector3",
	look = "Vector3",
	hullCenter = "Vector3",
	standingBox = "table",
	lyingBox = "table",
	apex = "number",
	platform = "number",
	epoch = "number",
}

local BOXES: { string } = { "standingBox", "lyingBox" }

return function (): (boolean, string | nil)
	local Public: any = Environment.load(PUBLIC)
	local made: any = Public.new()

	for field: string, kind: string in FIELDS do
		if typeof(made[field]) ~= kind then
			return false, `A new public state's {field} is a {typeof(made[field])}, not a {kind}`
		end
	end

	for field: string in made do
		if FIELDS[field] == nil then
			return false, `A new public state holds {field}, which the public State has no field for`
		end
	end

	for _, name: string in BOXES do
		local box: any = made[name]
		if typeof(box.cframe) ~= "CFrame" or typeof(box.size) ~= "Vector3" then
			return false, `A new public state's {name} holds a {typeof(box.cframe)} and a {typeof(box.size)}`
		end
	end

	if made.mode ~= "Air" or made.posture ~= "Stand" or made.moveMode ~= "Walk" or made.grounded then
		return false, `A new public state is {made.mode}, {made.posture} and {made.moveMode}, not at rest in the air`
	elseif made.platform ~= 0 then
		return false, `A new public state rides platform {made.platform}, where 0 means none`
	end

	local other: any = Public.new()
	if other == made or other.standingBox == made.standingBox or other.lyingBox == made.lyingBox then
		return false, "Two new public states share a table, so filling one would fill the other"
	elseif made.standingBox == made.lyingBox then
		return false, "A new public state's two boxes are one table"
	end

	return true, nil
end
