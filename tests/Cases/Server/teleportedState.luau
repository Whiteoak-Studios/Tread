--[[
    character:getState read inside a game's onTeleported callback gives the
    body where the teleport set it down, its new epoch included, not the
    state the tick before produced
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 4
local CLOSE: number = 0.1 -- Studs the landing may sit from its destination, the skin and a rest included

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local mover: any = server:create(rig.mock:addBot("Mover"), rig:at(6, 0))
	rig:tick(TICKS)

	local epoch: number = mover:getState().epoch
	local read: any = nil
	local stop: () -> () = server:onTeleported(function (character: any)
		local state: any = character:getState()
		read = { root = state.root, epoch = state.epoch }
	end)

	local destination: any = rig:at(-10, 5)
	mover:teleport(destination)
	rig:tick(1)
	stop()

	if not read then
		return false, "The onTeleported callback never ran"
	end

	local root: Vector3 = read.root
	local target: Vector3 = destination.Position
	if math.abs(root.X - target.X) > CLOSE or math.abs(root.Z - target.Z) > CLOSE then
		return false, `getState inside onTeleported read the body at {root}, not where it landed at {target}`
	elseif read.epoch ~= epoch + 1 then
		return false, `getState inside onTeleported read epoch {read.epoch}, not the landing's {epoch + 1}`
	end

	return true, nil
end
