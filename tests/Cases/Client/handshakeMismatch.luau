--[[
    A server whose shared table hashes otherwise stops the client for good:
    the player is kicked with both hashes, and no OwnerState, reveal, slot
    table or later handshake makes it play or send a Move
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local OWN: number = 9
local OTHER: number = 3
local GENERATION: number = 1
local TICK: number = 50
local FRAMES: number = 10

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local ours: number = rig.globals.require(rig.tread.Config).hash(rig.shared)
	local theirs: number = (ours + 1) % 2 ^ 32

	local spawned: number = 0
	handle:onSpawned(function (_: any, _: any)
		spawned += 1
	end)

	rig.own(OWN, GENERATION)
	rig.handshake(theirs)

	local kicked: string? = rig.kicked()
	if kicked == nil then
		return false, "A handshake with another hash kicked nobody"
	elseif not string.find(kicked, tostring(ours), 1, true) or not string.find(kicked, tostring(theirs), 1, true) then
		return false, `The kick "{kicked}" doesn't name both {ours} and {theirs}`
	end

	-- A matching handshake afterward takes nothing back
	rig.handshake(ours)
	rig.slots({ { slot = OTHER, generation = GENERATION, rig = "A" } })
	rig.owner(rig.body(vector.create(0, 50, 0), 0, TICK))
	rig.relay({
		tick = TICK,
		reveals = { { slot = OTHER, generation = GENERATION, kind = "Npc" } },
		records = { { slot = OTHER, generation = GENERATION, position = vector.create(1, 2, 3) } },
	})
	rig.frames(FRAMES)
	rig.step()

	if handle:getState() ~= nil then
		return false, "A refused client started a body from an OwnerState"
	elseif spawned ~= 0 then
		return false, `A refused client drew {spawned} characters`
	elseif #rig.moves ~= 0 then
		return false, `A refused client sent {#rig.moves} Moves`
	end

	return true, nil
end
