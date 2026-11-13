--[[
    Each frame places a platform's copy where its path puts it at the
    drawn tick: nowhere before the handshake names the server's tick, then
    at the clock while there is no body, at the owner's drawn tick once its
    body starts, and at a spectated target's drawn feed tick while the
    client views it, until the spectate ends
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Handle = require("../../Fixtures/Client/Handle")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"

local OWN: number = 9
local TARGET: number = 14
local GENERATION: number = 1
local LIFT: number = 2
local SERVER_TICK: number = 1000
local SPAWN_TICK: number = SERVER_TICK + 3 -- The owner's first OwnerState's tick
local FEED_TICK: number = SERVER_TICK + 1 -- The target's first feed's, behind the owner's as a feed runs
local VIEW_TICK: number = 60 -- The relay tick the target's view starts at
local END_TICK: number = 70
local RISE: number = 0.125 -- Studs the lift rises a tick
local TICK: number = 1 / 20 -- Seconds a simulation tick takes at Frontier Zero's rate
local CLOSE: number = 1e-4 -- Studs a copy may stand from the path's place, past a fraction's float rounding

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local world: any = handle._world
	local need: any = rig.globals.require
	local tread: any = rig.tread

	local ClientPlatforms: any = need(tread.Client.Platforms)
	local Config: any = need(tread.Config)
	local Constants: any = need(tread.Constants)
	local Feed: any = need(tread.Codec.Feed)
	local Fields: any = need(tread.Codec.Fields)
	local OwnerState: any = need(tread.Codec.OwnerState)
	local Platforms: any = need(tread.Step.Platforms)
	local Record: any = need(tread.Codec.Record)

	local shared: any = rig.shared
	local layout: any = Fields.compile(shared.fields)
	local limits: any = { lean = shared.step.lean, headCone = shared.step.headCone }

	-- The pool's stand-in has no watch, which a spectated target's rig is handed to
	handle._rigs.watch = function (_: any, _: number?) end

	-- Why the copy doesn't stand where the path puts it at a tick, or nil when it does
	local function placed(label: string, tick: number): string?
		local copy: vector? = ClientPlatforms.position(LIFT)
		local wanted: vector = Platforms.at(world, LIFT, tick)

		if copy == nil or vector.magnitude(copy - wanted) > CLOSE then
			return `{label}, the copy stood at {copy}, where the path puts it at tick {tick}, {wanted}`
		end

		return nil
	end

	-- One feed of the target standing at a tick
	local function feed(tick: number)
		local state: any = rig.body(vector.create(10, 0, 0), 0, tick)
		state.mode = "Ground"
		state.grounded = true

		local owner: buffer = buffer.create(Constants.MAX_OWNER_STATE)
		local length: number = OwnerState.write(state, owner, 0, layout, limits)
		local commands: { any } = { { yaw = 0, pitch = 0, headYaw = 0, headPitch = 0 } }

		local scratch: buffer = buffer.create(Constants.MAX_FEED)
		local bytes: number = Feed.write(scratch, owner, 0, length, commands, #commands, limits)
		local data: buffer = buffer.create(bytes)
		buffer.copy(data, 0, scratch, 0, bytes)

		rig.send("Feed", data)
	end

	handle:addPlatform(Riders.lift(LIFT, roblox.Vector3.new(0, 80, 0), SERVER_TICK - 10, RISE))

	-- 1) Before the handshake the copy has no place
	rig.frames(2)
	if ClientPlatforms.position(LIFT) ~= nil then
		return false, "The lift's copy was placed before the handshake named the server's tick"
	end

	-- 2) With no body, at the clock
	rig.send("Shared", Config.hash(shared), SERVER_TICK)
	rig.frames(1, TICK / 2)
	local problem: string? = placed("Half a tick after the handshake", SERVER_TICK + 0.5)
	if problem then
		return false, problem
	end

	rig.frames(1)
	problem = placed("A tick later", SERVER_TICK + 1.5)
	if problem then
		return false, problem
	end

	-- 3) With a body, at the tick it is drawn at
	rig.own(OWN, GENERATION)
	rig.slots({ { slot = TARGET, generation = GENERATION, rig = "A" } })
	rig.owner(rig.body(vector.create(0, 50, 0), 0, SPAWN_TICK))

	rig.frames(1)
	problem = placed("On the body's first tick", SPAWN_TICK)
	if problem then
		return false, problem
	end

	rig.frames(1, TICK / 4)
	problem = placed("A quarter tick into the body's drawing", SPAWN_TICK + 0.25)
	if problem then
		return false, problem
	end

	-- 4) While spectating, at the target's drawn feed tick, between its last two feeds
	rig.send("Spectate", Record.id(TARGET, GENERATION), VIEW_TICK)
	feed(FEED_TICK)
	rig.frames(1)
	problem = placed("On the target's first feed", FEED_TICK)
	if problem then
		return false, problem
	end

	feed(FEED_TICK + 1)
	rig.frames(1, TICK / 2)
	problem = placed("Halfway to the target's second feed", FEED_TICK + 0.5)
	if problem then
		return false, problem
	end

	-- 5) The spectate's end, back at the owner's drawn tick, which ran on with the frames
	rig.send("Spectate", nil, END_TICK)
	rig.frames(1)
	problem = placed("After the spectate's end", SPAWN_TICK + 2.75)
	if problem then
		return false, problem
	end

	return true, nil
end
