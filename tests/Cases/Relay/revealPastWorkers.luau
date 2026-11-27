--[[
    With relay.past, viewers at four delays watching hidden players come and
    go, across a skipped relay tick and a teleport, get the same blocks and
    tap frames, byte for byte, in process and on two stand-in workers, whose
    hand-ins carry each viewer's delay
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WIRE: string = "src/Server/Relay/Wire.luau"
local WORKERS: number = 2
local DELAYS: { number } = { 100, 250, 180, 0 } -- Each viewer's, in milliseconds
local LAGGING: number = 3 -- The viewer whose acknowledgments take a run, so its reveals repeat
local OBSERVED: number = 2 -- The viewer a sink observes, at 250 ms
local PLAYERS: number = 8
local RING: number = 100 -- Studs from the origin the players stand around
local STRIDE: number = 0.05 -- Radians each walks around the ring a run
local RUNS: number = 30
local PERIOD: number = 4 -- Runs each pattern of hidden pairs holds
local SPREAD: number = 3 -- One pair in this many is hidden in each pattern
local SKIP_RUN: number = 12 -- The run whose relay tick follows a skipped one
local TELEPORT_RUN: number = 18 -- The run before which the first player teleports
local TELEPORT: vector = vector.create(0, 0, 40)
local WIDE: number = 6 -- The records a 250 ms viewer's reveal carries at the example's 20 Hz
local NARROW: number = 3 -- And a 100 ms one's

-- What one mode's run gave: every block and tap frame in order with whom it went to, the delays its workers' hand-ins
-- carried, and the most records any reveal carried to each viewer
type Ran = {
	parts: { string },
	delays: string,
	most: { number },
}

local function run(workers: number?): Ran
	local Harness: any
	if workers then
		Harness = Layouts.harness()
	else
		Harness = Environment.load(HARNESS)
	end

	local harness: any = Harness.new(nil, function (_: any, server: any)
		server.relay = { changes = true, past = true }
	end, workers)

	local ran: Ran = { parts = {}, delays = "", most = table.create(#DELAYS, 0) }
	local names: { [any]: string } = {}

	harness._deliver = function (self: any, keys: { any }, data: buffer)
		local to: { string } = {}
		for index: number, key: any in keys do
			to[index] = names[key]
		end

		table.insert(ran.parts, `block {table.concat(to, ",")} {buffer.tostring(data)}`)
		Harness._deliver(self, keys, data)
	end

	-- Each round's hand-ins, read as a worker reads them, for the delays they carry
	if workers then
		local Wire: any = Environment.load(WIRE)
		local pool: any = harness.pool
		local send: any = pool.send
		local hands: { any } = {}
		local seen: { number } = {}

		pool.send = function (self: any, worker: number, round: number, shared: buffer, own: buffer)
			for index: number = 1, Wire.readOwn(own, hands) do
				table.insert(seen, hands[index].delay)
			end

			if round == 1 then
				table.sort(seen)
				ran.delays = table.concat(seen, ",")
			end

			send(self, worker, round, shared, own)
		end
	end

	local clients: { any } = {}
	for index: number, delay: number in DELAYS do
		local client: any = harness:viewer(`Viewer{index}`)
		client.viewer.delay = delay
		names[client.viewer.key] = `Viewer{index}`
		clients[index] = client
	end

	clients[LAGGING].lag = 1

	local slots: { number } = {}
	for index: number = 1, PLAYERS do
		local turn: number = index / PLAYERS * 2 * math.pi
		slots[index] = harness:spawn("Player", vector.create(math.cos(turn), 0, math.sin(turn)) * RING)
	end

	local frames: { buffer } = {}
	local stop: () -> () = Harness.Taps.observe(clients[OBSERVED].viewer.key, function (_: number, data: buffer)
		table.insert(frames, data)
	end)

	for step: number = 1, RUNS do
		local pattern: number = step // PERIOD
		for viewer: number, client: any in clients do
			for player: number, slot: number in slots do
				harness:hide(client, slot, (player + viewer + pattern) % SPREAD == 0)
			end
		end

		for index: number, slot: number in slots do
			local turn: number = (index / PLAYERS + step * STRIDE / (2 * math.pi)) * 2 * math.pi
			harness.states[slot].position = vector.create(math.cos(turn), 0, math.sin(turn)) * RING
		end

		if step == SKIP_RUN then
			harness.tick += 1
		elseif step >= TELEPORT_RUN then
			local state: any = harness.states[slots[1]]
			state.position += TELEPORT
			if step == TELEPORT_RUN then
				state.epoch = (state.epoch + 1) % 256
			end
		end

		harness:run()

		for index: number, client: any in clients do
			for _, past: any in client.seen.pasts do
				ran.most[index] = math.max(ran.most[index], #past.ages)
			end
		end

		for _, frame: buffer in frames do
			table.insert(ran.parts, `frame {buffer.tostring(frame)}`)
		end

		table.clear(frames)
	end

	stop()

	return ran
end

return function (): (boolean, string | nil)
	local serial: Ran = run(nil)
	if serial.most[OBSERVED] ~= WIDE or serial.most[1] ~= NARROW then
		return false, `In process the reveals carried at most {table.concat(serial.most, ",")} records`
	end

	local frames: number = 0
	for _, part: string in serial.parts do
		if string.sub(part, 1, 5) == "frame" then
			frames += 1
		end
	end

	if frames == 0 then
		return false, "The sink took no frame"
	end

	local pooled: Ran = run(WORKERS)
	local sorted: { number } = table.clone(DELAYS)
	table.sort(sorted)
	local expected: string = table.concat(sorted, ",")

	if pooled.delays ~= expected then
		return false, `The workers' first hand-ins carried delays {pooled.delays}, not {expected}`
	elseif #pooled.parts ~= #serial.parts then
		return false, `On workers {#pooled.parts} blocks and frames went, not {#serial.parts} as in process`
	end

	for index: number, part: string in serial.parts do
		if pooled.parts[index] ~= part then
			return false, `On workers block or frame {index} of {#serial.parts} differs from in process`
		end
	end

	return true, nil
end
