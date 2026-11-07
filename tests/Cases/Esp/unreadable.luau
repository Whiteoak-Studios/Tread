--[[
    A relay message the ESP can't read is let through, and the block after
    it in the same packet still reaches both the ESP and Tread's client, so
    the ESP's hook never stops what Volt delivers
--]]

--!strict
local Rig = require("../../Fixtures/Esp/Rig")

local SLOT: number = 3
local TICK: number = 50
local FRAMES: number = 3
local SHORT: number = 3 -- Bytes, too few for a relay block's header

return function (): (boolean, string | nil)
	local rig: any = Rig.new()
	local switch: (on: boolean) -> () = rig.startEsp()
	switch(true)
	rig.slots({ { slot = SLOT, generation = 1, rig = "A" } })

	-- The block's bytes as the client handle's rig writes them, kept rather than sent
	local send: any = rig.send
	local block: buffer? = nil
	rig.send = function (_: string, data: buffer)
		block = data
	end

	rig.relay({
		tick = TICK,
		reveals = { { slot = SLOT, generation = 1, kind = "Npc" } },
		records = { { slot = SLOT, generation = 1, position = vector.create(2, 0, 2), word = rig.word({}) } },
	})
	rig.send = send

	-- Both in one flush, so one packet, the unreadable one first
	local player: any = rig.mock.players[1]
	rig.server.Relay.fire(player, buffer.create(SHORT))
	rig.server.Relay.fire(player, block)
	rig.server.flush()
	rig.step()
	rig.frames(FRAMES)

	if not rig.slot(SLOT) then
		return false, "The block after an unreadable one drew no box"
	elseif #rig.pool.of("checkout") ~= 1 then
		return false, "Tread's client never drew the block after the unreadable one"
	end

	switch(false)

	return true, nil
end
