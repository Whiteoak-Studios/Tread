--[[
    A bot counts an acknowledgment as an OwnerState heard and apart, throws
    on neither and reads its body on both, and its every Move over a seeded
    roam is the same with checks off, on with bots agreeing and on without,
    and as a bot handed no body sends them
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Harness = require("../../Fixtures/DevBot/Harness")
local Rig = require("../../Fixtures/Server/Rig")

local Volt = require("@volt")

local CLIENT: string = "src/Network/Client.luau"
local VOLT: string = "ReplicatedStorage.Packages.Volt"
local ACK_BYTES: number = 5 -- An acknowledgment's: an OwnerState's command, tick and queue depth
local BOT_RTT: number = 0.1 -- Seconds, the round trip the bots table needs
local SEED: number = 7
local TICKS: number = 120
local MOVED: number = 4 -- Studs the body must cover, so the Moves compared steered from where it stood
local BOT_X: number = -20 -- Where the body is built, clear of the fixture's obstacles
local START_Z: number = 10
local AREA: number = 12 -- Studs across the square the bot roams, around where it was built
local SPEED: number = 16 -- Studs a second the roam's patience counts from

-- The run's ticks come faster than real time, so the Move's rate is raised past what they send in a real second
local MOVES_A_SECOND: number = 10000

-- The runs whose Moves must match: owner.checks and bots.agree in each, the last with the bot handed no body, as
-- every bot was before it read one, so it decodes each full OwnerState
type Mode = { checks: boolean, agree: boolean, body: boolean }

local MODES: { Mode } = {
	{ checks = false, agree = false, body = true },
	{ checks = true, agree = true, body = true },
	{ checks = true, agree = false, body = true },
	{ checks = false, agree = false, body = false },
}

-- What one run gave: each Move fired, as its numbers and wire fields in one line, and what the bot measured
type Ran = {
	moves: { string },
	measure: any,
	covered: number,
}

-- One Move's numbers and every wire field it carries, in one line
local function line(command: number, acknowledged: number, received: number, delay: number, wires: { any }): string
	local parts: { string } = { `{command} {acknowledged} {received} {delay}` }
	for _, wire: any in wires do
		local bytes: { string } = {}
		for offset: number = 0, buffer.len(wire.fields) - 1 do
			table.insert(bytes, `{buffer.readu8(wire.fields, offset)}`)
		end

		local fields: string = table.concat(bytes, ",")
		local look: string = `{wire.yaw} {wire.pitch} {wire.lean} {wire.headYaw} {wire.headPitch}`
		table.insert(parts, `{wire.moveX} {wire.moveZ} {wire.buttons} {look} {fields} {wire.check}`)
	end

	return table.concat(parts, "|")
end

-- 1) A bot on the stand-in client side, with no body and then with one, hearing both messages
local function hearing(harness: Harness.Loaded): string?
	local side: Harness.Side = Harness.side()
	local bot: any = harness.Bot.new(side.network, harness.context, function () end, nil, SEED)
	local where: vector = vector.create(3, 0, 4)
	local full: buffer = Harness.owner(harness, where, vector.zero, 10, 10)
	local ack: buffer = buffer.create(ACK_BYTES)
	buffer.copy(ack, 0, full, 0, ACK_BYTES)

	local heardAck: boolean = pcall(side.listeners.Owner, ack)
	local measure: any = bot:measure()
	if not heardAck or measure.heard ~= 1 or measure.acks ~= 1 or measure.position ~= nil then
		return `With no body, an acknowledgment counted {measure.heard} heard and {measure.acks} apart, or moved it`
	end

	local heardFull: boolean = pcall(side.listeners.Owner, full)
	if not heardFull or measure.heard ~= 2 or measure.acks ~= 1 or measure.position ~= where then
		return `With no body, a full OwnerState counted {measure.heard} heard and {measure.acks} apart`
	end

	bot:destroy()

	-- Handed a body, both messages read it, whatever the full one says
	local body: any = harness.State.new()
	body.position = vector.create(-5, 1, 2)
	side = Harness.side()
	bot = harness.Bot.new(side.network, harness.context, function () end, nil, SEED, body)
	measure = bot:measure()

	side.listeners.Owner(ack)
	if measure.position ~= body.position or measure.acks ~= 1 then
		return `With a body, an acknowledgment read {measure.position}, not the body's {body.position}`
	end

	body.position = vector.create(-6, 1, 2)
	side.listeners.Owner(full)
	if measure.position ~= body.position or measure.heard ~= 2 then
		return `With a body, a full OwnerState read {measure.position}, not the body's {body.position}`
	end

	bot:destroy()

	return nil
end

-- 2) One seeded roam of a bot on the real server, its client side the generated module on its transport
local function roam(harness: Harness.Loaded, mode: Mode): Ran
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.owner = { checks = mode.checks }
		settings.bots = { rtt = BOT_RTT, agree = mode.agree }
		settings.rates.move = { perSecond = MOVES_A_SECOND, burst = MOVES_A_SECOND }
	end)

	local server: any = rig:start()
	local volt: any = rig.mock:addBot("Bot")
	local transport: any = rig.mock:connectBot(volt)
	local network: any = Environment.load(CLIENT, {
		[VOLT] = {
			start = function (schema: any): any
				return Volt.start(schema, transport)
			end,
		},
	})

	-- Every Move the bot fires, kept as it went, since the bot reuses its wires, through the generated module, which
	-- is frozen, so the bot is handed it behind a Move of the case's own
	local ran: Ran = { moves = {}, measure = nil, covered = 0 }
	local sending: any = {
		events = network.events,
		flush = network.flush,
		View = network.View,

		Move = {
			fire = function (command: number, acknowledged: number, received: number, delay: number, wires: any)
				table.insert(ran.moves, line(command, acknowledged, received, delay, wires))
				network.Move.fire(command, acknowledged, received, delay, wires)
			end,
		},
	}

	local start: any = rig:at(BOT_X, START_Z)
	local character: any = server:create(volt, start)
	local body: any = mode.body and rig:require(rig.tread.Server.Characters).stateOf(character) or nil
	local area: any = { center = start.Position, size = roblox.Vector2.new(AREA, AREA) }
	local gait: any = { speed = SPEED, rate = rig.rate, sprint = false, crouch = false, long = false }
	local steer: any = harness.Programs.roam(area, harness.Seeded.new(SEED), gait)
	local context: any = harness.Bot.context(rig.shared, harness.Config.delay, harness.Config.fields)
	local bot: any = harness.Bot.new(sending, context, steer, nil, SEED, body)

	server:addStage("bots", "relay", function (tick: number)
		bot:tick(tick)
	end)

	rig:deliver()

	for _ = 1, TICKS do
		rig:tick(1)
		rig:deliver()

		local root: any = character:getState().root
		ran.covered = math.max(ran.covered, (root - start.Position).Magnitude)
	end

	ran.measure = bot:measure()
	bot:destroy()

	return ran
