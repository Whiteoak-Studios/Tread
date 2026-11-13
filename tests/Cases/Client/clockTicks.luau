--[[
    The client's clock starts at the handshake's tick, runs on at the
    simulation rate while there is no body, follows the owner's drawn tick
    unwrapped once one starts, across the u16 wrap, and runs on again once
    it ends; each frame sets the world's clock to its floor, so a step's
    u16 tick unwraps to the server's, and with no body the world's tick too
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local SLOT: number = 5
local GENERATION: number = 1
local WIRE: number = 2 ^ 16
local SERVER_TICK: number = 3 * WIRE - 3 -- Three before a u16 wrap, so the clock crosses it
local SPAWN_TICK: number = (SERVER_TICK + 2) % WIRE -- The owner's first OwnerState's, the tick before the wrap
local TICK: number = 1 / 20 -- Seconds a simulation tick takes at Frontier Zero's rate

-- Why the clock, the world's clock or the world's tick isn't what a frame should leave, or nil when each is
local function off(handle: any, label: string, ticks: number, tick: number?): string?
	local world: any = handle._world

	if handle._ticks ~= ticks then
		return `{label}, the clock stood at {handle._ticks}, not {ticks}`
	elseif world.clock ~= math.floor(ticks) then
		return `{label}, the world's clock stood at {world.clock}, not the clock's floor {math.floor(ticks)}`
	elseif tick ~= nil and world.tick ~= tick then
		return `{label}, the world's tick stood at {world.tick}, not {tick}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local world: any = handle._world
	local need: any = rig.globals.require
	local Config: any = need(rig.tread.Config)
	local Platforms: any = need(rig.tread.Step.Platforms)

	-- 1) Before the handshake there is no clock, and frames leave the world's alone
	rig.frames(2)
	if handle._ticks ~= nil or world.clock ~= 0 then
		return false, `Before the handshake the clock stood at {handle._ticks} and the world's at {world.clock}`
	end

	rig.send("Shared", Config.hash(rig.shared), SERVER_TICK)
	local problem: string? = off(handle, "At the handshake", SERVER_TICK, nil)
	if problem then
		return false, problem
	end

	-- 2) With no body it runs on at the simulation rate, the world's tick following its floor
	rig.frames(1, TICK / 2)
	problem = off(handle, "Half a tick on with no body", SERVER_TICK + 0.5, SERVER_TICK % WIRE)
	if problem then
		return false, problem
	end

	rig.frames(1)
	problem = off(handle, "A tick later with no body", SERVER_TICK + 1.5, (SERVER_TICK + 1) % WIRE)
	if problem then
		return false, problem
	end

	-- 3) A body's drawn tick takes over, unwrapped against the clock, across the wrap
	rig.own(SLOT, GENERATION)
	rig.owner(rig.body(vector.create(0, 50, 0), 0, SPAWN_TICK))

	rig.frames(1)
	problem = off(handle, "On the body's first tick", SERVER_TICK + 2, nil)
	if problem then
		return false, problem
	end

	rig.frames(1, TICK / 2)
	problem = off(handle, "Half a tick into the body's drawing", SERVER_TICK + 2.5, nil)
	if problem then
		return false, problem
	end

	rig.frames(1)
	problem = off(handle, "Past the u16 wrap", SERVER_TICK + 3.5, nil)
	if problem then
		return false, problem
	end

	-- The step the newest command ran on unwraps to the server's own tick for it
	if Platforms.tick(world) ~= SERVER_TICK + 4 then
		return false, `The newest predicted step's tick unwrapped to {Platforms.tick(world)}, not {SERVER_TICK + 4}`
	end

	-- 4) The body ended, the clock runs on from where it was drawn
	rig.slots({ { slot = SLOT, generation = GENERATION, rig = nil } })
	rig.frames(1)
	problem = off(handle, "A tick after the body ended", SERVER_TICK + 4.5, (SERVER_TICK + 4) % WIRE)
	if problem then
		return false, problem
	end

	return true, nil
end
