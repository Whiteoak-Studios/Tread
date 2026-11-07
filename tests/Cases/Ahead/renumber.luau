--[[
    While on, each Move's commands are numbered the kit's ticks past the
    client's clock, a Move with no commands keeping its 0, and off the
    client's own numbers go out again, which the switch never changed
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local OWN: number = 9
local TICK: number = 100
local WRAP: number = 2 ^ 16

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	rig.handshake()
	rig.own(OWN, 1)
	rig.owner(rig.body(vector.create(0, 50, 0), 0, TICK))
	rig.frames(2)
	rig.step()

	local last: number = rig.moves[#rig.moves].command
	local mounted: Kit.Mounted = Kit.mount(rig)
	local ticks: number = mounted.require(mounted.config).exploits.ahead
	local switch: (on: boolean) -> () =
		mounted.require(mounted.exploits.Ahead).start({ client = rig.handle, shared = rig.shared })

	switch(true)
	rig.frames(1)
	rig.step()
	local renumbered: any = rig.moves[#rig.moves]
	if renumbered.command ~= (last + 1 + ticks) % WRAP then
		return false, `On, the Move carries command {renumbered.command}, not {last + 1} moved {ticks} ahead`
	elseif renumbered.count == 0 then
		return false, "On, the Move carried no commands"
	end

	-- A Move with no commands, as the client sends while its clock holds back
	local Network: any = rig.globals.require(rig.tread.Network.Client)
	Network.Move.fire(0, 0, 0, 0, {})
	Network.flush()
	rig.step()
	local empty: any = rig.moves[#rig.moves]
	if empty.count ~= 0 or empty.command ~= 0 then
		return false, `A Move with no commands went out numbered {empty.command} with {empty.count} commands`
	end

	switch(false)
	rig.frames(1)
	rig.step()
	if rig.moves[#rig.moves].command ~= last + 2 then
		return false, `Off, the Move carries command {rig.moves[#rig.moves].command}, not the client's own {last + 2}`
	end

	return true, nil
end
