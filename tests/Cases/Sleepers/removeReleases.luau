--[[
    Removing a sleeper or a body releases its slot, which the slot table's
    change callbacks hear, and forgets it, leaving every other one be
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local BED: vector = vector.create(1, 2, 3)
local GRAVE: vector = vector.create(-1, 2, -3)
local KEPT: vector = vector.create(9, 2, 9)

type Change = { slot: number, previous: string?, current: string? }

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Example: any = globals.require(globals.game:GetService("ServerScriptService").Fixtures.Config.Example)
	local History: any = globals.require(tread.Server.History)
	local Sleepers: any = globals.require(tread.Server.Sleepers)
	local Slots: any = globals.require(tread.Server.Slots)
	local World: any = globals.require(tread.Step.World)

	local shared: any = Example.shared()
	local server: any = Example.server()
	Slots.start(server.slots.reserve)
	History.start(shared, server)
	Sleepers.start(shared, World.new(shared.step, shared.rates.simulation, {}, shared.water, shared.rules, true))

	local sleeper: number = Sleepers.create("Sleeper", BED, 0)
	local body: number = Sleepers.create("Body", GRAVE, 0)
	local kept: number = Sleepers.create("Sleeper", KEPT, 0)

	local changes: { Change } = {}
	local disconnect: () -> () = Slots.onChange(function (slot: number, _: number, previous: any, current: any)
		table.insert(
			changes,
			{ slot = slot, previous = previous and previous.kind, current = current and current.kind }
		)
	end)

	Sleepers.remove(sleeper)
	Sleepers.remove(body)
	disconnect()

	-- 1) Both slots are free, and the change callbacks heard each go
	if Slots.count("Sleeper") ~= 1 or Slots.count("Body") ~= 0 then
		return false,
			`After the removes the slot table held {Slots.count("Sleeper")} sleepers, {Slots.count("Body")} bodies`
	elseif select(2, Slots.get(sleeper)) ~= nil or select(2, Slots.get(body)) ~= nil then
		return false, "A removed slot kept its entry"
	elseif #changes ~= 2 then
		return false, `The change callbacks heard {#changes} changes, not the two releases`
	elseif changes[1].slot ~= sleeper or changes[1].previous ~= "Sleeper" or changes[1].current ~= nil then
		return false, `The first change was slot {changes[1].slot} from {changes[1].previous}, not the sleeper freed`
	elseif changes[2].slot ~= body or changes[2].previous ~= "Body" or changes[2].current ~= nil then
		return false, `The second change was slot {changes[2].slot} from {changes[2].previous}, not the body freed`
	end

	-- 2) The removed are forgotten, and each slot was released once
	for _, slot: number in { sleeper, body } do
		local again: boolean, reason: any = pcall(Sleepers.remove, slot)
		local released: boolean, releaseReason: any = pcall(Slots.release, slot)

		if again or not string.find(`{reason}`, "holds neither", 1, true) then
			return false, `Slot {slot} could be removed twice: {reason}`
		elseif released or not string.find(`{releaseReason}`, "takes a taken slot", 1, true) then
			return false, `Slot {slot} was still taken after its remove: {releaseReason}`
		end
	end

	-- 3) The sleeper left is held as it was
	if Sleepers.sampleAt(kept, 0).position ~= KEPT or select(2, Slots.get(kept)).kind ~= "Sleeper" then
		return false, "Removing two others changed the sleeper left"
	end

	return true, nil
end
