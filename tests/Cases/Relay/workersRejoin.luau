--[[
    A moderator removed and handed in again at once, still watching its
    target on a worker, keeps its watcher bit as the serial relay keeps it
    by key: every block, withheld block, tap frame and query stays the same
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local CENTER: vector = vector.create(1800, 0, 1800)
local MODERATOR_AT: vector = vector.create(-1800, 0, 1800)
local PLAYERS: number = 6
local HIDDEN: { number } = { 3, 4 } -- The players hidden from the target, which its watcher is sent withheld
local RUNS: number = 12
local WATCH_RUN: number = 2
local REMOVE_RUN: number = 6 -- The moderator is removed just before this run, which hands it in again

type Side = {
	Harness: any,
	harness: any,
	names: { [any]: string },
	clients: { [string]: any },
	keys: { any },
	log: { string },
	frames: { string },
}

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
			table.insert(built.keys, key)
			client.viewer.position = at
			if owned then
				client.viewer.slot = harness:spawn("Player", at)
				top = math.max(top, client.viewer.slot)
			end
		end
	end

	for index: number = 1, PLAYERS do
		join(`Player{index}`, CENTER + vector.create(index * 7, 0, (index % 2) * 9), true)
	end

	join("Moderator", MODERATOR_AT, false)

	for _, built: Side in sides do
		local target: any = built.clients.Player1
		for _, hidden: number in HIDDEN do
			built.harness:hide(target, built.clients[`Player{hidden}`].viewer.slot, true)
		end

		local function sink(_: number, data: buffer)
			table.insert(built.frames, buffer.tostring(data))
		end

		built.Harness.Taps.observe(built.clients.Moderator.viewer.key, sink)
		built.Harness.Taps.observeWithheld(target.viewer.key, sink)
	end

	local withheld: number = 0
	for run: number = 1, RUNS do
		for _, built: Side in sides do
			if run == WATCH_RUN then
				built.harness:watch(built.clients.Moderator, built.clients.Player1)
			elseif run == REMOVE_RUN then
				built.Harness.Relay.remove(built.clients.Moderator.viewer.key)
			end

			for _, client: any in built.clients do
				local slot: number? = client.viewer.slot
				if slot ~= nil then
					local state: any = built.harness.states[slot]
					state.position += vector.create(0.6, 0, -0.4)
					client.viewer.position = state.position
				end
			end

			built.log = {}
			built.frames = {}
			built.harness:run()
		end

		local why: string? = compare(`Run {run}'s send`, serial.log, workers.log)
			or compare(`Run {run}'s frame`, serial.frames, workers.frames)
			or compare(`Run {run}'s answer`, queries(serial, top), queries(workers, top))
		if why ~= nil then
			return false, why
		end

		for _, line: string in serial.log do
			if string.sub(line, 1, 8) == "withheld" then
				withheld += 1
			end
		end
	end

	if withheld == 0 then
		return false, "The target's watcher was sent no withheld block"
	end

	return true, nil
end
