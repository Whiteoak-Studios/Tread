--[[
    The real Predict against the real server with checks on: acknowledgments
    while the two agree, a full OwnerState on the tick after a change the
    client didn't predict, one correction, then acknowledgments again, and a
    full OwnerState lost followed by another on the next tick
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local ACK_BYTES: number = 5 -- An acknowledgment's: an OwnerState's command, tick and queue depth
local SPAWN_X: number = -20 -- On the fixture floor, with 50 studs clear along -Z
local SPAWN_Z: number = 25
local WALK_TICKS: number = 40 -- Ticks each way the input walks, forward then back, so the body stays on the floor
local DELAY: number = 0.1 -- Seconds of interpolation delay the client reports
local SETTLE: number = 60 -- Ticks the client's clock has to settle before the run is judged
local AGREE: number = 20 -- Ticks every message must be an acknowledgment, once settled and again after each change
local RECOVER: number = 6 -- Ticks after a change by which the replayed checks must agree again

-- The run's ticks come faster than real time, so the Move's rate is raised past what they send in a real second
local MOVES_A_SECOND: number = 10000

-- Each Owner message the client heard, by the server tick it names, and whether it was handed to Predict
type Heard = { [number]: { bytes: number, read: boolean } }

-- What the client hears and has no use for here, so none of it queues
local function ignore() end

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.owner = { checks = true }
		settings.rates.move = { perSecond = MOVES_A_SECOND, burst = MOVES_A_SECOND }
	end)

	local server: any = rig:start()
	local tread: any = rig.tread
	local Engine: any = rig:require(tread.Step.Engine)
	local Fields: any = rig:require(tread.Codec.Fields)
	local Predict: any = rig:require(tread.Client.Predict)
	local World: any = rig:require(tread.Step.World)
	local client: any = rig:require(tread.Network.Client)
	local shared: any = rig.shared
	local rate: number = shared.rates.simulation
	local example: any = rig:require(rig.globals.game:GetService("ServerScriptService").Fixtures.Config.Example)

	-- The client's world on the same fixture casts the server's runs on, as the client handle builds it
	local collision: any = Engine.casts(shared.collision)
	local world: any = World.new(shared.step, rate, collision, shared.water, shared.rules, false)

	local samples: number = 0
	Predict.start(
		{
			rates = shared.rates,
			ticks = shared.ticks,
			tolerances = shared.tolerances,
			smoothing = example.client().smoothing,
			layout = Fields.compile(shared.fields),

			sample = function (command: any)
				samples += 1
				command.forward = (samples // WALK_TICKS) % 2 == 0 and 1 or -1
				command.fields.slot = 0
				command.fields.shots = {}
			end,

			look = function (): (number, number, number, number)
				return 0, 0, 0, 0
			end,

			delay = function (): number
				return DELAY
			end,
		},
		world,
		function (move: any)
			client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
			client.flush()
		end,
		function (): (number, number)
			return 0, 0
		end
	)

	local corrections: number = 0
	Predict.onCorrected(function (_: number, _: boolean)
		corrections += 1
	end)

	local heard: Heard = {}
	local losing: boolean = false -- Whether the next full OwnerState is lost on its way
	client.Owner.on(function (data: buffer)
		local full: boolean = buffer.len(data) > ACK_BYTES
		local lost: boolean = losing and full
		heard[buffer.readu16(data, 2)] = { bytes = buffer.len(data), read = not lost }

		if lost then
			losing = false
		else
			Predict.receive(data)
		end
	end)

	client.Relay.on(ignore)
	client.flush()
	rig:deliver()

	local character: any = server:create(rig.mock.players[1], rig:at(SPAWN_X, SPAWN_Z))
	local tick: number = 0

	-- Runs ticks, each a server Heartbeat, the mock both ways, then a client frame of the same time
	local function run(count: number)
		for _ = 1, count do
			rig:tick(1)
			tick += 1
			rig:deliver()
			Predict.frame(1 / rate)
		end
	end

	-- Why some tick from first to last, each named by the server, sent other than an acknowledgment, or nil
	local function agreed(first: number, last: number, what: string): string?
		for at: number = first, last do
			local message: { bytes: number, read: boolean }? = heard[at]
			if not message or message.bytes ~= ACK_BYTES then
				return `{what}, tick {at} sent {message and message.bytes} B, not an acknowledgment`
			end
		end

		return nil
	end

	-- Settled, the client predicts every tick the server runs, so each one agrees, and the start's stand-ins are behind
	run(SETTLE)
	local started: number = corrections
	run(AGREE)

	local settled: string? = agreed(SETTLE + 1, tick, "Once the clock settled")
	if settled then
		return false, settled
	elseif corrections ~= started then
		return false, `The client corrected {corrections - started} times while its checks agreed`
	end

	-- 1) A field the server sets, which the client never predicts, goes in full on the tick after, and is corrected once
	local changed: number = tick + 1
	character:setField("beingRevived", true)
	run(RECOVER + AGREE)

	if not heard[changed] or heard[changed].bytes <= ACK_BYTES then
		return false, `The tick after the server set a field sent {heard[changed] and heard[changed].bytes} B`
	elseif corrections ~= started + 1 then
		return false, `The field the server set cost {corrections - started} corrections, not one`
	end

	local recovered: string? = agreed(changed + RECOVER, tick, "After the correction")
	if recovered then
		return false, recovered
	end

	-- 2) The field set back, its full OwnerState lost, and the next tick's full one lands and corrects
	local lost: number = tick + 1
	losing = true
	character:setField("beingRevived", false)
	run(RECOVER + AGREE)

	if not heard[lost] or heard[lost].read or heard[lost].bytes <= ACK_BYTES then
		return false, `The full OwnerState after the field was set back was not the one lost`
	elseif not heard[lost + 1] or heard[lost + 1].bytes <= ACK_BYTES then
		return false,
			`The tick after the lost OwnerState sent {heard[lost + 1] and heard[lost + 1].bytes} B, not it in full`
	elseif corrections ~= started + 2 then
		return false, `The field set back cost {corrections - started - 1} corrections, not one`
	end

	recovered = agreed(lost + RECOVER, tick, "After the lost OwnerState's correction")
	if recovered then
		return false, recovered
	end

	local read: any = server:stats()
	if read.ownerAcks == 0 or read.ownerMismatches == 0 or read.ownerChecked < read.ownerAcks then
		local counts: string = `{read.ownerAcks} acknowledgments, {read.ownerChecked} compares`
		return false, `Stats gave {counts} and {read.ownerMismatches} misses`
	end

	return true, nil
end
