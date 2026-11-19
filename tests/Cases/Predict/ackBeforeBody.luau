--[[
    An acknowledgment before the first OwnerState starts a body changes
    nothing, and nor does one no newer than the last read: a predictor sent
    them stays alike after every tick with one never sent them
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")
local Same = require("../../Fixtures/Codec/Same")

local ACK_BYTES: number = 5
local TICKS: number = 40 -- Frames run once the body starts
local LAG: number = 2 -- Commands the server's state trails the newest by
local DEPTH: number = 2 -- The queue each OwnerState gives, inside the band
local STALE_AT: number = 20 -- The frame after whose OwnerState the stale acknowledgments come
local EARLY_TICK: number = 500 -- Newer than the spawn's tick, so only the missing body keeps it out
local FULL_QUEUE: number = 9 -- Past the band and the ahead limit, which a clock that heard it would hold back for
local NUDGED_QUEUE: number = 4 -- Past the band's top, which a clock that heard it would nudge down for

-- An acknowledgment's bytes: the command, the tick and the queue depth
local function ack(command: number, tick: number, depth: number): buffer
	local data: buffer = buffer.create(ACK_BYTES)
	buffer.writeu16(data, 0, command)
	buffer.writeu16(data, 2, tick)
	buffer.writeu8(data, 4, depth)

	return data
end

-- Where the two predictors first differ in what a game or a test can read of them, or nil
local function differ(clean: any, probed: any): string?
	if #clean.moves ~= #probed.moves or clean.samples ~= probed.samples then
		return `{#clean.moves} and {#probed.moves} Moves went, from {clean.samples} and {probed.samples} samples`
	elseif #clean.corrections ~= #probed.corrections then
		return `{#clean.corrections} and {#probed.corrections} corrections were raised`
	elseif clean.Predict.drawn() ~= probed.Predict.drawn() then
		return `The bodies drew at ticks {clean.Predict.drawn()} and {probed.Predict.drawn()}`
	end

	local moved: string? = Same(clean.moves[#clean.moves], probed.moves[#probed.moves], "the newest Move")
	if moved then
		return moved
	end

	local cleanBody: any, probedBody: any = clean.Predict.state(), probed.Predict.state()
	if cleanBody == nil and probedBody == nil then
		return nil
	elseif cleanBody == nil or probedBody == nil then
		return "Only one of them had a body"
	end

	return Same(cleanBody, probedBody, "the drawn body")
end

return function (): (boolean, string | nil)
	local clean: any = Harness.new()
	local probed: any = Harness.new()

	-- Before any body: one acknowledgment would hold the clock back, and one would leave it nothing queued
	probed.Predict.receive(ack(9, EARLY_TICK, FULL_QUEUE))
	probed.Predict.receive(ack(10, EARLY_TICK + 1, 0))
	clean.frames(3)
	probed.frames(3)

	local before: string? = differ(clean, probed)
	if before then
		return false, `Before the first OwnerState: {before}`
	end

	clean.spawn()
	probed.spawn()

	for frame: number = 1, TICKS do
		clean.frames(1)
		probed.frames(1)

		local through: number = frame - LAG
		if through >= 1 then
			local server: any = clean.twin(through)
			clean.Predict.receive(clean.owner(server, DEPTH))
			probed.Predict.receive(probed.owner(server, DEPTH))

			-- The tick before and then the same tick again, each with a queue the clock would nudge down for
			if frame == STALE_AT then
				probed.Predict.receive(ack(server.command - 1, server.tick - 1, NUDGED_QUEUE))
				probed.Predict.receive(ack(server.command, server.tick, NUDGED_QUEUE))
			end
		end

		local differs: string? = differ(clean, probed)
		if differs then
			return false, `After frame {frame}: {differs}`
		end
	end

	return true, nil
end
