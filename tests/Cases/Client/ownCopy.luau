--[[
    The local player's rig is checked out of the pool as their own, which
    takes out its first-person copy, and another player's is not; the own
    slot's look and held item reach the pool for that slot, and so the copy
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Handle = require("../../Fixtures/Client/Handle")

local OWN: number = 9
local OTHER: number = 3
local GENERATION: number = 1
local TICK: number = 50
local SHIRT: number = 4
local ITEM: number = 2

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	local other: any = roblox.Instance.new("Player")
	other.Name = "Other"

	-- The pool's stand-in drops what its checkout isn't given a place for, so its own flag is written down here
	local owns: { [number]: any } = {}
	local rigs: any = handle._rigs
	local checkout: any = rigs.checkout
	rigs.checkout = function (self: any, slot: number, outfit: any, own: any): any
		owns[slot] = own
		return checkout(self, slot, outfit)
	end

	rig.handshake()
	rig.slots({ { slot = OTHER, generation = GENERATION, rig = "A", player = other } })
	rig.relay({
		tick = TICK,
		reveals = { { slot = OTHER, generation = GENERATION, kind = "Player" } },
		records = { { slot = OTHER, generation = GENERATION, position = vector.create(1, 2, 3) } },
	})

	rig.own(OWN, GENERATION)
	rig.owner(rig.body(vector.create(0, 50, 0), 0, TICK))
	rig.frames(1)

	if owns[OTHER] ~= false then
		return false, `Another player's rig was checked out with own {owns[OTHER]}, not false`
	elseif owns[OWN] ~= true then
		return false, `The local player's rig was checked out with own {owns[OWN]}, not true`
	end

	-- The own slot's look and held item, as the relay gives them
	rig.relay({
		tick = TICK + 1,
		looks = { { slot = OWN, generation = GENERATION, outfit = { shirt = SHIRT }, held = { item = ITEM } } },
	})

	local dresses: { any } = pool.of("dress")
	local holds: { any } = pool.of("hold")
	local dressed: any = dresses[#dresses]
	local held: any = holds[#holds]
	if dressed == nil or dressed.slot ~= OWN or dressed.outfit.shirt ~= SHIRT then
		return false, "The own slot's new look never reached the pool for its slot"
	elseif held == nil or held.slot ~= OWN or held.held == nil or held.held.item ~= ITEM then
		return false, "The own slot's held item never reached the pool for its slot"
	end

	return true, nil
end
