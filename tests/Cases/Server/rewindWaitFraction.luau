--[[
    server:rewindFor's expected render time counts its command's queue wait
    from the moment the Move arrived, fraction and all, so a Move that comes
    a quarter tick later moves its command's expected time by that quarter
--]]

--!strict
local Environment = require("../../Environment")
local Rig = require("../../Fixtures/Server/Rig")

local Volt = require("@volt")

local CLIENT: string = "src/Network/Client.luau"
local VOLT: string = "ReplicatedStorage.Packages.Volt"
local SETTLE: number = 30 -- Ticks of stand-ins before the first Move, so the rewinds sit inside the history
local LEAD: number = 2 -- Ticks after the tick a Move follows that its one command is for
local QUARTER: number = 0.25 -- The share of a tick the second Move arrives after the tick it follows
local DELAY: number = 200 -- Milliseconds of interpolation delay each Move reports, inside the rewind's clamp
local FAR: number = 10 -- Relay ticks a claim lies off, so rewindFor answers with the expected time
local MILLISECONDS: number = 1000
local CLOSE: number = 1e-9

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local tread: any = rig.tread
	local now: number = 0 -- Seconds on the clock Commands is handed
	local ticked: number = 0 -- The ticks run so far

	rig:require(tread.Server.Commands).setClock(function (): number
		return now
	end)

	-- Runs count ticks, the clock on each one's time as it runs
	local function run(count: number)
		for _ = 1, count do
			ticked += 1
			now = ticked / rig.rate
			rig:tick(1)
		end
	end

	local Command: any = rig:require(tread.Codec.Command)
	local Fields: any = rig:require(tread.Codec.Fields)
	local Move: any = rig:require(tread.Codec.Move)

	-- The bot's client side is the generated module on the bot's own transport
	local bot: any = rig.mock:addBot("Bot")
	local transport: any = rig.mock:connectBot(bot)
	local network: any = Environment.load(CLIENT, {
		[VOLT] = {
			start = function (schema: any): any
				return Volt.start(schema, transport)
			end,
		},
	})

	network.flush()
	rig:deliver()

	local character: any = server:create(bot, rig:at(0, 0))
	run(SETTLE)

	local layout: any = Fields.compile(rig.shared.fields)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	local move: any = Move.new()

	-- A Move of one command for the tick number, arriving as the clock stands
	local function send(number: number)
		local command: any = Command.new()
		command.number = number
		command.fields = { slot = 0, shots = {} }

		Move.encode(move, { command }, 1, 0, 0, DELAY, layout, limits)
		network.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
		network.flush()
		rig:deliver()
	end

	-- The first arrives as tick SETTLE is taken, so its command waits LEAD whole ticks
	local first: number = SETTLE + LEAD
	send(first)
	run(LEAD)

	-- The second a quarter tick after its tick was taken, so its command waits a quarter tick less
	local second: number = first + LEAD
	now = (first + QUARTER) / rig.rate
	send(second)
	run(LEAD)

	local relay: number = rig.shared.rates.relay
	local firstTime: number, firstInside: boolean = server:rewindFor(bot, first, first - FAR)
	local secondTime: number, secondInside: boolean = server:rewindFor(bot, second, second - FAR)

	local lag: number = rig.settings.bots.rtt + LEAD / rig.rate + DELAY / MILLISECONDS
	local expected: number = first - lag * relay
	if firstInside or secondInside then
		return false, `A claim {FAR} relay ticks off was taken as inside the band`
	elseif math.abs(firstTime - expected) > CLOSE then
		return false, `The command that waited {LEAD} ticks was expected at {firstTime}, not {expected}`
	end

	local moved: number = (secondTime - second) - (firstTime - first)
	local fraction: number = QUARTER * relay / rig.rate
	if math.abs(moved - fraction) > CLOSE then
		return false,
			`A Move a quarter tick later moved its command's expected time by {moved} relay ticks, not {fraction}`
	end

	character:destroy()

	return true, nil
end
