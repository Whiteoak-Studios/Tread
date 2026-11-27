--[[
    The bot harness sums the tick stages' rings by the tick each time ran
    on, oldest first across the wrap, the relay adding nothing to a tick it
    skipped, leaves the rest out, and refuses a full ring short of the window
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local RUN: string = "dev/Server/Bots/Run.luau"
local CAPACITY: number = 4
local HEAD: number = 1 -- The ring index the next time goes at, so the newest sits at the ring's first and the wrap behind it
local NEWEST: number = 3
local LAST: number = 40 -- The tick the full rings' newest time ran on

-- Each tick stage's time a ring index is that index times its own place value, so every sum reads its index back
local PLACES: { [string]: number } = { decode = 1, simulate = 10, npcs = 100, history = 1000, relay = 10000 }
local OTHER: number = 7 -- The place value of the stages left out, so any of their times would show in a sum
local STAGE_ORDER: { string } = { "decode", "simulate", "npcs", "history", "antiEsp", "relay", "bots" }
local EXPECTED: { number } = { 33333, 44444, 11111 } -- Ring indexes 3, 4 and then 1, past the wrap

-- Each Heartbeat's ticks, two on a catch-up one, whose first the relay skips, and a stage's time a tick that tick
-- times its place value, so every sum reads its tick and whether the relay ran on it
local HEARTBEATS: { { number } } = { { 1 }, { 2, 3 }, { 4 }, { 5, 6 } }
local EARLY: number = 2 -- The Heartbeats run while the rings are still filling
local EARLY_TOTALS: { number } = { 11111, 2222, 33333 } -- Ticks 1 to 3, the relay skipping 2
local SKIPPED_TOTALS: { number } = { 33333, 44444, 5555, 66666 } -- Ticks 3 to 6, the relay skipping 5
local SKIPS: string = "relay" -- The stage a catch-up Heartbeat's earlier ticks skip
local SHORT: number = 3 -- A ring too short for the window, which holds ticks 4 to 6 alone
local SHORTENED: string = "history" -- The stage given it

-- One stage as the tick loop keeps it, its ring full and its head where the case puts it, its newest at LAST
local function stage(name: string, head: number, place: number): any
	local times: { number } = {}
	for index: number = 1, CAPACITY do
		table.insert(times, index * place)
	end

	-- The newest at the index before the head, each one behind it a tick older
	local ticks: { number } = table.create(CAPACITY, 0)
	for back: number = 1, CAPACITY do
		ticks[(head - back) % CAPACITY + 1] = LAST - back + 1
	end

	return {
		name = name,
		run = function () end,
		between = false,
		label = name,
		times = times,
		ticks = ticks,
		held = CAPACITY,
		head = head,
	}
end

-- One stage as the tick loop makes it, its ring of the size given still empty
local function empty(name: string, size: number): any
	return {
		name = name,
		run = function () end,
		between = false,
		label = name,
		times = table.create(size, 0),
		ticks = table.create(size, 0),
		held = 0,
		head = 0,
	}
end

-- Each stage's ring after the Heartbeats given, written as the tick loop writes it, the relay on each one's last tick
local function heartbeats(rings: { any }, from: number, to: number)
	for index: number = from, to do
		local heartbeat: { number } = HEARTBEATS[index]

		for at: number, tick: number in heartbeat do
			for _, ring: any in rings do
				if ring.name == SKIPS and at < #heartbeat then
					continue
				end

				local size: number = #ring.times
				ring.times[ring.head + 1] = tick * (PLACES[ring.name] or OTHER)
				ring.ticks[ring.head + 1] = tick
				ring.head = (ring.head + 1) % size
				ring.held = math.min(ring.held + 1, size)
			end
		end
	end
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server

	-- Stand-ins for the dev game and its fleet, whose real modules start the dev game's server when required
	local results: { [any]: any } = { [server.Game] = {}, [server.Bots.Fleet] = {} }
	local Run: any = Kit.loader(dataModel, { [server.Bots.Run] = RUN }, results, loaded.require)(server.Bots.Run)

	-- The between stage and the bots' stage hold their own heads and times, which must not reach the sums
	local stages: { any } = {}
	for _, name: string in STAGE_ORDER do
		local place: number? = PLACES[name]
		if place then
			table.insert(stages, stage(name, HEAD, place))
		else
			table.insert(stages, stage(name, CAPACITY - 1, OTHER))
		end
	end

	local totals: { number } = Run.tickTotals(stages, NEWEST)
	if table.concat(totals, ",") ~= table.concat(EXPECTED, ",") then
		return false,
			`The newest {NEWEST} ticks summed to {table.concat(totals, ",")}, not {table.concat(EXPECTED, ",")}`
	end

	local all: { number } = Run.tickTotals(stages, CAPACITY * 2)
	if #all ~= CAPACITY then
		return false, `Asked for more ticks than the rings hold, it summed {#all}, not the {CAPACITY} held`
	end

	-- A relay ring that skipped ticks, still filling: every tick from the first, the skipped one without the relay
	local skipping: { any } = {}
	for _, name: string in STAGE_ORDER do
		table.insert(skipping, empty(name, CAPACITY))
	end

	heartbeats(skipping, 1, EARLY)

	local early: string = table.concat(Run.tickTotals(skipping, CAPACITY * 2), ",")
	if early ~= table.concat(EARLY_TOTALS, ",") then
		return false, `The filling rings summed to {early}, not {table.concat(EARLY_TOTALS, ",")}`
	end

	-- Once full, its heads apart from the rest: the newest ticks, the skipped one without the relay
	heartbeats(skipping, EARLY + 1, #HEARTBEATS)

	local skipped: string = table.concat(Run.tickTotals(skipping, CAPACITY), ",")
	if skipped ~= table.concat(SKIPPED_TOTALS, ",") then
		return false, `The skipping relay's window summed to {skipped}, not {table.concat(SKIPPED_TOTALS, ",")}`
	end

	-- A full ring whose oldest tick is past the window's oldest is refused, naming its stage
	local short: { any } = {}
	for _, name: string in STAGE_ORDER do
		local size: number = name == SHORTENED and SHORT or CAPACITY
		table.insert(short, empty(name, size))
	end

	heartbeats(short, 1, #HEARTBEATS)

	local summed: boolean, message: any = pcall(Run.tickTotals, short, CAPACITY)
	if summed or not string.find(tostring(message), `{SHORTENED}'s full ring`, 1, true) then
		return false, `A full ring short of the window was not refused naming {SHORTENED}: {message}`
	end

	return true, nil
end
