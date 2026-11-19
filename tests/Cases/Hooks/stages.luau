--[[
    Each Move runs through the stages in the order they were added, a stage
    that keeps it stops it from the rest and from the server, a Move a stage
    sends goes through the later stages alone, and with none left Moves go out
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local OWN: number = 9
local TICK: number = 100

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	rig.handshake()
	rig.own(OWN, 1)
	rig.owner(rig.body(vector.create(0, 50, 0), 0, TICK))
	rig.frames(2)
	rig.step()

	local mounted: Kit.Mounted = Kit.mount(rig)
	local Hooks: any = mounted.require(mounted.exploits.Hooks)
	local seen: { string } = {}
	local keeps: boolean = false

	local function first(_: any): boolean
		table.insert(seen, "first")

		return not keeps
	end

	local function second(_: any): boolean
		table.insert(seen, "second")

		return true
	end

	local removeFirst: () -> () = Hooks.add(first)
	local removeSecond: () -> () = Hooks.add(second)
	local before: number = #rig.moves

	rig.frames(1)
	rig.step()
	if table.concat(seen, ",") ~= "first,second" or #rig.moves ~= before + 1 then
		return false, `A Move ran through {table.concat(seen, ",")} and reached the server {#rig.moves - before} times`
	end

	table.clear(seen)
	keeps = true
	rig.frames(1)
	rig.step()
	if table.concat(seen, ",") ~= "first" or #rig.moves ~= before + 1 then
		return false, "A Move the first stage kept still reached the second stage or the server"
	end

	-- A Move the first stage sends goes through the second alone
	table.clear(seen)
	Hooks.send(first, { command = 0, acknowledged = 0, received = 0, delay = 0, commands = {} })
	Hooks.flush()
	rig.step()
	if table.concat(seen, ",") ~= "second" or #rig.moves ~= before + 2 then
		return false, `A Move the first stage sent ran through "{table.concat(seen, ",")}", not the second alone`
	end

	removeFirst()
	removeSecond()
	table.clear(seen)
	rig.frames(1)
	rig.step()
	if #seen ~= 0 or #rig.moves ~= before + 3 then
		return false, "With every stage taken out, a Move didn't go straight to the server"
	end

	local sent: boolean =
		pcall(Hooks.send, first, { command = 0, acknowledged = 0, received = 0, delay = 0, commands = {} })
	if sent then
		return false, "A Move from a stage no longer in the send was taken"
	end

	return true, nil
end
