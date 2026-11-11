--[[
    A frame observed on a bot carries its view lag in milliseconds, the bot's
    round trip, the queue wait of the command its OwnerState names and its
    clamped delay, and rewindFor puts that command's render time as far back
--]]

--!strict
local Environment = require("../../Environment")
local Rig = require("../../Fixtures/Server/Rig")

local Volt = require("@volt")

local CLIENT: string = "src/Network/Client.luau"
local VOLT: string = "ReplicatedStorage.Packages.Volt"
local SETTLE: number = 30 -- Ticks of stand-ins before the Move, so the rewinds sit inside the history
local HALF: number = 0.5 -- The share of a tick after SETTLE the Move arrives at
local DELAY: number = 100 -- Milliseconds, under the rewind's 150 ms floor, so the lag carries the floor
local FAR: number = 10 -- Relay ticks a claim lies off, so rewindFor answers with the expected time
local CLOSE: number = 1e-9
local YAW: number = 0.75 -- The newest command's yaw, each older one's a quarter radian more, which its frame's look carries
local YAW_STEP: number = 0.25

-- Each command's lag from the bot's 0.1 s round trip, its queue wait of 0.5, 1.5 and 2.5 ticks at 20 Hz and the
-- 0.15 s floor
local LAGS: { [number]: number } = {
	[SETTLE + 1] = 275,
	[SETTLE + 2] = 325,
	[SETTLE + 3] = 375,
}

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
	local Tap: any = rig:require(tread.Codec.Tap)

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

	local frames: { [number]: buffer } = {}
	local stop: () -> () = server:observe(bot, function (tick: number, data: buffer)
		frames[tick] = data
	end)

	local character: any = server:create(bot, rig:at(0, 0))
	run(SETTLE)

	-- A stand-in waited none, and before any Move the delay is 0, held at the 150 ms floor
	local settled: any = frames[SETTLE] and Tap.read(frames[SETTLE]).owner
	if not settled or settled.lag ~= 250 then
		return false, `The settled frame's lag is {settled and settled.lag}, not the 250 ms of a stand-in`
	end

	-- Three commands in one Move half a tick after SETTLE, so the one for SETTLE + n waits n - 0.5 ticks in the queue
	local layout: any = Fields.compile(rig.shared.fields)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	local commands: { any } = {}
	for back: number = 0, 2 do
		local command: any = Command.new()
		command.number = SETTLE + 3 - back
		command.yaw = YAW + back * YAW_STEP
		command.fields = { slot = 0, shots = {} }
		table.insert(commands, command)
	end

	local move: any = Move.new()
	Move.encode(move, commands, #commands, 0, 0, DELAY, layout, limits)

	now = (SETTLE + HALF) / rig.rate
	network.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
	network.flush()
	rig:deliver()

	run(3)

	for tick: number, lag: number in LAGS do
		local data: buffer? = frames[tick]
		local owner: any = data and Tap.read(data, limits).owner
		if not owner then
			return false, `Tick {tick}'s frame carried no OwnerState`
		elseif owner.lag ~= lag then
			return false, `Tick {tick}'s frame lags {owner.lag} ms, not {lag}`
		elseif #owner.looks ~= 1 or math.abs(owner.looks[1].yaw - (YAW + (SETTLE + 3 - tick) * YAW_STEP)) > 1e-4 then
			return false, `Tick {tick}'s frame does not carry the one look its command stepped`
		end

		-- The render time rewindFor expects for the command is its tick less the same lag, in relay ticks
		local time: number, inside: boolean = server:rewindFor(bot, tick, tick - FAR)
		local expected: number = tick - owner.lag / 1000 * rig.shared.rates.relay
		if inside or math.abs(time - expected) > CLOSE then
			return false, `rewindFor put command {tick} at {time}, where its frame's {owner.lag} ms gives {expected}`
		end
	end

	stop()
	character:destroy()

	return true, nil
end
