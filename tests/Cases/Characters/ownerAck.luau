--[[
    With checks on, a command whose check is the hash the server's state
    gives is answered with the full OwnerState's first 5 bytes, any other
    tick and every change the server made gets the full OwnerState, and the
    spectate feed and the taps get the full bytes every tick either way
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Rig = require("../../Fixtures/Server/Rig")

local HASH: string = "src/Codec/Hash.luau"
local ACK_BYTES: number = 5 -- An acknowledgment's: an OwnerState's command, tick and queue depth
local TICKS: number = 10
local SKIP_AT: number = 4 -- The tick every run sends no command for, so it steps a stand-in
local WRONG_AT: number = 5 -- The tick the base run's check misses at
local ZERO_AT: number = 6 -- The tick the base run sends a check of 0 at
local CHANGE_AT: number = 8 -- The tick a change the server makes lands on, which the checks didn't predict
local TURN: number = 0.1 -- Radians the look turns a tick, so each tick's state differs from the one before
local DELAY: number = 100 -- Milliseconds of interpolation delay each Move reports
local WORD: number = 2 ^ 32 -- The values a check holds

-- The platform the body stands on and turns in place on, as in the platforms case, one 8 studs square
local PLATFORM: number = 1
local X: number = -15
local Z: number = 10
local BASE: number = 3 -- Studs above the floor its box center rests before a call
local RISE: number = 0.25 -- Studs it rises a tick once called
local HALF_HEIGHT: number = 0.5
local WIDTH: number = 8

local TELEPORT_X: number = -25 -- Where the teleport sets the body down, on the floor clear of the platform
local TELEPORT_Z: number = 10

-- What one run of the rig does differently
type Options = {
	checks: boolean, -- owner.checks
	hashes: { [number]: number }?, -- Each tick's check, from the run with checks off, or 0 for every one
	wrong: boolean?, -- Whether WRONG_AT's check misses and ZERO_AT's is 0
	change: string?, -- The change the server makes for CHANGE_AT, by name
}

-- What one run heard: the Owner message after each tick, and the bytes the feed and the taps were handed each tick
type Run = {
	owners: { [number]: string },
	feeds: { [number]: string },
	taps: { [number]: string },
}

-- The changes the server makes that its client can't predict, each made before CHANGE_AT's tick
local CHANGES: { string } = { "teleport", "mode", "field", "platform", "hook" }

-- One run: the player stands on the platform, turning a step each tick from tick 2, each command with its check
local function run(options: Options): (Run?, string?)
	local moved: boolean = false -- Whether the hook moves CHANGE_AT's command, as a game's hook may
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.owner = { checks = options.checks }
		settings.beforeCommand = function (_: any, command: any)
			if moved and command.number == CHANGE_AT then
				command.forward = 1
			end
		end
	end)

	local server: any = rig:start()
	local tread: any = rig.tread
	local Command: any = rig:require(tread.Codec.Command)
	local Fields: any = rig:require(tread.Codec.Fields)
	local Move: any = rig:require(tread.Codec.Move)
	local Spectate: any = rig:require(tread.Server.Spectate)
	local floor: number = rig.floor

	server:addPlatform({
		id = PLATFORM,
		boxes = { { center = roblox.Vector3.zero, size = roblox.Vector3.new(WIDTH, HALF_HEIGHT * 2, WIDTH) } },

		path = function (tick: number, calledAt: number?): any
			local risen: number = calledAt ~= nil and (tick - calledAt) * RISE or 0

			return roblox.Vector3.new(X, floor + BASE + risen, Z)
		end,
	})

	local result: Run = { owners = {}, feeds = {}, taps = {} }
	local heard: string? = nil
	local fed: string? = nil
	local tapped: string? = nil

	local client: any = rig:require(tread.Network.Client)
	client.Owner.on(function (data: buffer)
		heard = buffer.tostring(data)
	end)

	local feed: any = Spectate.feed
	Spectate.feed = function (key: any, data: buffer, length: number)
		fed = buffer.tostring(data):sub(1, length)
		feed(key, data, length)
	end

	client.flush()
	rig:deliver()

	local player: any = rig.mock.players[1]
	local character: any = server:create(player, roblox.CFrame.new(X, floor + BASE + 1, Z))
	server:observe(player, function (_: number, data: buffer)
		local frame: any = rig:require(tread.Codec.Tap).read(data)
		tapped = frame.owner and buffer.tostring(frame.owner.data)
	end)

	local layout: any = Fields.compile(rig.shared.fields)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	local move: any = Move.new()
	local command: any = Command.new()
	command.fields = { slot = 0, shots = {} }

	for tick: number = 1, TICKS do
		local change: string? = options.change

		-- A call times the path from the next tick, where it stands at rest, so the body rides up the tick after
		if change == "platform" and tick == CHANGE_AT - 1 then
			server:callPlatform(PLATFORM)
		elseif tick == CHANGE_AT then
			if change == "teleport" then
				character:teleport(rig:at(TELEPORT_X, TELEPORT_Z))
			elseif change == "mode" then
				character:setMode("Noclip")
			elseif change == "field" then
				character:setField("beingRevived", true)
			elseif change == "hook" then
				moved = true
			end
		end

		-- The first tick and SKIP_AT's run with no command, the first since the server ran no tick before it
		if tick > 1 and tick ~= SKIP_AT then
			local hashes: { [number]: number }? = options.hashes
			local check: number = hashes and hashes[tick] or 0
			if options.wrong and tick == WRONG_AT then
				check = (check + 1) % WORD
			elseif options.wrong and tick == ZERO_AT then
				check = 0
			end

			command.number = tick
			command.yaw = tick * TURN
			Move.encode(move, { command }, 1, 0, 0, DELAY, layout, limits, { check })
			client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
			client.flush()
			rig:deliver()
		end

		heard, fed, tapped = nil, nil, nil
		rig:tick(1)
		rig:deliver()

		if heard == nil or fed == nil or tapped == nil then
			return nil, `Tick {tick} sent the client {heard and "an" or "no"} Owner message, fed {fed}, tapped {tapped}`
		end

		result.owners[tick] = heard
		result.feeds[tick] = fed
		result.taps[tick] = tapped
	end

	return result, nil
end

-- Whether a tick of a run with checks on takes an acknowledgment, from its options
local function acknowledged(options: Options, tick: number): boolean
	if tick == 1 or tick == SKIP_AT then
		return false
	elseif options.wrong and (tick == WRONG_AT or tick == ZERO_AT) then
		return false
	elseif options.change and tick >= CHANGE_AT then
		return false
	end

	return true
end

--[[
    Why a run's messages are not what its options give against the run
    with checks off, or nil when they are: an acknowledgment the full
    OwnerState's first bytes, any other tick the full OwnerState, and the
    feed and the taps the full bytes, which before any change are the run
    with checks off's own
--]]

local function compare(label: string, options: Options, heard: Run, reference: Run): string?
	for tick: number = 1, TICKS do
		local owner: string = heard.owners[tick]
		local fed: string = heard.feeds[tick]
		local full: string = reference.owners[tick]
		local due: boolean = options.checks and acknowledged(options, tick)
		local unchanged: boolean = options.change == nil or tick < CHANGE_AT

		if due and owner ~= full:sub(1, ACK_BYTES) then
			return `{label}: tick {tick} sent {#owner} B, not the full OwnerState's first {ACK_BYTES}`
		elseif not due and #owner <= ACK_BYTES then
			return `{label}: tick {tick} sent an acknowledgment, where the full OwnerState goes`
		elseif not due and fed ~= owner then
			return `{label}: tick {tick}'s feed was handed other bytes than its full OwnerState`
		elseif #fed <= ACK_BYTES or heard.taps[tick] ~= fed then
			return `{label}: tick {tick}'s feed got {#fed} B and its taps {#heard.taps[tick]} B, not the same full bytes`
		elseif unchanged and fed ~= full then
			return `{label}: tick {tick}'s feed got other bytes than the run with checks off sent its client`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local off: Options = { checks = false }
	local reference: Run?, failure: string? = run(off)
	if not reference then
		return false, `With checks off: {failure}`
	end

	-- Each tick's check is the hash of the full OwnerState the run with checks off sent past its first bytes
	local Hash: any = Environment.load(HASH)
	local hashes: { [number]: number } = {}
	for tick: number, owner: string in reference.owners do
		local data: buffer = buffer.fromstring(owner)
		if #owner <= ACK_BYTES then
			return false, `With checks off, tick {tick} sent {#owner} B`
		end

		hashes[tick] = Hash.range(data, ACK_BYTES, #owner - ACK_BYTES)
	end

	local plans: { { label: string, options: Options } } = {
		{ label = "With checks off and the checks right", options = { checks = false, hashes = hashes, wrong = true } },
		{ label = "With checks on", options = { checks = true, hashes = hashes, wrong = true } },
	}

	for _, change: string in CHANGES do
		table.insert(plans, {
			label = `With checks on and a {change} change`,
			options = {
				checks = true,
				hashes = hashes,
				change = change,
			},
		})
	end

	for _, plan: { label: string, options: Options } in plans do
		local heard: Run?, why: string? = run(plan.options)
		if not heard then
			return false, `{plan.label}: {why}`
		end

		local wrong: string? = compare(plan.label, plan.options, heard, reference)
		if wrong then
			return false, wrong
		end
	end

	return true, nil
end
