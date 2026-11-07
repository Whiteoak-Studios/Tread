--[[
    A part none of the four, and a shown flag that is no boolean, each have
    their reason, and the four parts with either boolean have none
--]]

--!strict
local Environment = require("../../Environment")

local FIRST_PERSON: string = "src/Client/Rigs/FirstPerson.luau"

return function (): (boolean, string | nil)
	local FirstPerson = Environment.load(FIRST_PERSON)

	local parts: { any } = { "legs", "Arms", "head", 1, true, {} }
	for _, part: any in parts do
		local problem: string? = FirstPerson.refuse(part, true)
		if problem == nil then
			return false, `{part} was taken as a part`
		elseif not string.find(problem, `not {part}`, 1, true) then
			return false, `The refusal of {part} doesn't name it: {problem}`
		end
	end

	if FirstPerson.refuse(nil, true) == nil then
		return false, "No part at all was taken"
	end

	local flags: { any } = { 1, "true", nil :: any }
	for index: number = 1, 3 do
		local problem: string? = FirstPerson.refuse("arms", flags[index])
		if problem == nil then
			return false, `{flags[index]} was taken as shown`
		elseif not string.find(problem, "boolean", 1, true) then
			return false, `The refusal of {flags[index]} as shown names no boolean: {problem}`
		end
	end

	local valid: { string } = { "arms", "chest", "copy", "rig" }
	for _, part: string in valid do
		local shown: string? = FirstPerson.refuse(part, true)
		local hidden: string? = FirstPerson.refuse(part, false)
		if shown or hidden then
			return false, `{part} was refused: {shown or hidden}`
		end
	end

	return true, nil
end
