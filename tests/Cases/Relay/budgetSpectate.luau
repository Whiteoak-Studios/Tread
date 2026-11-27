--[[
    Under a relay budget of 0, a spectate that starts the run after the
    budget left the watcher, one that ends with the watcher back on its own
    view, and one that starts the run after the budget left the target, in
    process and on 2 stand-in workers: the watcher gets every block its
    target does, and neither a watched target nor a watcher back from its
    spectate is left
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local LOOK_FOR: number = 8 -- The most runs waited for the budget to leave a given viewer
local WATCHED_RUNS: number = 4 -- Runs each spectate lasts
local STRIDE: number = 0.1 -- Studs the player moves a run, so every viewer always has a record to send
local PLAYER_AT: vector = vector.create(0, 0, -60)

-- Whether a run passed a key's viewer to anti-ESP, which is how the case knows the budget left it
local function left(harness: any, key: any): boolean
	for _, call: any in harness.passed do
		if call.key == key then
			return true
		end
	end

	return false
end

-- Runs a spectate's runs and gives why it went wrong, or nil
local function drive(Harness: any, workers: number?): string?
	local harness: any = Harness.new(nil, nil, workers)
	local names: { string } = { "A", "B", "C", "Target", "Watcher" }
	local clients: { [string]: any } = {}
	for index: number, name: string in names do
		local client: any = harness:viewer(name)
		client.viewer.position = vector.create(index * 10, 0, 0)
		clients[name] = client
	end

	local target: any = clients.Target
	local watcher: any = clients.Watcher
	local player: number = harness:spawn("Player", PLAYER_AT)
	Harness.Relay.setBudget(0)

	local run: number = 0
	local function step()
		run += 1
		harness.states[player].position += vector.create(run % 2 == 0 and -STRIDE or STRIDE, 0, 0)
		harness:run()
	end

	-- Runs until the budget leaves a viewer, and gives whether it did
	local function runUntilLeft(client: any): boolean
		for _ = 1, LOOK_FOR do
			step()
			if left(harness, client.viewer.key) then
				return true
			end
		end

		return false
	end

	-- Every block the target was sent this run went to its watcher too, and neither was left
	local function copied(): string?
		local sent: number = 0
		for _, keys: { any } in harness.sends do
			if keys[1] == target.viewer.key then
				sent += 1
				if keys[2] ~= watcher.viewer.key then
					return `Run {run} sent the target a block its watcher was not given`
				end
			end
		end

		if sent == 0 then
			return `Run {run} sent the watched target nothing`
		elseif left(harness, target.viewer.key) or left(harness, watcher.viewer.key) then
			return `Run {run} left the watched target or its watcher`
		end

		return nil
	end

	-- A spectate that starts the run after the watcher was left
	if not runUntilLeft(watcher) then
		return `The budget never left the watcher in {LOOK_FOR} runs`
	end

	harness:watch(watcher, target)
	for _ = 1, WATCHED_RUNS do
		step()
		local why: string? = copied()
		if why then
			return why
		end
	end

	-- The spectate's end: the watcher back on its own view takes its turn
	harness:watch(watcher, nil)
	step()
	if left(harness, watcher.viewer.key) then
		return `Run {run} left the watcher on the run it came back from its spectate`
	elseif #watcher.seen.sizes == 0 then
		return `Run {run} sent the watcher back from its spectate nothing of its own view`
	end

	-- A spectate that starts the run after the target was left
	if not runUntilLeft(target) then
		return `The budget never left the target in {LOOK_FOR} runs`
	end

	harness:watch(watcher, target)
	for _ = 1, WATCHED_RUNS do
		step()
		local why: string? = copied()
		if why then
			return why
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local ran: boolean, why: any = pcall(drive, Environment.load(HARNESS), nil)
	if not ran or why then
		return false, `In process: {why}`
	end

	ran, why = pcall(drive, Layouts.harness(), WORKERS)
	if not ran or why then
		return false, `On {WORKERS} workers: {why}`
	end

	return true, nil
end
