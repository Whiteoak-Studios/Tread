--[[
    Engine.wrap refuses a collision table that is no table, or lacks any of
    the four functions, naming the first one missing
--]]

--!strict
local Environment = require("../../Environment")

local ENGINE: string = "src/Step/Engine.luau"

type Row = { name: string, functions: any, refusal: string }

local function cast(): nil
	return nil
end

return function (): (boolean, string | nil)
	local Engine: any = Environment.load(ENGINE)

	local rows: { Row } = {
		{ name = "a number", functions = 4, refusal = "collision must be a table" },
		{ name = "an empty table", functions = {}, refusal = "collision.ray must be a function" },
		{
			name = "no sweep",
			functions = { ray = cast, rest = cast, sphere = cast },
			refusal = "collision.sweep must be a function",
		},
		{
			name = "a rest that is a number",
			functions = { ray = cast, sweep = cast, rest = 1100, sphere = cast },
			refusal = "collision.rest must be a function",
		},
		{
			name = "no sphere",
			functions = { ray = cast, sweep = cast, rest = cast },
			refusal = "collision.sphere must be a function",
		},
		{
			name = "an include holding a string",
			functions = { ray = cast, sweep = cast, rest = cast, sphere = cast, include = { "Map" } },
			refusal = "collision.include[1] must be an Instance",
		},
	}

	for _, row: Row in rows do
		local ran: boolean, message: any = pcall(Engine.wrap, row.functions)
		if ran then
			return false, `Engine.wrap took {row.name}`
		elseif not string.find(`{message}`, row.refusal, 1, true) then
			return false, `Engine.wrap of {row.name} failed with something other than "{row.refusal}": {message}`
		end
	end

	return true, nil
end
