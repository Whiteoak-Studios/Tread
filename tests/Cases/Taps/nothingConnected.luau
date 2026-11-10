--[[
    With nothing connected the taps cost a flag read each: a relay run that
    sends, restyles and withholds touches no member of Taps but its flags
    and makes nothing on the heap, and neither does the server's tick
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Rig = require("../../Fixtures/Server/Rig")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local TAPS: string = "ReplicatedStorage.Packages.Tread.Server.Taps"
local BODIES: number = 20
local VIEWERS: number = 10
local WARM: number = 200 -- Runs before the heap is read, so every pooled buffer and list has been made
local MEASURED: number = 200
local RUNS: number = 20
local LOOKS: { { [string]: any } } = { { head = 1 }, { head = 2, torso = 3 } }
local HELDS: { { [string]: any } } = { { item = 4 }, { item = 5, skin = 6 } }
local COMMANDS: { [number]: any } = {} -- Each body's last command, none, one table for every run

--[[
    Taps as nothing connected leaves it, its flags all false, whose every
    other member but start errors naming itself, so any call past a flag
    fails the case
--]]

local function stub(): any
	local flags: { [string]: boolean } = { observing = false, commanding = false, reliable = false }

	return setmetatable({
		start = function (_: any) end,
	}, {
		__index = function (_: any, key: string): any
			if flags[key] ~= nil then
				return flags[key]
			end

			error(`Taps.{key} was reached with nothing connected`)
		end,
	})
end

--[[
    One relay run of the bodies in states, each moved, its look and held
    item changed on every other run, and the taps' frames made as the relay
    stage makes them while a sink observes
--]]

local function step(Relay: any, Taps: any, run: number, viewers: { any }, states: { [number]: any }, slots: { number })
	for index: number, slot: number in slots do
		local state: any = states[slot]
		state.position = vector.create(index * 5, 0, (run % 7) * 0.5)
		state.held = HELDS[run % 2 + 1]

		if index == 1 then
			Relay.setLook(slot, LOOKS[run % 2 + 1])
		end
	end

	Relay.run(run, viewers, states, COMMANDS)

	if Taps.observing then
		Taps.finish(run)
	end
end

return function (): (boolean, string | nil)
	-- 1) The relay alone, its taps real and nothing connected, makes nothing on the heap
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local fixtures: any = globals.game:GetService("ServerScriptService").Fixtures
	local Example: any = globals.require(fixtures.Config.Example)
	local Fields: any = globals.require(tread.Codec.Fields)
	local Relay: any = globals.require(tread.Server.Relay)
	local Slots: any = globals.require(tread.Server.Slots)
	local State: any = globals.require(tread.Step.State)
	local Taps: any = globals.require(tread.Server.Taps)

	local shared: any = Example.shared()
	local server: any = Example.server()
	local layout: any = Fields.compile(shared.fields)
	Slots.start(server.slots.reserve)

	local function nothing(_: any, _: any) end

	Relay.start({ shared = shared, server = server, layout = layout }, nothing, nothing, function (_: any): number
		return 0
	end, function (_: any, slot: number): boolean
		return slot % 3 == 0
	end)

	local states: { [number]: any } = {}
	local slots: { number } = {}
	for _ = 1, BODIES do
		local slot: number = Slots.take("Player")
		Slots.setEntry(slot, { kind = "Player", rig = "A" })

		local state: any = State.new()
		state.mode = "Ground"
		states[slot] = state
		table.insert(slots, slot)
	end

	local viewers: { any } = {}
	for index: number = 1, VIEWERS do
		local key: any = { Name = `Viewer{index}` }
		table.insert(viewers, {
			key = key,
			slot = nil,
			position = vector.create(index, 0, 0),
			acknowledged = 0,
			received = 0,
			target = nil,
		})
	end

	-- A watcher, so the withheld block is built too
	viewers[VIEWERS].target = viewers[1].key

	Taps.start({
		layout = layout,
		wearing = Relay.wearing,

		reason = function (_: any, _: number): string
			return "Clear"
		end,
	})

	for run: number = 1, WARM do
		step(Relay, Taps, run, viewers, states, slots)
	end

	local before: number = collectgarbage("count")
	for run: number = WARM + 1, WARM + MEASURED do
		step(Relay, Taps, run, viewers, states, slots)
	end
	local changed: number = collectgarbage("count") - before

	if Taps.observing or Taps.commanding or Taps.reliable then
		return false, "A tap's flag was set with nothing connected"
	elseif changed ~= 0 then
		return false, `{MEASURED} relay runs with nothing connected changed the heap's count by {changed} KB`
	end

	-- The same runs with a sink and a change callback connected do make frames and changes, so the read can tell
	local stopSink: () -> () = Taps.observe(viewers[1].key, nothing)
	local stopChanges: () -> () = Taps.onReliable(nothing)

	before = collectgarbage("count")
	for run: number = WARM + MEASURED + 1, WARM + 2 * MEASURED do
		step(Relay, Taps, run, viewers, states, slots)
	end
	changed = collectgarbage("count") - before

	stopSink()
	stopChanges()
	if changed == 0 then
		return false, "The runs with taps connected left the heap's count as it was, so the read tells nothing"
	end

	-- 2) The relay harness reaches no member of Taps but its flags
	local Harness: any = Environment.load(HARNESS, { [TAPS] = stub() })
	local harness: any = Harness.new()
	local target: any = harness:viewer("Target")
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = vector.create(4000, 0, 0)

	local culled: number = harness:spawn("Player", vector.create(20, 0, 0))
	local seen: number = harness:spawn("Player", vector.create(-20, 0, 0))
	harness:hide(target, culled, true)
	harness:watch(moderator, target)

	for run: number = 1, RUNS do
		Harness.Relay.setLook(seen, LOOKS[run % 2 + 1])
		harness.states[culled].held = HELDS[run % 2 + 1]
		harness.states[seen].position = vector.create(-20, 0, run)

		local ran: boolean, failure: any = pcall(harness.run, harness)
		if not ran then
			return false, `The relay harness's run {run} reached Taps: {failure}`
		end
	end

	-- 3) The server's tick, its looks, held items, deaths, teleports and leaves reach no member of Taps but its flags
	local rig: Rig.Rig = Rig.new(nil, { [TAPS] = stub() })
	local handle: any = rig:start()
	local bot: any = rig.mock:addBot("Bot")
	local character: any = handle:create(bot, rig:at(0, 0))
	local other: any = handle:create(rig.mock:addBot("Other"), rig:at(6, 0))
	handle:createNpc(rig:at(0, 8))

	local ran: boolean, failure: any = pcall(function ()
		character:setOutfit(LOOKS[1])
		character:setHeld(HELDS[1])
		rig:tick(4)

		character:teleport(rig:at(-10, 5))
		rig:tick(2)

		local body: any = other:die(roblox.Vector3.new(1, 0, 0))
		other:destroy()
		body:destroy()
		rig:tick(2)

		rig.mock:removeBot(bot)
		rig:tick(2)
		character:destroy()
	end)

	if not ran then
		return false, `The server reached Taps with nothing connected: {failure}`
	end

	return true, nil
end