end

return function (): (boolean, string | nil)
	local harness: Harness.Loaded = Harness.load()
	local heard: string? = hearing(harness)
	if heard then
		return false, heard
	end

	local runs: { Ran } = {}
	for _, mode: Mode in MODES do
		local ran: Ran = roam(harness, mode)
		local label: string = `With owner.checks {mode.checks}, bots.agree {mode.agree} and a body {mode.body}`
		local acks: number = ran.measure.acks
		local agreeing: boolean = mode.checks and mode.agree

		if ran.covered < MOVED then
			return false, `{label}, the body got {ran.covered} studs out, too little to show it steered`
		elseif ran.measure.heard < TICKS - 1 then
			return false, `{label}, the bot heard {ran.measure.heard} OwnerStates in {TICKS} ticks`
		elseif agreeing and acks < ran.measure.heard / 2 or not agreeing and acks ~= 0 then
			return false, `{label}, {acks} of the {ran.measure.heard} OwnerStates the bot heard were acknowledgments`
		end

		table.insert(runs, ran)
	end

	local first: Ran = runs[1]
	for index: number = 2, #runs do
		local other: Ran = runs[index]
		if #other.moves ~= #first.moves then
			return false, `Mode {index} fired {#other.moves} Moves and the first {#first.moves}`
		end

		for at: number, move: string in first.moves do
			if other.moves[at] ~= move then
				return false, `Mode {index}'s Move {at} differs from the first mode's: {other.moves[at]} against {move}`
			end
		end
	end

	return true, nil
end
