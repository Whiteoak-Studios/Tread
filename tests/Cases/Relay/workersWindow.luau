--[[
    Calls made while a round is out on the workers give the next run a
    serial relay's calls made after its run give, and isSent, viewersOf and
    keyframe inside that window answer as the serial relay did before its run
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator
local MULTIPLIER: number = 16807
local SEED: number = 707
local CENTER: vector = vector.create(600, 0, -600)
local SPREAD: number = 90
local STEP: number = 1.2 -- Studs a body may move along each axis a run
local TURN: number = 0.3 -- Radians a body may turn either way a run
local HIDDEN: number = 0.3 -- The share of pairs anti-ESP hides at each shuffle
local SHUFFLE: number = 5
local PLAYERS: number = 10
local RUNS: number = 26
local NEAR: number = 40 -- A render distance a call sets, inside the spread
local FAR: number = 1000
local SLEEPER_AT: vector = CENTER + vector.create(20, 0, 20)
local SLEEPER_MOVE: vector = vector.create(3, 0, -2)
local MODERATOR_AT: vector = vector.create(-3000, 0, 3000)

-- The runs whose window carries each call, as its name says
local WATCH_RUN: number = 4 -- The moderator watches from this run's next, its revealAll in this one's window
local LOOK_RUN: number = 6
local SHOT_RUN: number = 7
local SLEEPER_RUN: number = 8
local NEAR_RUN: number = 9
local INVISIBLE_RUN: number = 10
local HELD_RUN: number = 11
local JOIN_RUN: number = 12 -- A newcomer's view made by setDistance in the window, before its first run
local FIRST_SIGHT_RUN: number = 13 -- The newcomer's first run sends it the sleeper, which a reveal in its window then finds
local VISIBLE_RUN: number = 14
local RETURN_RUN: number = 16
local FAR_RUN: number = 18
local LEAVE_RUN: number = 20
local REMOVE_TWICE_RUN: number = 22 -- A leave and another call on the same viewer in one window

type Generator = () -> number

-- One harness, the names of its keys, and what it sent and its sinks were handed this run
type Side = {
	Harness: any,
	harness: any,
	names: { [any]: string },
	clients: { [string]: any },
	keys: { any }, -- Every key ever joined, in join order
	log: { string },
	frames: { [string]: { string } },
}

local function generator(seed: number): Generator
	local value: number = seed

	return function (): number
		value = value * MULTIPLIER % MODULUS

		return value / MODULUS
	end
end

local function side(workers: number?): Side
	local Harness: any
	if workers then
		Harness = Layouts.harness()
	else
		Harness = Environment.load(HARNESS)
	end

	local built: Side = {
		Harness = Harness,
		harness = Harness.new(nil, nil, workers),
		names = {},
		clients = {},
		keys = {},
		log = {},
		frames = {},
	}

	local function label(keys: { any }): string
		local names: { string } = {}
		for index: number, key: any in keys do
			names[index] = built.names[key]
		end

		return table.concat(names, ",")
	end

	built.harness._deliver = function (self: any, keys: { any }, data: buffer)
		table.insert(built.log, `block {label(keys)} {buffer.tostring(data)}`)
		Harness._deliver(self, keys, data)
	end

	built.harness._withhold = function (self: any, keys: { any }, data: buffer)
		table.insert(built.log, `withheld {label(keys)} {buffer.tostring(data)}`)
		Harness._withhold(self, keys, data)
	end

	return built
end

-- Every answer a side's queries give now: each key's keyframe and isSent for every slot, and each slot's viewersOf
local function queries(built: Side, top: number): { string }
	local Relay: any = built.Harness.Relay
	local answers: { string } = {}

	for _, key: any in built.keys do
		local name: string = built.names[key]
		table.insert(answers, `keyframe {name} {buffer.tostring(Relay.keyframe(key))}`)

		local sent: { string } = {}
		for slot: number = 0, top do
			if Relay.isSent(key, slot) then
				table.insert(sent, `{slot}`)
			end
		end

		table.insert(answers, `isSent {name} {table.concat(sent, ",")}`)
	end

	for slot: number = 0, top do
		local names: { string } = {}
		for index: number, key: any in Relay.viewersOf(slot) do
			names[index] = built.names[key]
		end

		-- As a set, since a key that leaves and comes back may come back elsewhere in a relay's walk of its views
		table.sort(names)
		table.insert(answers, `viewersOf {slot} {table.concat(names, ",")}`)
	end

	return answers
end

-- Why two lists of lines differ, or nil when they match
local function compare(what: string, serial: { string }, workers: { string }): string?
	for index: number = 1, math.max(#serial, #workers) do
		if serial[index] ~= workers[index] then
			local expected: string = (serial[index] or "nothing"):sub(1, 60)
			local got: string = (workers[index] or "nothing"):sub(1, 60)

			return `{what} {index} was "{expected}" serially and "{got}" on the workers`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local serial: Side = side(nil)
	local workers: Side = side(WORKERS)
	local sides: { Side } = { serial, workers }
	local random: Generator = generator(SEED)
	local top: number = 0

	-- One key object for both sides, so both relays' answers name the same keys
	local function join(name: string, at: vector, owned: boolean)
		local key: { Name: string } = { Name = name }
		for _, built: Side in sides do
			local harness: any = built.harness
			local client: any = harness:viewer(name)
			local made: any = client.viewer.key
			client.viewer.key = key
			harness.clients[key], harness.clients[made] = client, nil
			harness.hidden[key], harness.hidden[made] = harness.hidden[made], nil
			harness.reasons[key], harness.reasons[made] = harness.reasons[made], nil

			built.names[key] = name
			built.clients[name] = client
			table.insert(built.keys, client.viewer.key)
			client.viewer.position = at
			if owned then
				client.viewer.slot = built.harness:spawn("Player", at)
				top = math.max(top, client.viewer.slot)
			end
		end
	end

	-- A viewer leaves the list both sides hand in
	local function leave(built: Side, name: string)
		local viewers: { any } = built.harness.viewers
		table.remove(viewers, table.find(viewers, built.clients[name].viewer))
	end

	for index: number = 1, PLAYERS do
		join(`Player{index}`, CENTER + vector.create((random() - 0.5) * SPREAD, 0, (random() - 0.5) * SPREAD), true)
	end

	join("Moderator", MODERATOR_AT, false)

	local sleeper: number = 0
	for _, built: Side in sides do
		sleeper = built.harness:spawn("Sleeper", SLEEPER_AT)
	end
	top = math.max(top, sleeper)

	for _, built: Side in sides do
		local function sink(_: number, data: buffer)
			table.insert(built.frames.target, buffer.tostring(data))
		end

		built.frames.target = {}
		built.Harness.Taps.observe(built.clients.Player2.viewer.key, sink)
	end

	-- The calls made after the serial run, and inside the workers' window, alike
	local function calls(built: Side, run: number)
		local Relay: any = built.Harness.Relay
		local clients: { [string]: any } = built.clients

		if run == WATCH_RUN then
			Relay.revealAll(clients.Player2.viewer.key)
		elseif run == LOOK_RUN then
			Relay.setLook(clients.Player3.viewer.slot, { head = 2, shirt = 300 })
		elseif run == SHOT_RUN then
			Relay.shotNear(clients.Player1.viewer.key, clients.Player4.viewer.slot)
		elseif run == SLEEPER_RUN then
			built.harness.states[sleeper].position += SLEEPER_MOVE
			Relay.reveal(sleeper)
		elseif run == NEAR_RUN then
			Relay.setDistance(clients.Player5.viewer.key, NEAR)
		elseif run == INVISIBLE_RUN then
			Relay.setInvisible(clients.Player6.viewer.slot, true)
		elseif run == JOIN_RUN then
			Relay.setDistance(clients.Newcomer.viewer.key, NEAR)
		elseif run == FIRST_SIGHT_RUN then
			Relay.reveal(sleeper)
		elseif run == VISIBLE_RUN then
			Relay.setInvisible(clients.Player6.viewer.slot, false)
			Relay.setLook(clients.Player7.viewer.slot, { face = 11 })
		elseif run == RETURN_RUN then
			Relay.revealAll(clients.Moderator.viewer.key)
		elseif run == FAR_RUN then
			Relay.setDistance(clients.Player5.viewer.key, FAR)
		elseif run == LEAVE_RUN then
			leave(built, "Player8")
			Relay.remove(clients.Player8.viewer.key)
		elseif run == REMOVE_TWICE_RUN then
			leave(built, "Player9")
			Relay.shotNear(clients.Player9.viewer.key, clients.Player1.viewer.slot)
			Relay.remove(clients.Player9.viewer.key)
			Relay.setDistance(clients.Player9.viewer.key, NEAR)
			Relay.remove(clients.Player9.viewer.key)
		end
	end

	local windows: number = 0
	local refusals: { string } = {}
	local realPool: any = workers.harness.pool
	local window: () -> () = function () end

	-- The workers' window: what Harness.run does between the relay's run and its pool's delivery
	workers.harness.pool = {
		deliver = function (_: any)
			window()
			realPool:deliver()
		end,
	}

	local held: number = 0
	for run: number = 1, RUNS do
		if run == WATCH_RUN + 1 then
			for _, built: Side in sides do
				built.harness:watch(built.clients.Moderator, built.clients.Player2)
			end
		elseif run == RETURN_RUN + 1 then
			for _, built: Side in sides do
				built.harness:watch(built.clients.Moderator, nil)
			end
		elseif run == JOIN_RUN then
			join("Newcomer", CENTER, true)
			for _, built: Side in sides do
				leave(built, "Newcomer")
			end
		elseif run == JOIN_RUN + 1 then
			for _, built: Side in sides do
				table.insert(built.harness.viewers, built.clients.Newcomer.viewer)
			end
		end

		if run == HELD_RUN then
			held = serial.clients.Player4.viewer.slot
			for _, built: Side in sides do
				built.harness.states[held].held = { item = 7, skin = 2 }
			end
		end

		-- Every body moves alike on both sides, the hides reshuffled alike
		local shuffled: boolean = run % SHUFFLE == 1
		local moves: { [number]: { number } } = {}
		local hides: { [string]: { [number]: boolean } } = {}
		for name: string, client: any in serial.clients do
			local slot: number? = client.viewer.slot
			if slot ~= nil then
				moves[slot] = { (random() - 0.5) * 2 * STEP, (random() - 0.5) * 2 * STEP, (random() - 0.5) * 2 * TURN }
			end

			if shuffled then
				hides[name] = {}
				for _, other: any in serial.clients do
					if other ~= client and other.viewer.slot ~= nil then
						hides[name][other.viewer.slot] = random() < HIDDEN
					end
				end
			end
		end

		for _, built: Side in sides do
			for slot: number, move: { number } in moves do
				local state: any = built.harness.states[slot]
				state.position += vector.create(move[1], 0, move[2])
				state.facing += move[3]
			end

			for name: string, client: any in built.clients do
				local slot: number? = client.viewer.slot
				if slot ~= nil then
					local state: any = built.harness.states[slot]
					client.viewer.position = state.position
					client.viewer.look = vector.create(-math.sin(state.facing), 0, -math.cos(state.facing))
				end

				for otherSlot: number, on: boolean in hides[name] or {} do
					built.harness:hide(client, otherSlot, on)
				end
			end

			built.log = {}
			built.frames.target = {}
		end

		-- The serial relay's answers before its run, which the workers' window gives back
		local before: { string } = queries(serial, top)
		serial.harness:run()
		calls(serial, run)

		local why: string? = nil
		window = function ()
			windows += 1
			why = compare(`Run {run}'s window answer`, before, queries(workers, top))

			local ran: boolean, failure: any = pcall(workers.Harness.Relay.run, run + 1, {}, {}, {})
			if ran or not string.find(`{failure}`, "still out", 1, true) then
				table.insert(refusals, `Relay.run inside the window gave {ran} {failure}`)
			end

			calls(workers, run)
		end

		workers.harness:run()
		why = why
			or compare(`Run {run}'s send`, serial.log, workers.log)
			or compare(`Run {run}'s frame`, serial.frames.target, workers.frames.target)
			or compare(`Run {run}'s answer`, queries(serial, top), queries(workers, top))

		if why ~= nil then
			return false, why
		end
	end

	if windows ~= RUNS then
		return false, `{windows} of {RUNS} runs had a window`
	elseif #refusals > 0 then
		return false, refusals[1]
	end

	local dropped: boolean, failure: any = pcall(workers.Harness.Relay.drop)
	if dropped or not string.find(`{failure}`, "no round out", 1, true) then
		return false, `Relay.drop with no round out gave {dropped} {failure}`
	end

	return true, nil
end
