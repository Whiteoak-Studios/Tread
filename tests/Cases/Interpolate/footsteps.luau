--[[
    Every footstep entry a block carries goes to each footstep callback in
    the block's order, with its position, kind and material, whatever the
    slot table holds, and a disconnected callback hears none
--]]

--!strict
local Same = require("../../Fixtures/Codec/Same")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local roblox: any = require("@lune/roblox")

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate

	-- At the record's precision, 1/64 stud across and 1/32 up
	local steps: { { [string]: any } } = {
		{ at = vector.create(1.5, 2.25, -3.015625), kind = "Sprint", material = roblox.Enum.Material.Grass },
		{ at = vector.create(-4096, -5.5, 8000), kind = "Land", material = roblox.Enum.Material.Concrete },
	}

	local heard: number = 0
	local disconnect: () -> () = Interpolate.onFootstep(function ()
		heard += 1
	end)

	viewer.send({ tick = 3, footsteps = steps })

	if #viewer.footsteps ~= 2 or heard ~= 2 then
		return false, `Two footstep entries reached the callbacks {#viewer.footsteps} and {heard} times`
	end

	for index: number, step: { [string]: any } in steps do
		local differs: string? = Same(step, viewer.footsteps[index], `footstep {index}`)
		if differs then
			return false, differs
		end
	end

	disconnect()
	viewer.send({ tick = 4, footsteps = { steps[1] } })

	if heard ~= 2 or #viewer.footsteps ~= 3 then
		return false, `After its disconnect a footstep callback heard {heard - 2} more`
	end

	return true, nil
end
