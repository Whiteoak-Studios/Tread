--[[
    Math.fall refuses a gravity of 0, below 0 or not a number, since a fall
    under none never ends
--]]

--!strict
local Environment = require("../../Environment")

local MATH: string = "src/Step/Math.luau"
local REFUSAL: string = "A fall needs a gravity above 0"

return function (): (boolean, string | nil)
	local Math: any = Environment.load(MATH)

	local from: vector = vector.create(0, 10, 0)
	local to: vector = vector.zero

	for _, gravity: number in { 0, -68.1, 0 / 0 } do
		local ran: boolean, message: any = pcall(Math.fall, from, to, gravity, 0)
		if ran then
			return false, `Math.fall took a gravity of {gravity}`
		elseif not string.find(`{message}`, REFUSAL, 1, true) then
			local which: string = `Math.fall with a gravity of {gravity}`

			return false, `{which} failed with something other than its refusal: {message}`
		end
	end

	return true, nil
end
