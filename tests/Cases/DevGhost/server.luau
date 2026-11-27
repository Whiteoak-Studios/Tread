--[[
    The ghosts' frame listener is held only while someone asks, and each
    send carries the clock read before the Heartbeat that ran its tick and
    the relay tick, wrapping at a u16; nothing goes while a live run runs,
    nor on the first frame after one, after a connect or after a reconnect
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevGhost/Harness")

local SLOT: number = 3 -- The watched character's
local START: number = 1790000000 -- The server's clock at the case's first frame, seconds
local FRAME: number = 1 / 60 -- Seconds between the case's frames
local FIRST_RAN: number = 31 -- The ticks run once the first tick goes, its relay tick 10 at three ticks a relay tick
local FIRST_TICK: number = 10
local WRAP: number = 2 ^ 16
local WRAPPED_RAN: number = 3 * WRAP + 7 -- Its relay tick 65,538, which wraps to 2
local WRAPPED_TICK: number = 2
local LIVE: string = "BenchStep" -- A live run's name, as the live panel gives it
local LABEL: string = "0 relay workers"
local LONG_LABEL: string = string.rep("w", 40) -- Past the event's 32 bytes
local ROOT: any = roblox.Vector3.new(120, 4, -300) -- Inside the wire bounds
local VELOCITY: any = roblox.Vector3.new(16, 0, 0)

local function player(name: string): any
	local made: any = roblox.Instance.new("Player")
	made.Name = name

	return made
end

return function (): (boolean, string | nil)
	local rig: Harness.Rig = Harness.load()
	local asker: any = player("Asker")
	local other: any = player("Other")

	rig.character(player("Owner"), SLOT, ROOT, VELOCITY)
	rig.sentTo[asker] = { [SLOT] = true }
	rig.sentTo[other] = { [SLOT] = true }
	rig.state.label = LABEL

	local now: number = START
	local stamp: number = START -- The clock at the frame before the newest

	-- A frame after the Heartbeat before it ran ticks ticks, the server's clock a frame on
	local function frame(ticks: number)
		rig.state.ran += ticks
		stamp = now
		now += FRAME
		rig.frame(now)
	end

	-- 1) Bound at its config's rate, and with no ask nothing listens to the frames
	local rate: any = rig.rates.ghostAsk
	if not rate or rate.perSecond ~= rig.config.rate.perSecond or rate.burst ~= rig.config.rate.burst then
		return false, "ghostAsk was not bound at the rate dev/Server/Config/Ghost.luau gives"
	elseif rig.listening() ~= 0 then
		return false, `{rig.listening()} frame listeners were held before anyone asked`
	end

	-- 2) The first ask connects, its first frame stamps nothing, and the next sends the tick between them
	rig.state.ran = FIRST_RAN - 1
	rig.ask(asker, { SLOT })
	if rig.listening() ~= 1 then
		return false, `An ask left {rig.listening()} frame listeners, not 1`
	end

	rig.frame(now)
	frame(1)

	local first: Harness.Sent? = rig.sent[1]
	if #rig.sent ~= 1 or not first then
		return false, `The frames after the first ask sent {#rig.sent} times, not once`
	elseif first.time ~= stamp then
		return false, `The first send was stamped {first.time}, not {stamp}, the clock before its tick's Heartbeat`
	elseif first.tick ~= FIRST_TICK or first.player ~= asker or first.label ~= LABEL then
		return false, `The first send went to {first.player} for tick {first.tick} labeled {first.label}`
	end

	frame(0)
	if #rig.sent ~= 1 then
		return false, "A frame with no tick before it sent"
	end

	-- 3) The relay tick wraps at a u16, and the label is cut to the event's bound
	rig.state.label = LONG_LABEL
	rig.state.ran = WRAPPED_RAN
	frame(0)

	local wrapped: Harness.Sent? = rig.sent[2]
	if not wrapped or wrapped.tick ~= WRAPPED_TICK or wrapped.time ~= stamp then
		return false, `{WRAPPED_RAN} ticks were sent as tick {wrapped and wrapped.tick}, not {WRAPPED_TICK}`
	elseif wrapped.label ~= string.sub(LONG_LABEL, 1, rig.config.labelBytes) then
		return false, `A {#LONG_LABEL}-byte label went as {#wrapped.label} bytes`
	end

	rig.state.label = LABEL

	-- 4) Nothing goes while a live run runs, nor on the first frame after it
	rig.state.live = LIVE
	frame(1)
	frame(1)
	rig.state.live = nil
	frame(1)
	if #rig.sent ~= 2 then
		return false, `{#rig.sent - 2} sends went during a live run or on the frame after it`
	end

	frame(1)
	local resumed: Harness.Sent? = rig.sent[3]
	if #rig.sent ~= 3 or not resumed or resumed.time ~= stamp then
		return false, "The ghosts did not resume on the second frame after the live run, stamped with the first's clock"
	end

	-- 5) A second asker shares the one listener, and a leave stops the leaver's sends alone
	rig.ask(other, { SLOT })
	frame(1)
	if rig.listening() ~= 1 or #rig.sent ~= 5 then
		return false, `Two askers held {rig.listening()} listeners and a tick sent {#rig.sent - 3} times`
	end

	rig.leave(asker)
	frame(1)
	local left: Harness.Sent? = rig.sent[6]
	if rig.listening() ~= 1 or #rig.sent ~= 6 or not left or left.player ~= other then
		return false, "After one asker left, the next tick did not go to the other alone"
	end

	-- 6) The last asker's empty ask disconnects, and a new ask's first frame stamps nothing
	rig.ask(other, {})
	if rig.listening() ~= 0 then
		return false, `An empty ask from the last asker left {rig.listening()} frame listeners`
	end

	frame(1)
	rig.ask(other, { SLOT })
	frame(1)
	if #rig.sent ~= 6 then
		return false, `{#rig.sent - 6} sends went with nobody asking or on a reconnect's first frame`
	end

	frame(1)
	local again: Harness.Sent? = rig.sent[7]
	if #rig.sent ~= 7 or not again or again.time ~= stamp then
		return false, "The second frame after a reconnect sent no tick stamped with the first's clock"
	end

	-- 7) The last asker leaving disconnects
	rig.leave(other)
	if rig.listening() ~= 0 then
		return false, `The last asker's leave left {rig.listening()} frame listeners`
	end

	return true, nil
end
