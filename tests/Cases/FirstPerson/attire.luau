--[[
    Attire a hook adds later takes the region of the parts it is welded to,
    by a Weld, a WeldConstraint, a RigidConstraint or a Motor6D, piece to
    piece, wherever it is parented, and every piece on the world rig hides
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Environment = require("../../Environment")
local Owner = require("../../Fixtures/Rigs/Owner")

local FIRST_PERSON: string = "src/Client/Rigs/FirstPerson.luau"
local HIDDEN: number = 1
local SHOWN: number = 0

type Trial = { part: string, shown: boolean, expected: { [string]: number } }

return function (): (boolean, string | nil)
	local FirstPerson = Environment.load(FIRST_PERSON)
	local world: Model, copy: Owner.Copy = Owner.rigs()
	local rig: Model = copy.rig

	local view = FirstPerson.new()
	view:build(world, copy)

	-- What a dress and a hold hook put on, after the copy was built
	local head: BasePart = Owner.find(rig, "Head")
	local torso: BasePart = Owner.find(rig, "UpperTorso")
	local hand: BasePart = Owner.find(rig, "RightHand")
	local arm: BasePart = Owner.find(rig, "LeftUpperArm")
	local shin: BasePart = Owner.find(rig, "LeftLowerLeg")

	local helmet: BasePart = Owner.wear(rig, "Helmet", head, "Weld")
	Owner.wear(rig, "Visor", helmet, "WeldConstraint") -- On the helmet, never the head itself
	Owner.wear(rig, "Vest", torso, "RigidConstraint")
	Owner.wear(rig, "Held", hand, "Motor6D")
	local sleeve: BasePart = Owner.wear(rig, "Sleeve", arm, "WeldConstraint")
	local strap: any = roblox.Instance.new("WeldConstraint")
	strap.Part0 = torso
	strap.Part1 = sleeve
	strap.Parent = sleeve
	Owner.wear(rig, "Boot", shin, "Weld")

	local loose: any = roblox.Instance.new("Part") -- Welded to nothing, so the body's alone
	loose.Name = "Loose"
	loose.Parent = rig

	local badge: any = roblox.Instance.new("Decal") -- On the helmet, so the head's
	badge.Name = "Badge"
	badge.Parent = helmet
	local patch: any = roblox.Instance.new("Decal") -- On the boot, so the body's
	patch.Name = "Patch"
	patch.Parent = Owner.find(rig, "Boot")

	view:refresh()

	local trials: { Trial } = {
		{
			part = "arms",
			shown = true,
			expected = {
				Helmet = HIDDEN,
				Visor = HIDDEN,
				Badge = HIDDEN,
				Vest = SHOWN,
				Held = SHOWN,
				Sleeve = SHOWN,
				Boot = SHOWN,
				Patch = SHOWN,
				Loose = SHOWN,
			},
		},
		{ part = "arms", shown = false, expected = { Held = HIDDEN, Sleeve = HIDDEN, Vest = SHOWN, Boot = SHOWN } },
		{ part = "arms", shown = true, expected = { Held = SHOWN, Sleeve = SHOWN } },
		{ part = "chest", shown = false, expected = { Vest = HIDDEN, Sleeve = HIDDEN, Held = SHOWN, Boot = SHOWN } },
		{ part = "chest", shown = true, expected = { Vest = SHOWN, Sleeve = SHOWN } },
		{ part = "copy", shown = false, expected = { Boot = HIDDEN, Patch = HIDDEN, Loose = HIDDEN, Held = HIDDEN } },
		{ part = "copy", shown = true, expected = { Boot = SHOWN, Loose = SHOWN, Helmet = HIDDEN, Badge = HIDDEN } },
	}

	for _, trial: Trial in trials do
		view:show(trial.part, trial.shown)

		for name: string, expected: number in trial.expected do
			local value: number = Owner.level(rig, name)
			if value ~= expected then
				return false,
					`After show("{trial.part}", {trial.shown}) the copy's {name} reads {value}, not {expected}`
			end
		end
	end

	-- The same attire on the world rig hides with it
	local worldHand: BasePart = Owner.find(world, "RightHand")
	local worldHead: BasePart = Owner.find(world, "Head")
	Owner.wear(world, "Held", worldHand, "Motor6D")
	local worldHelmet: BasePart = Owner.wear(world, "Helmet", worldHead, "Weld")
	local worldBadge: any = roblox.Instance.new("Decal")
	worldBadge.Parent = worldHelmet

	view:refresh()

	local unseen: string? = Owner.all(world, HIDDEN)
	if unseen then
		return false, `Attire added to the world rig stayed shown: {unseen}`
	end

	view:show("rig", true)
	local seen: string? = Owner.all(world, SHOWN)
	if seen then
		return false, `Showing the world rig left its attire hidden: {seen}`
	end

	return true, nil
end
