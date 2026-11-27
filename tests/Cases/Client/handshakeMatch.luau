--[[
    Until the server's hash of its shared table arrives, the client reads no
    OwnerState and draws no character; once it matches the client's own, the
    next ones start the body and draw the character, and nobody is kicked
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local OWN: number = 9
local OTHER: number = 3
local GENERATION: number = 1
local TICK: number = 50

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local spawned: { any } = {}

	handle:onSpawned(function (slot: any, _: any)
		table.insert(spawned, slot)
	end)

	local at: vector = vector.create(0, 50, 0)
	rig.own(OWN, GENERATION)
	rig.slots({ { slot = OTHER, generation = GENERATION, rig = "A" } })

	local reveal: { [string]: any } = {
		tick = TICK,
		reveals = { { slot = OTHER, generation = GENERATION, kind = "Npc" } },
		records = { { slot = OTHER, generation = GENERATION, position = vector.create(4, 5, 6) } },
	}

	-- Before the handshake both are dropped
	rig.owner(rig.body(at, 0, TICK))
	rig.relay(reveal)

	if handle:getState() ~= nil then
		return false, "An OwnerState before the server's handshake started a body"
	elseif #spawned ~= 0 then
		return false, "A reveal before the server's handshake drew a character"
	end

	rig.handshake()
	rig.owner(rig.body(at, 0, TICK + 1))
	reveal.tick = TICK + 1
	rig.relay(reveal)

	if handle:getState() == nil then
		return false, "An OwnerState after a matching handshake started no body"
	elseif #spawned ~= 1 or spawned[1].id ~= OTHER then
		return false, `A reveal after a matching handshake drew {#spawned} characters, not slot {OTHER}`
	elseif rig.kicked() ~= nil then
		return false, `A matching handshake kicked the player: {rig.kicked()}`
	end

	return true, nil
end
