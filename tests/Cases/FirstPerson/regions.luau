--[[
    The copy shows its hips, legs and chest and arms with its head out of
    view, and the world rig is hidden whole, until each part the game names
    is hidden or shown in turn: the arms, the chest, the copy and the rig
--]]

--!strict
local Environment = require("../../Environment")
local Owner = require("../../Fixtures/Rigs/Owner")

local FIRST_PERSON: string = "src/Client/Rigs/FirstPerson.luau"
local HIDDEN: number = 1
local SHOWN: number = 0

type Trial = { part: string, shown: boolean, names: { string }, expected: number }

return function (): (boolean, string | nil)
	local FirstPerson = Environment.load(FIRST_PERSON)
	local world: Model, copy: Owner.Copy = Owner.rigs()
	local rig: Model = copy.rig

	local view = FirstPerson.new()
	view:build(world, copy)

	local wrong: string? = Owner.all(world, HIDDEN)
	if wrong then
		return false, `The world rig wasn't hidden whole at the start: {wrong}`
	end

	-- The settings at the start: everything but the head shown
	local shownAtStart: { string } = table.clone(Owner.body)
	table.move(Owner.chest, 1, #Owner.chest, #shownAtStart + 1, shownAtStart)
	table.move(Owner.arms, 1, #Owner.arms, #shownAtStart + 1, shownAtStart)

	local hiddenHead: string? = Owner.differs(rig, Owner.head, HIDDEN)
	local shownRest: string? = Owner.differs(rig, shownAtStart, SHOWN)
	if hiddenHead or shownRest then
		return false, `The copy at the start showed its head or hid the rest: {hiddenHead or shownRest}`
	end

	local trials: { Trial } = {
		{ part = "arms", shown = false, names = Owner.arms, expected = HIDDEN },
		{ part = "arms", shown = true, names = Owner.arms, expected = SHOWN },
		{ part = "chest", shown = false, names = Owner.chest, expected = HIDDEN },
		{ part = "chest", shown = true, names = Owner.chest, expected = SHOWN },
	}

	for _, trial: Trial in trials do
		view:show(trial.part, trial.shown)

		local changed: string? = Owner.differs(rig, trial.names, trial.expected)
		local rest: { string } = {}
		for _, name: string in shownAtStart do
			if not table.find(trial.names, name) then
				table.insert(rest, name)
			end
		end
		local kept: string? = Owner.differs(rig, rest, SHOWN)
		local head: string? = Owner.differs(rig, Owner.head, HIDDEN)

		if changed or kept or head then
			return false, `show("{trial.part}", {trial.shown}) left the copy wrong: {changed or kept or head}`
		end
	end

	-- The whole copy, the head staying hidden as it comes back
	view:show("copy", false)
	local gone: string? = Owner.all(rig, HIDDEN)
	if gone then
		return false, `Hiding the copy left part of it shown: {gone}`
	end

	view:show("copy", true)
	local back: string? = Owner.differs(rig, shownAtStart, SHOWN)
	local head: string? = Owner.differs(rig, Owner.head, HIDDEN)
	if back or head then
		return false, `Showing the copy again left it wrong: {back or head}`
	end

	-- The world rig, whole, both ways, and the copy left as it was
	view:show("rig", true)
	local seen: string? = Owner.all(world, SHOWN)
	if seen then
		return false, `Showing the world rig left part of it hidden: {seen}`
	end

	view:show("rig", false)
	local hidden: string? = Owner.all(world, HIDDEN)
	local copyKept: string? = Owner.differs(rig, shownAtStart, SHOWN)
	if hidden or copyKept then
		return false, `Hiding the world rig again left a rig wrong: {hidden or copyKept}`
	end

	return true, nil
end
