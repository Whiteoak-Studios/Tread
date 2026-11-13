--[[
    A marker callback must be a function, and connecting one hands back the
    closure that disconnects it, safe to call more than once
--]]

--!strict
local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	local rigs = Rigs.new(Rig.settings({}), Rig.drawDistance, Rig.collision())

	local took: boolean = pcall(rigs.onMarker, rigs, "callback")
	if took then
		return false, "onMarker took a string as its callback"
	end

	local disconnect: any = rigs:onMarker(function () end)
	if type(disconnect) ~= "function" then
		return false, `onMarker gave back a {type(disconnect)}, not its disconnect closure`
	end

	local once: boolean, problem: any = pcall(disconnect)
	local twice: boolean, again: any = pcall(disconnect)
	if not once or not twice then
		return false, `Disconnecting a marker callback threw: {problem or again}`
	end

	rigs:destroy()

	return true, nil
end
