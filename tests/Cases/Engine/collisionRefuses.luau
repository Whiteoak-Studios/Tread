--[[
    Engine.collision refuses an include that is no list or holds anything but
    Instances, naming the entry, before it makes any engine object
--]]

--!strict
local Environment = require("../../Environment")

local ENGINE: string = "src/Step/Engine.luau"

type Row = { name: string, include: any, refusal: string }

return function (): (boolean, string | nil)
	local Engine: any = Environment.load(ENGINE)

	local rows: { Row } = {
		{ name = "no include", include = nil, refusal = "collision.include must be a list of Instances" },
		{ name = "a string", include = "Workspace", refusal = "collision.include must be a list of Instances" },
		{ name = "a list holding a number", include = { 7 }, refusal = "collision.include[1] must be an Instance" },
	}

	for _, row: Row in rows do
		local ran: boolean, message: any = pcall(Engine.collision, row.include)
		if ran then
			return false, `Engine.collision took {row.name}`
		elseif not string.find(`{message}`, row.refusal, 1, true) then
			return false, `Engine.collision of {row.name} failed with something other than "{row.refusal}": {message}`
		end
	end

	return true, nil
end
