--[[
    Crossing a posture's shapes gives each capsule on vector with its radius
    and the waist kept, every capsule a new table on each call, so a set
    crossed again can be placed into while the first stays as it was
--]]

--!strict
local Environment = require("../../Environment")

local SHAPES: string = "src/Step/Shapes.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

-- Why a crossed capsule differs from the shared table's, or nil when it holds the same values
local function differs(name: string, got: any, want: any): string?
	local from: vector = vector.create(want.from.X, want.from.Y, want.from.Z)
	local to: vector = vector.create(want.to.X, want.to.Y, want.to.Z)

	if got == nil then
		return `The {name} capsule wasn't crossed`
	elseif type(got.from) ~= "vector" or type(got.to) ~= "vector" then
		return `The {name} capsule crossed as {typeof(got.from)}, not vector`
	elseif got.from ~= from or got.to ~= to or got.radius ~= want.radius then
		return `The {name} capsule crossed from {got.from} to {got.to} at {got.radius}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local Shapes: any = Environment.load(SHAPES)
	local Example: any = Environment.load(EXAMPLE)
	local given: any = Example.shared().hitShapes.Downed

	local crossed: any = Shapes.cross(given)
	local again: any = Shapes.cross(given)

	local failure: string? = differs("body", crossed.body, given.body)
	for name: string, shape: any in given.zones do
		failure = failure or differs(name, crossed.zones[name], shape)
	end

	if failure then
		return false, failure
	elseif crossed.waist ~= given.waist then
		return false, `The waist crossed as {crossed.waist}, not {given.waist}`
	elseif again.body == crossed.body or again.zones == crossed.zones or again.zones.head == crossed.zones.head then
		return false, "Crossing the same shapes twice handed back a table it had handed out before"
	end

	return true, nil
end
