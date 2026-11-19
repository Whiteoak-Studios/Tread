--[[
    A new look and a held item on the local player's own slot reach its
    first-person copy too, the copy dressed as the copy, and what the hooks
    add stays hidden on the world rig and takes its region on the copy.
    Another slot's look and item reach only its own rig
--]]

--!strict
local Environment = require("../../Environment")
local Owner = require("../../Fixtures/Rigs/Owner")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local OWN: number = 9
local OTHER: number = 3
local HIDDEN: number = 1
local SHOWN: number = 0

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	-- The fixture's hooks, which write each call down, with a helmet, a vest and a held item welded on as a game's do
	local calls: { any } = {}
	local settings: any = Rig.settings(calls)
	local dress: (Model, any, boolean) -> () = settings.dress
	local undress: (Model) -> () = settings.undress
	local hold: (Model, any) -> () = settings.hold

	settings.dress = function (rig: Model, outfit: any, copy: boolean)
		dress(rig, outfit, copy)
		if outfit.helmet then
			Owner.wear(rig, "Helmet", Owner.find(rig, "Head"), "Weld")
			Owner.wear(rig, "Vest", Owner.find(rig, "UpperTorso"), "WeldConstraint")
		end
	end

	settings.undress = function (rig: Model)
		undress(rig)
		for _, name: string in { "Helmet", "Vest" } do
			local worn: Instance? = rig:FindFirstChild(name)
			if worn then
				worn:Destroy()
			end
		end
	end

	settings.hold = function (rig: Model, held: any)
		hold(rig, held)
		local carried: Instance? = rig:FindFirstChild("Held")
		if carried then
			carried:Destroy()
		end
		if held then
			Owner.wear(rig, "Held", Owner.find(rig, "RightHand"), "Motor6D")
		end
	end

	local rigs = Rigs.new(settings, Rig.drawDistance, Rig.collision())
	local world: any = rigs:checkout(OWN, {}, true)
	local copy: any = calls[2].rig
	local other: any = rigs:checkout(OTHER, {})

	-- A new look: both rigs undressed and dressed, the copy as the copy
	table.clear(calls)
	local outfit: { [string]: any } = { helmet = 1 }
	rigs:dress(OWN, outfit)

	local order: { string } = {}
	for _, call: any in calls do
		local who: string = call.rig == world and "world" or call.rig == copy and "copy" or "other"
		table.insert(order, `{call.hook} {who} {call.copy}`)
	end
	local got: string = table.concat(order, ", ")
	local expected: string = "undress world nil, dress world false, undress copy nil, dress copy true"
	if got ~= expected then
		return false, `The own slot's new look made {got}, not {expected}`
	end

	local worldHidden: string? = Owner.all(world, HIDDEN)
	if worldHidden then
		return false, `The world rig's new attire showed on this screen: {worldHidden}`
	elseif Owner.level(copy, "Helmet") ~= HIDDEN or Owner.level(copy, "Vest") ~= SHOWN then
		return false, "The copy's helmet didn't hide with its head, or its vest hid"
	end

	-- A held item: both rigs, the copy's in its hand, shown with the arms
	table.clear(calls)
	local held: { [string]: any } = { item = 7 }
	rigs:hold(OWN, held)

	if #calls ~= 2 or calls[1].rig ~= world or calls[2].rig ~= copy or calls[2].held ~= held then
		return false, `The own slot's held item made {#calls} hook calls, not one on each rig`
	elseif Owner.level(world, "Held") ~= HIDDEN then
		return false, "The world rig's held item showed on this screen"
	elseif Owner.level(copy, "Held") ~= SHOWN then
		return false, "The copy's held item was hidden while its arms show"
	end

	rigs:show("arms", false)
	if Owner.level(copy, "Held") ~= HIDDEN or Owner.level(copy, "Vest") ~= SHOWN then
		return false, "Hiding the arms didn't hide the copy's held item, or hid its vest"
	end
	rigs:show("chest", false)
	if Owner.level(copy, "Vest") ~= HIDDEN then
		return false, "Hiding the chest didn't hide the copy's vest"
	end

	-- Another slot's look and item reach its rig alone, and nothing on it hides
	table.clear(calls)
	rigs:dress(OTHER, outfit)
	rigs:hold(OTHER, held)

	for _, call: any in calls do
		if call.rig ~= other then
			return false, `Another slot's {call.hook} reached a rig of the local player's`
		end
	end

	if #calls ~= 3 then
		return false, `Another slot's look and item made {#calls} hook calls, not undress, dress and hold`
	elseif Owner.all(other, SHOWN) ~= nil then
		return false, "Another slot's attire was hidden on this screen"
	end

	rigs:destroy()

	return true, nil
end
