--[[
    With relay workers each relay tick dispatches and holds, its OwnerStates
    sent at once, and the next Heartbeat starts with its blocks and frames,
    every one as the in-process server's; stats reads both kinds of ring
--]]

--!strict
local Lockstep = require("../../Fixtures/Server/Lockstep")

local WORKERS: number = 2
local TIMEOUT: number = 60 -- Seconds, far past when any round here lands
local TICKS: number = 10
local HELD_AT: number = 4 -- The beat after which the held server is read and run a Heartbeat that owes no tick
local QUARTER: number = 0.25 -- A tick's share that a Heartbeat owing no tick takes
local TEAM: number = 7
local NAMES: { string } = { "Client", "Seen", "Hidden", "Moderator" }

type Side = Lockstep.Side

-- A side's stage by its name in the tick's list
local function stageOf(side: Side, name: string): any
	for _, stage: any in side.Tick.stages() do
		if stage.name == name then
			return stage
		end
	end

	error(`The tick has no {name} stage`)
end

-- Every stage the stage reports gave, as their measurements
local function failures(side: Side): string
	local measured: { string } = {}
	for _, measurement: number | string in side.rig:reported("stage") do
		table.insert(measured, `{measurement}`)
	end

	return table.concat(measured, ", ")
end

return function (): (boolean, string | nil)
	local serial: Side = Lockstep.side(nil)
	local workers: Side = Lockstep.side({ workers = WORKERS, timeout = TIMEOUT })

	-- In process the read has no finishes, and with workers an empty ring reads 0
	local serialRead: any = serial.server:stats()
	local workersRead: any = workers.server:stats()
	if serialRead.relayFinish ~= nil or serialRead.relayDropped ~= nil then
		return false, "The in-process server's stats gave relayFinish or relayDropped"
	elseif
		workersRead.relayFinish == nil
		or workersRead.relayFinish.last ~= 0
		or workersRead.relayFinish.p95 ~= 0
		or workersRead.relayDropped ~= 0
	then
		return false, "Before any finish the workers' stats gave no empty relayFinish and no relayDropped of 0"
	end

	local serialBlocks: { number } = { [0] = 0 } -- The client's blocks in process after each beat
	local slices: any = stageOf(workers, "antiEsp")

	for beat: number = 1, TICKS do
		Lockstep.beat(serial, 1)
		Lockstep.beat(workers, 1)
		serialBlocks[beat] = #serial.blocks

		if #workers.owners ~= #serial.owners then
			local counts: string = `{#workers.owners} OwnerStates on the workers and {#serial.owners} in process`
			return false, `After beat {beat} the client had {counts}`
		elseif #workers.blocks ~= serialBlocks[beat - 1] then
			local behind: string = `not the {serialBlocks[beat - 1]} it had in process a beat before`
			return false, `After beat {beat} the client had {#workers.blocks} blocks on the workers, {behind}`
		end

		if beat == HELD_AT then
			-- Read while held: the dispatch's time in the relay stage's ring, the finishes before it in their own
			local read: any = workers.server:stats()
			local finishes: any = workers.Tick.finishes()
			local relay: any = stageOf(workers, "relay")
			if
				finishes.held ~= beat - 1
				or read.relayFinish.last ~= finishes.last
				or relay.ticks[relay.held] ~= beat
			then
				local rings: string = `{finishes.held} finishes, the relay's newest at tick {relay.ticks[relay.held]}`
				return false, `Read while beat {beat}'s tick was held, the workers' server had {rings}`
			end

			-- The client and the bot it can't see join a team while the round is out, which in process comes after
			-- the tick's asks, so the round's taps still give the bot as hidden
			for _, side: Side in { serial, workers } do
				side.characters.Client:setTeam(TEAM)
				side.characters.Hidden:setTeam(TEAM)
			end

			-- A Heartbeat owing no tick runs nothing while the round is out, the slice included
			local ran: number = workers.Tick.counts()
			local sliced: number = slices.held
			local framed: number = #workers.frames.Client
			Lockstep.beat(serial, QUARTER)
			Lockstep.beat(workers, QUARTER)

			if workers.Tick.counts() ~= ran or slices.held ~= sliced or #workers.frames.Client ~= framed then
				return false, "A Heartbeat while the workers' round was out ran a tick, a slice or a frame"
			end
		end

		workers.pool:deliver()
	end

	-- The last tick's finish, which runs the next tick after it
	Lockstep.beat(workers, 1)

	for _, name: string in NAMES do
		local why: string? = Lockstep.differ(`{name}'s tap frame`, serial.frames[name], workers.frames[name], TICKS)
		if why then
			return false, why
		end
	end

	local why: string? = Lockstep.differ("The withheld frame", serial.withheld, workers.withheld, TICKS)
		or Lockstep.differ("The client's block", serial.blocks, workers.blocks, #serial.blocks)
		or Lockstep.differ("The client's OwnerState", serial.owners, workers.owners, #serial.owners)
	if why then
		return false, why
	elseif #workers.blocks ~= #serial.blocks then
		return false, `The client had {#workers.blocks} blocks on the workers and {#serial.blocks} in process`
	end

	-- The moderator's withheld frames carried the client's culled bot, and the frames were never empty
	local carried: boolean = false
	for _, frame: string in serial.withheld do
		if #serial.Tap.read(buffer.fromstring(frame)).blocks > 0 then
			carried = true
		end
	end

	if not carried or #serial.blocks < TICKS then
		return false, `The withheld frames carried a block {carried}, and the client had {#serial.blocks} blocks`
	elseif failures(serial) ~= "" or failures(workers) ~= "" then
		return false, `The stages reported failures, "{failures(serial)}" in process and "{failures(workers)}"`
	end

	-- In process the order is each tick's alone, and on the workers each Heartbeat starts with the tick before's finish
	local serialOrder: { string } = {}
	local workersOrder: { string } = {}
	for beat: number = 1, TICKS do
		table.insert(serialOrder, `beat, decode {beat}, frame {beat}, late {beat}`)

		if beat == 1 then
			table.insert(workersOrder, "beat, decode 1")
		else
			table.insert(workersOrder, `beat, frame {beat - 1}, late {beat - 1}, decode {beat}`)
		end

		if beat == HELD_AT then
			table.insert(serialOrder, "beat")
			table.insert(workersOrder, "beat")
		end
	end

	table.insert(workersOrder, `beat, frame {TICKS}, late {TICKS}, decode {TICKS + 1}`)

	if table.concat(serial.order, ", ") ~= table.concat(serialOrder, ", ") then
		return false, `In process the stages and frames came as {table.concat(serial.order, ", ")}`
	elseif table.concat(workers.order, ", ") ~= table.concat(workersOrder, ", ") then
		return false, `On the workers the stages and frames came as {table.concat(workers.order, ", ")}`
	end

	-- Each finish in its own ring with the tick it held, which stats gives beside the stages
	local finishes: any = workers.Tick.finishes()
	for index: number = 1, finishes.held do
		if finishes.ticks[index] ~= index or not (finishes.times[index] >= 0) then
			return false, `The finish {index} held tick {finishes.ticks[index]} and took {finishes.times[index]} s`
		end
	end

	local read: any = workers.server:stats()
	if finishes.held ~= TICKS or read.relayFinish.last ~= finishes.last or read.relayDropped ~= 0 then
		return false, `The workers' server kept {finishes.held} finishes, and stats gave {read.relayDropped} dropped`
	elseif read.relayFinish.p95 < read.relayFinish.last then
		-- Of the ten finishes the p95 by nearest rank is the slowest
		return false,
			`Stats gave the finishes a p95 of {read.relayFinish.p95}, below the last's {read.relayFinish.last}`
	elseif serial.Tick.finishes().held ~= 0 then
		return false, "The in-process server kept a finish"
	end

	return true, nil
end
