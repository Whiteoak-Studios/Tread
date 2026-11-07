--[[
    While on, no Move the client sends reaches the server, each one dropped
    rather than held, and off lets the next ones through with none of the
    frozen ones among them
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local OWN: number = 9
local TICK: number = 100
local FROZEN: number = 4 -- Relay ticks the freeze lasts, a Move each
local AFTER: number = 2 -- Relay ticks after it

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	rig.handshake()
	rig.own(OWN, 1)
	rig.owner(rig.body(vector.create(0, 50, 0), 0, TICK))
	rig.frames(2)
	rig.step()

	local before: number = #rig.moves
	if before == 0 then
		return false, "The client sent no Move to freeze"
	end

	local last: number = rig.moves[before].command
	local mounted: Kit.Mounted = Kit.mount(rig)
	local switch: (on: boolean) -> () =
		mounted.require(mounted.exploits.Freeze).start({ client = rig.handle, shared = rig.shared })

	switch(true)
	rig.frames(FROZEN)
	rig.step()
	if #rig.moves ~= before then
		return false, `{#rig.moves - before} Moves reached the server while the client was frozen`
	end

	switch(false)
	rig.frames(AFTER)
	rig.step()
	if #rig.moves ~= before + AFTER then
		return false, `{#rig.moves - before} Moves reached the server after the freeze, not {AFTER}`
	end

	-- The first one through carries the command made just after the freeze ended, one a relay tick
	local first: number = rig.moves[before + 1].command
	if first ~= last + FROZEN + 1 then
		return false, `The first Move after the freeze carries command {first}, not {last + FROZEN + 1}`
	end

	return true, nil
end
