--[[
    Two shared tables equal in every value hash alike, a second build of the
    fixture and a copy whose every table took its keys in another order,
    which iterates them in another order
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PADDING: number = 2 -- Spare keys per real key that grow each copy's table before its keys go in

-- Keys in one order, numbers first and strings second, so the copy can put them in the reverse
local function before(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return type(a) < type(b)
	end

	return a < b
end

--[[
    A copy of a value whose every table first grows past its keys with
    spare ones, then takes its keys in the reverse of sorted order, and then
    drops the spares
--]]

local function rebuilt(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local keys: { any } = {}
	for key in value do
		table.insert(keys, key)
	end

	table.sort(keys, before)

	local result: { [any]: any } = {}
	local spares: number = #keys * PADDING

	for index: number = 1, spares do
		result[`spare{index}`] = true
	end

	for index: number = #keys, 1, -1 do
		result[keys[index]] = rebuilt(value[keys[index]])
	end

	for index: number = 1, spares do
		result[`spare{index}`] = nil
	end

	return result
end

-- The keys of a table in the order it iterates them
local function order(source: { [any]: any }): { any }
	local keys: { any } = {}
	for key in source do
		table.insert(keys, key)
	end

	return keys
end

local function same(a: { any }, b: { any }): boolean
	if #a ~= #b then
		return false
	end

	for index: number = 1, #a do
		if a[index] ~= b[index] then
			return false
		end
	end

	return true
end

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	local shared = Example.shared()
	local base: number = Config.hash(shared)

	if Config.hash(Example.shared()) ~= base then
		return false, "Two builds of the same shared table hashed apart"
	end

	local copy = rebuilt(shared)

	-- The copy must iterate its keys in another order, or the case proves nothing
	if same(order(shared.step), order(copy.step)) and same(order(shared), order(copy)) then
		return false, "The copy iterates its keys in the fixture's own order"
	end

	if Config.hash(copy) ~= base then
		return false, "A shared table built in another order hashed apart from an equal one"
	end

	return true, nil
end
