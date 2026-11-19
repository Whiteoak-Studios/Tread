--[[
    A body whose copy couldn't be dressed still hides its world rig until
    the game shows it, and every setting and release works with no copy
--]]

--!strict
local Environment = require("../../Environment")
local Owner = require("../../Fixtures/Rigs/Owner")

local FIRST_PERSON: string = "src/Client/Rigs/FirstPerson.luau"
local HIDDEN: number = 1
local SHOWN: number = 0

return function (): (boolean, string | nil)
	local FirstPerson = Environment.load(FIRST_PERSON)
	local world: Model = Owner.rigs()

	local view = FirstPerson.new()
	view:build(world, nil)

	local hidden: string? = Owner.all(world, HIDDEN)
	if hidden then
		return false, `With no copy the world rig wasn't hidden: {hidden}`
	end

	local parts: { string } = { "arms", "chest", "copy" }
	for _, part: string in parts do
		local hid: boolean, problem: any = pcall(view.show, view, part, false)
		if not hid then
			return false, `show("{part}", false) with no copy threw: {problem}`
		end
	end

	view:refresh()
	if Owner.all(world, HIDDEN) ~= nil then
		return false, "A refresh with no copy showed part of the world rig"
	end

	view:show("rig", true)
	local shown: string? = Owner.all(world, SHOWN)
	if shown then
		return false, `With no copy the world rig wasn't shown by the rig setting: {shown}`
	end

	view:show("rig", false)
	view:release()
	if Owner.all(world, SHOWN) ~= nil then
		return false, "A release with no copy left the world rig hidden"
	end

	return true, nil
end
