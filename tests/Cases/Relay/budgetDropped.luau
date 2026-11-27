--[[
    Under a relay budget on a stand-in worker, a round given up counts as one
    run over with the viewers it left and passes none of them to anti-ESP, as
    none of its asks is replayed, and a round whose first turn threw counts
    alike, its failure raised after; either way the next run forces the
    viewers it left
--]]

--!strict
local Layouts = require("../../Fixtures/Relay/Layouts")

local VIEWERS: number = 8 -- So a run may leave 2, the last two in the list on the first run
local NO_SLOT: number = 4096 -- Constants.SLOTS, a slot the slot table never has, so a turn with it throws
local TARGET_AT: vector = vector.create(0, 0, -60) -- A player each viewer is first revealed on its first turn

-- A harness under a budget of 0 with its viewers and a target
local function rig(): (any, any, { any })
	local Harness: any = Layouts.harness()
	local harness: any = Harness.new(nil, nil, 1)
	local clients: { any } = {}
	for index: number = 1, VIEWERS do
		local client: any = harness:viewer(`Viewer{index}`)
		client.viewer.position = vector.create(index * 10, 0, 0)
		table.insert(clients, client)
	end

	harness:spawn("Player", TARGET_AT)
	Harness.Relay.setBudget(0)

	return Harness, harness, clients
end

-- Sends the next run's round without bringing it in
local function dispatch(Harness: any, harness: any)
	harness.passed = {}
	harness.tick += 1
	Harness.Relay.run(harness.tick, harness.viewers, harness.states, harness.commands, harness.platforms)
end

-- Why the run after the round the budget left the seventh and eighth viewers in did not force them, or nil
local function forcedNext(harness: any, clients: { any }): string?
	harness:run()

	if #harness.passed ~= 2 then
		return `The run after left {#harness.passed} viewers, not 2`
	end

	for _, call: any in harness.passed do
		if call.key == clients[7].viewer.key or call.key == clients[8].viewer.key then
			return `The run after left {call.key.Name}, which the round before had left`
		end
	end

	for index: number = 7, 8 do
		if #clients[index].seen.sizes == 0 then
			return `The run after sent nothing to viewer {index}, which the round before had left`
		end
	end

	return nil
end

-- A round given up
local function dropped(): string?
	local Harness: any, harness: any, clients: { any } = rig()
	dispatch(Harness, harness)
	Harness.Relay.drop()

	local left: number, over: number = Harness.Relay.caps()
	if left ~= 2 or over ~= 1 then
		return `A round given up counted {left} viewers left and {over} runs over, not 2 and 1`
	elseif #harness.passed ~= 0 then
		return `A round given up passed {#harness.passed} viewers to anti-ESP`
	end

	return forcedNext(harness, clients)
end

-- A round whose first viewer's turn throws, so its replay stops before the viewers it left
local function failed(): string?
	local Harness: any, harness: any, clients: { any } = rig()
	clients[1].viewer.slot = NO_SLOT
	dispatch(Harness, harness)
	harness.pool:deliver()

	local finished: boolean, failure: any = pcall(Harness.Relay.finish)
	if finished or not string.find(tostring(failure), "slot table's slots", 1, true) then
		return `A round whose first turn threw finished {finished}: {failure}`
	end

	local left: number, over: number = Harness.Relay.caps()
	if left ~= 2 or over ~= 1 then
		return `A round whose first turn threw counted {left} viewers left and {over} runs over, not 2 and 1`
	elseif #harness.passed ~= 0 then
		return `A round whose replay stopped at its first turn passed {#harness.passed} viewers left after it`
	end

	clients[1].viewer.slot = nil

	return forcedNext(harness, clients)
end

return function (): (boolean, string | nil)
	local why: string? = dropped()
	if why then
		return false, `Given up: {why}`
	end

	why = failed()
	if why then
		return false, `Thrown: {why}`
	end

	return true, nil
end
