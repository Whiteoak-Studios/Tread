--[[
    A relay budget the runs never reach sends every block byte for byte as no
    budget does, whose digest is pinned, in process and on 1 and 2 stand-in
    workers, through skipped relay ticks and a viewer missing from a run's
    list, leaving nobody
--]]

--!strict
local serde = require("@lune/serde")

local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local MOST_WORKERS: number = 2
local RUNS: number = 30
local SKIPS: { [number]: boolean } = { [10] = true, [20] = true } -- Runs a relay tick is skipped before
local ABSENT: number = 15 -- The run the fourth viewer is missing from the list
local BUDGET: number = 1 -- Seconds of the stand-in clock, which stands still, so no run reaches it
local STRIDE: number = 0.1 -- Studs every body moves a run, back and forth, so each always has a change to send

-- The blocks' digest with no budget, measured from a turn that takes one run's credit as the relay always has, so a
-- turn's credit counting the ticks since its last when no run left it shows here as well as under a budget
local EXPECTED: string = "156573367bad001d6c18f33be3247b26c05985874e84670eeb85d6152487e9bf"

-- Five viewers, two with bodies, and players in both of the example's bands from them
local VIEWERS: { { name: string, at: vector, owned: boolean } } = {
	{ name = "A", at = vector.zero, owned = true },
	{ name = "B", at = vector.create(50, 0, 0), owned = true },
	{ name = "C", at = vector.create(0, 0, 30), owned = false },
	{ name = "D", at = vector.create(-40, 0, 0), owned = false },
	{ name = "E", at = vector.create(20, 0, -20), owned = false },
}
local TARGETS: { vector } = { vector.create(0, 0, -100), vector.create(0, 0, -400), vector.create(300, 0, 0) }

-- What one side's runs gave: the digest of every block in send order, and what the budget read and counted
type Ran = { digest: string, reads: number, left: number, over: number, passed: number }

local function drive(Harness: any, workers: number?, budget: number?): Ran
	local harness: any = Harness.new(nil, nil, workers)
	local Relay: any = Harness.Relay
	local names: { [any]: string } = {}
	local parts: { string } = {}

	harness._deliver = function (self: any, keys: { any }, data: buffer)
		local recipients: { string } = {}
		for index: number, key: any in keys do
			recipients[index] = names[key]
		end

		table.insert(parts, `{table.concat(recipients, ",")} {buffer.tostring(data)}`)
		Harness._deliver(self, keys, data)
	end

	local bodies: { number } = {}
	local clients: { any } = {}
	for _, viewer: { name: string, at: vector, owned: boolean } in VIEWERS do
		local client: any = harness:viewer(viewer.name)
		names[client.viewer.key] = viewer.name
		client.viewer.position = viewer.at
		if viewer.owned then
			client.viewer.slot = harness:spawn("Player", viewer.at)
			table.insert(bodies, client.viewer.slot)
		end

		table.insert(clients, client)
	end

	for _, at: vector in TARGETS do
		table.insert(bodies, harness:spawn("Player", at))
	end

	Relay.setBudget(budget)

	local absent: any = clients[4].viewer
	local passed: number = 0
	for run: number = 1, RUNS do
		local step: number = run % 2 == 0 and -STRIDE or STRIDE
		for _, slot: number in bodies do
			harness.states[slot].position += vector.create(step, 0, 0)
		end

		if SKIPS[run] then
			harness.tick += 1
		end

		if run == ABSENT then
			table.remove(harness.viewers, 4)
		elseif run == ABSENT + 1 then
			table.insert(harness.viewers, 4, absent)
		end

		table.insert(parts, `run {run}`)
		harness:run()
		passed += #harness.passed
	end

	local left: number, over: number = Relay.caps()

	return {
		digest = serde.hash("sha256", table.concat(parts, "\n")),
		reads = harness.reads,
		left = left,
		over = over,
		passed = passed,
	}
end

-- Why a side under the budget gave other than the side with none, or nil when it gave the same and left nobody
local function judge(ran: Ran, plain: Ran, where: string): string?
	if ran.digest ~= plain.digest then
		return `{where} the blocks under a budget never reached digest to {ran.digest}, not {plain.digest} with none`
	elseif ran.reads == 0 then
		return `{where} the budget never read the relay's clock, so nothing it judges ran`
	elseif ran.left ~= 0 or ran.over ~= 0 or ran.passed ~= 0 then
		return `{where} a budget never reached left {ran.left}, judged {ran.over} runs over and passed {ran.passed}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local plain: Ran = drive(Environment.load(HARNESS), nil, nil)
	if plain.reads ~= 0 then
		return false, `With no budget the relay read its clock {plain.reads} times`
	elseif plain.digest ~= EXPECTED then
		return false, `With no budget the blocks digest to {plain.digest}, not the pinned {EXPECTED}`
	end

	local why: string? = judge(drive(Environment.load(HARNESS), nil, BUDGET), plain, "In process")
	if why then
		return false, why
	end

	for workers: number = 1, MOST_WORKERS do
		local unbudgeted: Ran = drive(Layouts.harness(), workers, nil)
		if unbudgeted.digest ~= plain.digest then
			return false,
				`On {workers} workers with no budget the blocks digest to {unbudgeted.digest}, not as in process`
		end

		why = judge(drive(Layouts.harness(), workers, BUDGET), plain, `On {workers} workers`)
		if why then
			return false, why
		end
	end

	return true, nil
end
