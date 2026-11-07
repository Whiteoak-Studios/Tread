--[[
    Relay.counts gives the running totals of the records the tier ticks
    placed and of those a viewer's room left out: with room to spare every
    record a client reads past its reveals is counted sent and none cut, and
    with the soft budget leaving room for one record a tick the rest are cut
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local TICKS: number = 10
local SOFT: number = 64 * 1000
local ONE_RECORD: number = 27 -- A block's header and framing and one record
local MOVE: vector = vector.create(0.1, 0, 0) -- What each character moves a tick, so each is due on its tier ticks

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local Relay: any = Harness.Relay

	local client: any = harness:viewer("Viewer")
	client.viewer.slot = harness:spawn("Player", vector.zero)

	local others: { number } = {
		harness:spawn("Player", vector.create(30, 0, 0)),
		harness:spawn("Player", vector.create(-30, 0, 0)),
		harness:spawn("Player", vector.create(0, 0, 30)),
	}

	-- The reveals go first, each with its record, which the tier ticks never place
	harness:run()

	local sent: number, cut: number = Relay.counts()
	if sent ~= 0 or cut ~= 0 then
		return false, `The reveals' own records counted {sent} sent and {cut} cut`
	end

	local read: number = 0
	for _ = 1, TICKS do
		for _, slot: number in others do
			harness.states[slot].position += MOVE
		end

		harness:run()
		read += #client.seen.records
	end

	sent, cut = Relay.counts()
	if sent ~= read or cut ~= 0 then
		return false, `With room to spare the relay counted {sent} sent and {cut} cut, where the client read {read}`
	end

	harness.traffic = SOFT - ONE_RECORD

	local before: number, cutBefore: number = sent, cut
	read = 0
	for _ = 1, TICKS do
		for _, slot: number in others do
			harness.states[slot].position += MOVE
		end

		harness:run()
		read += #client.seen.records
	end

	sent, cut = Relay.counts()
	if sent - before ~= read then
		return false, `Near the soft budget the relay counted {sent - before} sent, where the client read {read}`
	elseif not (cut > cutBefore) then
		return false, "With room for one record a tick past the floors no record was counted cut"
	end

	return true, nil
end
