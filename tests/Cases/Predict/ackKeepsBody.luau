--[[
    An acknowledgment is read as an OwnerState that fits with nothing to
    shift: one input through two predictors, one sent each state whole and
    one its acknowledgment, stays alike after every tick and holds alike
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")
local Same = require("../../Fixtures/Codec/Same")

local TICKS: number = 60 -- Frames run, a command each
local LAG: number = 10 -- Commands the server's state trails the newest by, past the 8 a Move repeats
local PROBE_DEPTH: number = 2
local PROBE_OFF: vector = vector.create(5, 0, 0) -- How far off the probe's state puts the body, past any tolerance

-- The queue each state gives in turn, some past the band's top, so the clock nudges
local DEPTHS: { number } = { 2, 4, 4, 3, 1, 2, 4 }

-- Walk ahead, weaving side to side, and jump twice
local function input(command: any, sample: number)
	command.forward = 1
	command.right = sample % 20 < 10 and 0.5 or -0.5
	command.jump = sample == 15 or sample == 40
	command.fields.slot = 0
	command.fields.shots = {}
end

-- Where the two predictors first differ in what a game or a test can read of them, or nil
local function differ(full: any, acked: any): string?
	local fullMove: any, ackedMove: any = full.moves[#full.moves], acked.moves[#acked.moves]
	if #full.moves ~= #acked.moves or full.samples ~= acked.samples then
		return `{#full.moves} and {#acked.moves} Moves went, from {full.samples} and {acked.samples} samples`
	elseif fullMove.command ~= ackedMove.command or #fullMove.numbers ~= #ackedMove.numbers then
		return `The newest Moves carried command {fullMove.command} and {ackedMove.command}`
	elseif #full.corrections ~= 0 or #acked.corrections ~= 0 then
		return `{#full.corrections} and {#acked.corrections} corrections were raised`
	elseif full.Predict.drawn() ~= acked.Predict.drawn() then
		return `The bodies drew at ticks {full.Predict.drawn()} and {acked.Predict.drawn()}`
	end

	for index: number, check: number in fullMove.checks do
		if ackedMove.checks[index] ~= check then
			return `The newest Moves' command {fullMove.numbers[index]} carried checks {check} and {ackedMove.checks[index]}`
		end
	end

	local drawn: string? = Same(full.Predict.state(), acked.Predict.state(), "the drawn body")
	if drawn then
		return drawn
	end

	local fullEye: vector, fullLook: vector = full.Predict.eye()
	local ackedEye: vector, ackedLook: vector = acked.Predict.eye()
	if fullEye ~= ackedEye or fullLook ~= ackedLook then
		return `The eyes were {fullEye} and {ackedEye}, looking {fullLook} and {ackedLook}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local full: any = Harness.new()
	local acked: any = Harness.new()
	full.input = input
	acked.input = input
	full.spawn()
	acked.spawn()

	local states: { [number]: any } = {}
	local tick: number = 0

	for frame: number = 1, TICKS do
		full.frames(1)
		acked.frames(1)

		local through: number = frame - LAG
		if through >= 1 then
			local server: any = full.twin(through)
			local depth: number = DEPTHS[frame % #DEPTHS + 1]
			states[through] = full.copy(server)
			tick = server.tick

			full.Predict.receive(full.owner(server, depth))
			acked.Predict.receive(acked.ack(server, depth))
		end

		local differs: string? = differ(full, acked)
		if differs then
			return false, `After frame {frame}: {differs}`
		end
	end

	-- A newer state for the newest command the last acknowledgment let go finds it held by neither
	local released: number = TICKS - LAG
	local probe: any = full.copy(states[released])
	probe.position += PROBE_OFF
	probe.tick = tick + 1

	full.Predict.receive(full.owner(probe, PROBE_DEPTH))
	acked.Predict.receive(acked.owner(probe, PROBE_DEPTH))

	local fullCorrection: any, ackedCorrection: any = full.corrections[1], acked.corrections[1]
	if #full.corrections ~= 1 or not fullCorrection.flagged then
		return false, `The probe for released command {released} raised no flagged correction, so it found it held`
	elseif #acked.corrections ~= 1 or ackedCorrection.size ~= fullCorrection.size or not ackedCorrection.flagged then
		return false, `After acknowledgments the probe found command {released} held, or replayed otherwise`
	end

	-- Both replayed the commands they still held, the same ones
	local drawn: string? = Same(full.Predict.state(), acked.Predict.state(), "the replayed body")
	if drawn then
		return false, drawn
	end

	return true, nil
end
