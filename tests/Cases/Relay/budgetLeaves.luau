--[[
    In process, once a run reaches its relay budget the last viewers in its
    order, a quarter of them at most, get no block that run, and take their
    turns first in the next, ahead of where its rest begin, each carrying
    what it was owed
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local VIEWERS: number = 8 -- So a run may leave 2
local BUDGET: number = 7 -- Stand-in seconds, reached at the seventh viewer's read
local STEP: number = 1 -- Stand-in seconds each read of the clock moves on
local STRIDE: number = 0.1 -- Studs the targets move a run, back and forth, so each always has a change to send
local TARGETS: { vector } = { vector.create(0, 0, -100), vector.create(60, 0, -60) }

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local Relay: any = Harness.Relay
	harness.step = STEP

	local clients: { any } = {}
	for index: number = 1, VIEWERS do
		local client: any = harness:viewer(`Viewer{index}`)
		client.viewer.position = vector.create(index * 5, 0, 0)
		table.insert(clients, client)
	end

	local targets: { number } = {}
	for _, at: vector in TARGETS do
		table.insert(targets, harness:spawn("Player", at))
	end

	Relay.setBudget(BUDGET)
	harness:run()

	-- Run 1: the budget is reached at the seventh viewer's read, so the last two in the list wait
	for index: number, client: any in clients do
		local blocks: number = #client.seen.sizes
		if index <= VIEWERS - 2 and blocks == 0 then
			return false, `Viewer {index}, inside the budget, got no block on the first run`
		elseif index > VIEWERS - 2 and blocks ~= 0 then
			return false, `Viewer {index}, left by the budget, got {blocks} blocks on the first run`
		end
	end

	local passed: { any } = harness.passed
	if #passed ~= 2 or passed[1].key ~= clients[7].viewer.key or passed[2].key ~= clients[8].viewer.key then
		return false, `The first run passed {#passed} viewers to anti-ESP, not the seventh and eighth in turn`
	end

	-- Run 2, with the list reversed so the place the rest begin at, the seventh, holds the second viewer: the two left
	-- go first in the list's order, eighth then seventh, each with both targets' reveals it was owed, and nobody waits
	for _, slot: number in targets do
		harness.states[slot].position += vector.create(STRIDE, 0, 0)
	end

	local viewers: { any } = harness.viewers
	for index: number = 1, VIEWERS // 2 do
		viewers[index], viewers[VIEWERS + 1 - index] = viewers[VIEWERS + 1 - index], viewers[index]
	end

	harness:run()

	local sends: { { any } } = harness.sends
	if #sends < 3 or sends[1][1] ~= clients[8].viewer.key or sends[2][1] ~= clients[7].viewer.key then
		return false, "The second run's first blocks went to other than the two viewers the first left"
	elseif sends[3][1] ~= clients[2].viewer.key then
		return false, "The second run's rest began elsewhere than the second viewer, at the place the first left from"
	end

	for index: number = VIEWERS - 1, VIEWERS do
		local seen: any = clients[index].seen
		for _, slot: number in targets do
			if Harness.count(seen.reveals, slot) ~= 1 then
				return false, `Viewer {index} got no reveal of slot {slot} on the run after it was left`
			end
		end
	end

	for index: number, client: any in clients do
		if #client.seen.sizes == 0 then
			return false, `Viewer {index} got no block on the second run, which reached no budget`
		end
	end

	if #harness.passed ~= 0 then
		return false, `The second run, inside its budget, passed {#harness.passed} viewers to anti-ESP`
	end

	local left: number, over: number, halved: number = Relay.caps()
	if left ~= 2 or over ~= 1 or halved ~= 0 then
		return false, `The caps counted {left} left, {over} runs over and {halved} lowered, not 2, 1 and 0`
	end

	return true, nil
end
