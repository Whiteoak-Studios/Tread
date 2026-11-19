--[[
    A checkout hands back a clone of the template dressed once with the
    slot's look as a world rig, kept out of Workspace until a pose draws it
--]]

--!strict
local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	local calls: { any } = {}
	local settings = Rig.settings(calls)
	local rigs = Rigs.new(settings, Rig.drawDistance, Rig.collision())

	local outfit: { [string]: any } = { helmet = 3 }
	local rig: any = rigs:checkout(5, outfit)

	if typeof(rig) ~= "Instance" or not rig:IsA("Model") then
		return false, `checkout gave a {typeof(rig)}, not a Model`
	elseif rig == settings.rig then
		return false, "checkout gave the template itself, not a clone of it"
	elseif not rig:FindFirstChild("LeftFoot") or rig.PrimaryPart == nil then
		return false, "The checked-out rig lacks the template's parts or its PrimaryPart"
	elseif rig.Parent ~= nil then
		return false, `A rig no pose has drawn sits in {rig.Parent:GetFullName()}`
	end

	if #calls ~= 1 then
		return false, `checkout made {#calls} hook calls, not the one dress`
	end

	local call: any = calls[1]
	if call.hook ~= "dress" or call.rig ~= rig or call.outfit ~= outfit or call.copy ~= false then
		local got: string = `{call.hook} with the rig {call.rig == rig}, the outfit {call.outfit == outfit}`
		return false, `checkout called {got} and copy {call.copy}, not dress(rig, outfit, false)`
	end

	rigs:destroy()

	return true, nil
end
