--[[
    A workers' round still out past the timeout is given up at the next
    Heartbeat, counted, its tick framed with no worker block and released,
    even when its stage threw after holding; the runs after match in process
--]]

--!strict
local Lockstep = require("../../Fixtures/Server/Lockstep")

local WORKERS: number = 2
local TIMEOUT: number = 1e-6 -- Seconds, so a round not delivered by the next Heartbeat is past it
local TICKS: number = 12
local DROP_AT: number = 4 -- The tick whose round is never delivered
local THROW_AT: number = 8 -- The tick whose stage throws after holding, its round never delivered
local PLANTED: string = "A planted failure after the relay's dispatch"
local NAMES: { string } = { "Client", "Seen", "Hidden", "Moderator" }

type Side = Lockstep.Side

-- Whether a tick's round is given up on the workers
local function lost(tick: number): boolean
	return tick == DROP_AT or tick == THROW_AT
end

-- Why two lists of frames, one a tick, differ on a tick whose round was kept, or nil when none does
local function differ(what: string, serial: { string }, workers: { string }): string?
	if #serial < TICKS or #workers < TICKS then
		return `{what}: {#serial} serially and {#workers} on the workers, not {TICKS} each`
	end

	for tick: number = 1, TICKS do
		if not lost(tick) and serial[tick] ~= workers[tick] then
			return `{what} {tick} differs serially and on the workers`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local serial: Side = Lockstep.side(nil)
	local workers: Side = Lockstep.side({ workers = WORKERS, timeout = TIMEOUT })
	workers.server:stats()

	-- The workers' stage throws once its tick's turns are out
	local relay: any = workers.Characters.relay
	workers.Characters.relay = function (relayTick: number, tick: number)
		relay(relayTick, tick)
		if relayTick == THROW_AT then
			error(PLANTED)
		end
	end

	local serialBlocks: { number } = { [0] = 0 } -- The client's blocks in process after each beat

	for beat: number = 1, TICKS do
		Lockstep.beat(serial, 1)
		Lockstep.beat(workers, 1)
		serialBlocks[beat] = #serial.blocks

		-- The beat after a round left out gave it up, framed its tick and ran the next
		local given: number = beat - 1
		local framed: string? = workers.frames.Client[given]
		if lost(given) and framed == nil then
			return false, `The beat after tick {given}'s round was left out gave that tick no frame`
		elseif lost(given) and framed ~= nil then
			local read: any = workers.server:stats()
			local frame: any = workers.Tap.read(buffer.fromstring(framed))
			if read.relayDropped ~= 1 or workers.Tick.counts() ~= beat then
				return false, `After tick {given}'s round was left out, stats gave {read.relayDropped} dropped`
			elseif #frame.blocks ~= 0 or frame.owner == nil or frame.tick ~= given then
				local held: string = `{#frame.blocks} blocks, and an OwnerState {frame.owner}`
				return false, `Tick {given}'s frame on the workers had {held}`
			end
		end

		if not lost(beat) then
			workers.pool:deliver()
		end
	end

	Lockstep.beat(workers, 1)

	for _, name: string in NAMES do
		local why: string? = differ(`{name}'s tap frame`, serial.frames[name], workers.frames[name])
		if why then
			return false, why
		end
	end

	local why: string? = differ("The withheld frame", serial.withheld, workers.withheld)
		or Lockstep.differ("The client's OwnerState", serial.owners, workers.owners, #serial.owners)
	if why then
		return false, why
	end

	-- The client's blocks are the in-process ones but those of the ticks given up
	local kept: { string } = {}
	for tick: number = 1, TICKS do
		if not lost(tick) then
			table.move(serial.blocks, serialBlocks[tick - 1] + 1, serialBlocks[tick], #kept + 1, kept)
		end
	end

	why = Lockstep.differ("The client's block", kept, workers.blocks, #kept)
	if why then
		return false, why
	elseif #workers.blocks ~= #kept or #kept == #serial.blocks then
		return false, `The client had {#workers.blocks} blocks on the workers, {#kept} kept of {#serial.blocks}`
	end

	-- The throw reported as the relay stage's once, and no other failure, the drops raising none
	local reported: { number | string } = workers.rig:reported("stage")
	if #reported ~= 1 or reported[1] ~= "relay" or #serial.rig:reported("stage") ~= 0 then
		return false, `The stage reports were {#reported} on the workers, the first {reported[1]}`
	elseif workers.Tick.finishes().held ~= TICKS then
		return false, `The workers' server kept {workers.Tick.finishes().held} finishes, not one a tick`
	end

	return true, nil
end
