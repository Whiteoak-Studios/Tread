--[[
    A bot's Moves acknowledge its relay blocks as a player's client does:
    the newest sequence with a mask of the 16 before it, a block that comes
    late setting its bit, a jump past the mask clearing it, and the wrap
--]]

--!strict
local Harness = require("../../Fixtures/DevBot/Harness")

local SEED: number = 1

-- Each block's sequence in the order it arrives, then the acknowledgment and mask the next Move carries
type Step = { sequence: number, acknowledged: number, received: number }

local STEPS: { Step } = {
	{ sequence = 5, acknowledged = 5, received = 0 }, -- The first block starts the mask empty
	{ sequence = 6, acknowledged = 6, received = 0b1 }, -- 5 is just before
	{ sequence = 8, acknowledged = 8, received = 0b110 }, -- 6 and 5 two and three before, 7 still missing
	{ sequence = 7, acknowledged = 8, received = 0b111 }, -- 7 came late and sets its bit
	{ sequence = 8, acknowledged = 8, received = 0b111 }, -- A second copy changes nothing
	{ sequence = 4, acknowledged = 8, received = 0b1111 }, -- So does an older one inside the mask, setting its bit
	{ sequence = 30, acknowledged = 30, received = 0 }, -- A jump past the 16 the mask covers clears it
	{ sequence = 13, acknowledged = 30, received = 0 }, -- One older than the mask reaches is ignored
	{ sequence = 65535, acknowledged = 30, received = 0 }, -- Far behind across the wrap is older still
}

-- Across the wrap from 65535, 1 is two ahead
local WRAPPED: { Step } = {
	{ sequence = 65535, acknowledged = 65535, received = 0 },
	{ sequence = 1, acknowledged = 1, received = 0b10 },
}

local function run(harness: Harness.Loaded, steps: { Step }): string?
	local side: Harness.Side = Harness.side()
	local bot: any = harness.Bot.new(side.network, harness.context, function () end, nil, SEED)

	for index: number, step: Step in steps do
		side.listeners.Relay(Harness.relay(harness, step.sequence))
		bot:tick(index)

		local fired: Harness.Fired = side.fired[#side.fired]
		if fired.acknowledged ~= step.acknowledged or fired.received ~= step.received then
			local got: string = `{fired.acknowledged} with mask {fired.received}`
			return `After block {step.sequence} the Move acknowledged {got}, not {step.acknowledged} with {step.received}`
		end
	end

	bot:destroy()

	return nil
end

return function (): (boolean, string | nil)
	local harness: Harness.Loaded = Harness.load()

	local failed: string? = run(harness, STEPS) or run(harness, WRAPPED)
	if failed then
		return false, failed
	end

	return true, nil
end
