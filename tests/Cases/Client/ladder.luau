--[[
    addLadder registers a ladder for prediction and gives back the closure
    that removes it: the same ladder twice is refused for its id, and once
    removed it registers again. A ladder given as anything but a CFrame and
    a Vector3 is refused
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Handle = require("../../Fixtures/Client/Handle")

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local cframe: any = roblox.CFrame.new(4, 5, 6)
	local size: any = roblox.Vector3.new(2, 10, 1)

	local remove: any = handle:addLadder(cframe, size)
	if type(remove) ~= "function" then
		return false, `addLadder gave back a {type(remove)}, not the closure that removes it`
	end

	local twice: boolean = pcall(handle.addLadder, handle, cframe, size)
	if twice then
		return false, "The same ladder registered twice, so the first was never held"
	end

	remove()

	local again: boolean, failure: any = pcall(handle.addLadder, handle, cframe, size)
	if not again then
		return false, `A ladder removed and registered again was refused: {failure}`
	end

	local wrong: boolean, reason: any = pcall(handle.addLadder, handle, cframe.Position, size)
	if wrong then
		return false, "A ladder given as a Vector3 in place of its CFrame was taken"
	elseif not string.find(tostring(reason), "takes a CFrame and a Vector3", 1, true) then
		return false, `A ladder given as a Vector3 failed as "{reason}"`
	end

	return true, nil
end
