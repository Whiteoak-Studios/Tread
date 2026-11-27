--[[
    With a round out on the workers a full OwnerState leaves at the tick's
    flush and an acknowledgment at the finish's, with the player's blocks,
    and in process both leave in the one flush; a dropped round and a throw
    in the relay each send the queued acknowledgment once
--]]

--!strict
local Lockstep = require("../../Fixtures/Server/Lockstep")

local WORKERS: number = 2
local TIMEOUT: number = 1e-6 -- Seconds, so a round not delivered by the next Heartbeat is given up there
local TICKS: number = 10
local FULL_AT: number = 4 -- The tick the client sends no command for, so it steps a stand-in and goes in full
local DROP_AT: number = 6 -- The tick whose round is never delivered
local THROW_AT: number = 8 -- The tick whose relay throws once its turns are out
local DELAY: number = 100 -- Milliseconds of interpolation delay each Move reports
local ACK_BYTES: number = 5 -- An acknowledgment's: an OwnerState's command, tick and queue depth
local PLANTED: string = "A planted failure after the relay ran"

type Side = Lockstep.Side

-- Each beat's arrivals, the ones its delivery brought, by the beat's number
local function segments(side: Side): { { string } }
	local split: { { string } } = {}

	for _, arrival: string in side.arrivals do
		if arrival == "beat" then
			table.insert(split, {})
		elseif #split > 0 then
			table.insert(split[#split], arrival)
		end
	end

	return split
end

-- The beats whose delivery brought an arrival of a kind for a tick, and the bytes each one held, 0 for a block
local function found(split: { { string } }, kind: string, tick: number): ({ number }, { number })
	local beats: { number } = {}
	local sizes: { number } = {}

	for beat: number, arrived: { string } in split do
		for _, arrival: string in arrived do
			local named: string?, at: string?, bytes: string? = arrival:match("^(%a+) (%d+) ?(%d*)$")
			if named == kind and tonumber(at) == tick then
				table.insert(beats, beat)
				table.insert(sizes, tonumber(bytes) or 0)
			end
		end
	end

	return beats, sizes
end

-- A side whose server checks owners and takes the client, a bot to Tread on the mock, as agreeing on every command
local function side(relay: Lockstep.Relay?): Side
	local built: Side = Lockstep.side(relay, nil, function (settings: any)
		settings.owner = { checks = true }
		settings.bots.agree = true
	end)

	-- The relay throws once its turns are out, after it has queued the tick's acknowledgment
	local relayRun: any = built.Characters.relay
	built.Characters.relay = function (relayTick: number, tick: number)
		relayRun(relayTick, tick)
		if relayTick == THROW_AT then
			error(PLANTED)
		end
	end

	return built
end

-- Runs a side its ticks, the client's command for each but the first and FULL_AT's filed before it, with a check of 0
local function drive(built: Side)
	local tread: any = built.rig.tread
	local Command: any = built.rig:require(tread.Codec.Command)
	local Fields: any = built.rig:require(tread.Codec.Fields)
	local Move: any = built.rig:require(tread.Codec.Move)
	local layout: any = Fields.compile(built.rig.shared.fields)
	local limits: any = { lean = built.rig.shared.step.lean, headCone = built.rig.shared.step.headCone }
	local command: any = Command.new()
	command.fields = { slot = 0, shots = {} }
	local move: any = Move.new()

	for beat: number = 1, TICKS do
		if beat > 1 and beat ~= FULL_AT then
			command.number = beat
			Move.encode(move, { command }, 1, 0, 0, DELAY, layout, limits)
			built.client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
			built.client.flush()
			built.rig:deliver()
		end

		Lockstep.beat(built, 1)

		if built.pool and beat ~= DROP_AT then
			built.pool:deliver()
		end
	end

	-- The last tick's finish
	Lockstep.beat(built, 1)
end

-- Why one tick's Owner messages and blocks came other than where they belong, or nil when each did
local function check(label: string, split: { { string } }, tick: number, workers: boolean): string?
	local full: boolean = tick == 1 or tick == FULL_AT
	local beats: { number }, sizes: { number } = found(split, "owner", tick)
	local relays: { number } = found(split, "relay", tick)

	if #beats ~= 1 then
		return `{label}: tick {tick} sent the client {#beats} Owner messages, not one`
	end

	local bytes: number = sizes[1]
	if full and bytes <= ACK_BYTES then
		return `{label}: tick {tick} sent an acknowledgment, where its stand-in's full OwnerState goes`
	elseif not full and bytes ~= ACK_BYTES then
		return `{label}: tick {tick} sent {bytes} B, not an acknowledgment`
	end

	-- In process both leave in the tick's flush; on the workers a full one does, and an acknowledgment and the
	-- blocks leave at the finish's, a beat later, but the dropped round's, which sends no worker block
	local owner: number = (workers and not full) and tick + 1 or tick
	local blocks: number = workers and tick + 1 or tick
	local dropped: boolean = workers and tick == DROP_AT

	if beats[1] ~= owner then
		return `{label}: tick {tick}'s Owner message came at beat {beats[1]}, not {owner}`
	elseif dropped and #relays ~= 0 then
		return `{label}: the dropped round of tick {tick} still sent the client {#relays} blocks`
	elseif not dropped and (#relays == 0 or relays[1] ~= blocks) then
		return `{label}: tick {tick}'s blocks came at beat {relays[1]}, not {blocks}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local serial: Side = side(nil)
	local workers: Side = side({ workers = WORKERS, timeout = TIMEOUT })

	drive(serial)
	drive(workers)

	for _, built: { label: string, side: Side, workers: boolean } in
		{
			{ label = "In process", side = serial, workers = false },
			{ label = "On the workers", side = workers, workers = true },
		}
	do
		local split: { { string } } = segments(built.side)

		for tick: number = 1, TICKS do
			local wrong: string? = check(built.label, split, tick, built.workers)
			if wrong then
				return false, wrong
			end
		end

		local reported: { number | string } = built.side.rig:reported("stage")
		if #reported ~= 1 or reported[1] ~= "relay" then
			return false, `{built.label}, the stage reports were {#reported}, the first {reported[1]}`
		end
	end

	local read: any = workers.server:stats()
	if read.relayDropped ~= 1 then
		return false, `On the workers, stats gave {read.relayDropped} rounds dropped, not the one`
	end

	return true, nil
end
