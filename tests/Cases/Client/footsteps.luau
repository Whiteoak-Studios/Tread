--[[
    Each footstep entry reaches every footstep callback as a copy of its
    own on Vector3, so two steps in one block arrive as two tables holding
    each step's place, kind and material
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Handle = require("../../Fixtures/Client/Handle")

local TICK: number = 50

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle

	local sent: { any } = {
		{ at = vector.create(10, 2, -5), kind = "Walk", material = roblox.Enum.Material.Grass },
		{ at = vector.create(-7.5, 0.5, 3.25), kind = "Land", material = roblox.Enum.Material.Concrete },
	}

	rig.handshake()

	-- With no callback connected, steps go by
	rig.relay({ tick = TICK, footsteps = sent })

	local heard: { any } = {}
	local others: { any } = {}
	handle:onFootstep(function (step: any)
		table.insert(heard, step)
	end)
	handle:onFootstep(function (step: any)
		table.insert(others, step)
	end)

	rig.relay({ tick = TICK + 1, footsteps = sent })

	if #heard ~= #sent or #others ~= #sent then
		return false, `{#sent} footsteps reached the callbacks {#heard} and {#others} times`
	elseif heard[1] == heard[2] then
		return false, "Two footsteps arrived in one table"
	end

	for index: number, step: any in sent do
		local got: any = heard[index]
		local at: vector = step.at

		if typeof(got.at) ~= "Vector3" then
			return false, `Footstep {index}'s place is a {typeof(got.at)}, not a Vector3`
		elseif got.at.X ~= at.x or got.at.Y ~= at.y or got.at.Z ~= at.z then
			return false, `Footstep {index} fell at {got.at}, not at {at}`
		elseif got.kind ~= step.kind or got.material ~= step.material then
			return false, `Footstep {index} was a {got.kind} on {got.material}, not a {step.kind} on {step.material}`
		elseif others[index].at ~= got.at then
			return false, `The second callback heard footstep {index} at {others[index].at}, not {got.at}`
		end
	end

	return true, nil
end
