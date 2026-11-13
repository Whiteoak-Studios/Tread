--[[
    A frame carries the looks its viewer stepped since the last frame, two
    for two simulation ticks a relay tick, newest first in the feed's own
    bytes, at most a Move's 8 with the oldest dropped, and none it already
    carried or that came with no OwnerState
--]]

--!strict
local Environment = require("../../Environment")
local Rig = require("../../Fixtures/Server/Rig")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local COMMAND: string = "src/Codec/Command.luau"
local FEED: string = "src/Codec/Feed.luau"
local TAP: string = "src/Codec/Tap.luau"
local SETTLE: number = 4 -- Ticks before the Move, two relay ticks at 40 Hz over 20
local MOVE_DELAY: number = 150
local LOOK_BYTES: number = 6
local MAX_LOOKS: number = 8
local STEPPED: number = 10 -- Looks handed between two frames, two past the cap
local OWNER_ID: number = 4097 -- Slot 1, generation 1
local OWNER_BYTES: number = 46

-- Each command's look from its place: a yaw, a pitch and a head offset inside the 75° cone, all apart
local function look(command: any, index: number)
	command.yaw = 0.5 + index * 0.25
	command.pitch = -0.4 + index * 0.05
	command.headYaw = index * 3
	command.headPitch = -index * 2
end

-- The look list a feed of these commands carries, its count and looks, as the bytes a frame must end with
local function feedLooks(Feed: any, commands: { any }, count: number, limits: any): string
	local data: buffer = buffer.create(2 + count * LOOK_BYTES)
	Feed.write(data, buffer.create(0), 0, 0, commands, count, limits)

	return buffer.readstring(data, 1, 1 + count * LOOK_BYTES)
end

-- The last bytes of a frame, its look list's length of them
local function tail(data: buffer, count: number): string
	local length: number = 1 + count * LOOK_BYTES

	return buffer.readstring(data, buffer.len(data) - length, length)
end

return function (): (boolean, string | nil)
	-- 1) Two simulation ticks a relay tick give a frame two looks, newest first, as the server stepped them
	local rig: Rig.Rig = Rig.new(function (shared: any, _: any)
		shared.rates.simulation = 40
	end)

	local server: any = rig:start()
	local tread: any = rig.tread
	local Command: any = rig:require(tread.Codec.Command)
	local Feed: any = rig:require(tread.Codec.Feed)
	local Fields: any = rig:require(tread.Codec.Fields)
	local Move: any = rig:require(tread.Codec.Move)
	local Tap: any = rig:require(tread.Codec.Tap)

	local client: any = rig:require(tread.Network.Client)
	local player: any = rig.mock.players[1]
	client.flush()
	rig:deliver()

	local frames: { [number]: buffer } = {}
	local stop: () -> () = server:observe(player, function (tick: number, data: buffer)
		frames[tick] = data
	end)

	server:create(player, rig:at(0, 0))
	rig:tick(SETTLE)

	-- The commands for the next two ticks, newest first, in one Move
	local layout: any = Fields.compile(rig.shared.fields)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	local commands: { any } = {}
	for back: number = 0, 1 do
		local command: any = Command.new()
		command.number = SETTLE + 2 - back
		command.fields = { slot = 0, shots = {} }
		look(command, back + 1)
		table.insert(commands, command)
	end

	local move: any = Move.new()
	Move.encode(move, commands, #commands, 0, 0, MOVE_DELAY, layout, limits)
	client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
	client.flush()
	rig:deliver()

	rig:tick(2)
	stop()

	-- The relay tick that follows ticks SETTLE + 1 and SETTLE + 2
	local relayTick: number = (SETTLE + 2) // 2
	local data: buffer? = frames[relayTick]
	local owner: any = data and Tap.read(data, limits).owner
	if not data or not owner then
		return false, `Relay tick {relayTick}'s frame carried no OwnerState`
	elseif #owner.looks ~= 2 then
		return false, `Relay tick {relayTick}'s frame carried {#owner.looks} looks for two stepped commands`
	elseif tail(data, 2) ~= feedLooks(Feed, commands, 2, limits) then
		return false, "The frame's two looks are not the feed's bytes for the commands, newest first"
	end

	-- 2) Past a Move's worth the oldest drop, and a frame never carries a look twice or without its OwnerState
	local Harness: any = Environment.load(HARNESS)
	local Codec: any = Environment.load(COMMAND)
	local HarnessFeed: any = Environment.load(FEED)
	local HarnessTap: any = Environment.load(TAP)

	local harness: any = Harness.new()
	local Taps: any = Harness.Taps
	local viewer: any = harness:viewer("Viewer")
	local key: any = viewer.viewer.key

	local heard: { buffer } = {}
	local stopHarness: () -> () = Taps.observe(key, function (_: number, frame: buffer)
		table.insert(heard, frame)
	end)

	local stepped: { any } = {}
	for index: number = 1, STEPPED do
		local command: any = Codec.new()
		look(command, index)
		table.insert(stepped, command)
		Taps.stepped(key, command)
	end

	local ownerState: buffer = buffer.create(OWNER_BYTES)
	Taps.owner(key, OWNER_ID, ownerState, 0, harness.limits)
	harness:run()

	-- The newest 8 of the 10, newest first
	local newest: { any } = {}
	for index: number = STEPPED, STEPPED - MAX_LOOKS + 1, -1 do
		table.insert(newest, stepped[index])
	end

	local capped: any = HarnessTap.read(heard[1], harness.limits).owner
	if not capped or #capped.looks ~= MAX_LOOKS then
		return false, `{STEPPED} looks between frames gave {capped and #capped.looks} looks, not the cap of {MAX_LOOKS}`
	elseif tail(heard[1], MAX_LOOKS) ~= feedLooks(HarnessFeed, newest, MAX_LOOKS, harness.limits) then
		return false, "The capped frame's looks are not the newest 8 in the feed's bytes, newest first"
	end

	-- A look stepped while no OwnerState comes is dropped with its frame, and the next frame starts with none
	Taps.stepped(key, stepped[1])
	harness:run()

	Taps.owner(key, OWNER_ID, ownerState, 0, harness.limits)
	harness:run()
	stopHarness()

	local bare: any = HarnessTap.read(heard[2], harness.limits)
	local after: any = HarnessTap.read(heard[3], harness.limits).owner
	if bare.owner ~= nil then
		return false, "A frame with no OwnerState handed carried one"
	elseif not after or #after.looks ~= 0 then
		return false, `A frame after one that dropped its look carried {after and #after.looks} looks, not none`
	end

	return true, nil
end
