--[[
    Every tap frame carries its own relay tick's OwnerState, across deferred
    ticks and across a deferred tick whose run the next tick skips, which
    gives no frame, though its OwnerStates went and an observed bot then died
--]]

--!strict
local SplitSide = require("../../Fixtures/Server/SplitSide")

local DEFERRING: number = SplitSide.CALM + 3 -- The deferred tick whose run the next is owed over
local NAMES: { string } = { "Client", "Seen", "Hidden", "Moderator" }
local AFTER: number = 6 -- Heartbeats run once the owed tick has finished, two ticks' worth

type Driven = SplitSide.Driven

return function (): (boolean, string | nil)
	local driven: Driven = SplitSide.new({ split = true, workers = true })
	local side: any = driven.side

	SplitSide.ticks(driven, DEFERRING - 1)

	-- The deferring tick's own Heartbeat; then, before its rest, a bot it sent an OwnerState dies; then a Heartbeat of
	-- a whole tick, which owes the next tick, so the rest is skipped and the next runs whole
	SplitSide.beat(driven, SplitSide.THIRD)
	side.characters.Seen:die()
	SplitSide.beat(driven, 1)

	for _ = 1, AFTER do
		SplitSide.beat(driven, SplitSide.THIRD)
	end

	for _, name: string in NAMES do
		local framed: { [number]: boolean } = {}

		for _, data: string in side.frames[name] do
			local frame: any = side.Tap.read(buffer.fromstring(data))
			framed[frame.tick] = true

			if frame.owner and buffer.readu16(frame.owner.data, 2) ~= frame.tick then
				local carried: number = buffer.readu16(frame.owner.data, 2)
				return false, `{name}'s frame for tick {frame.tick} carried tick {carried}'s OwnerState`
			elseif frame.owner == nil and name ~= "Seen" then
				return false, `{name}'s frame for tick {frame.tick} carried no OwnerState`
			elseif frame.owner and name == "Seen" and frame.tick > DEFERRING then
				return false, `Seen's frame for tick {frame.tick}, after it died, carried an OwnerState`
			end
		end

		-- Every deferred tick gives a frame, the skipped one none, and the owed one its own
		for tick: number = SplitSide.CALM, DEFERRING + 1 do
			local had: boolean = framed[tick] == true
			if had ~= (tick ~= DEFERRING) then
				return false, `{name}'s frames gave tick {tick} a frame {had}`
			end
		end
	end

	local read: any = side.server:stats()
	if read.relaySkipped ~= 1 then
		return false, `Stats gave {read.relaySkipped} relay ticks skipped, not the deferring one`
	end

	return true, nil
end
