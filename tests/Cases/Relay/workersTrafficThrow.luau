--[[
    A traffic read that throws for a later worker's viewer at the dispatch
    raises with no round sent and the call queued before it kept, and a
    send that throws for the later worker gives the round up with a resend
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/Relay/StandIn")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local SLOTS: number = 4096 -- Constants.SLOTS
local ROW_BYTES: number = SLOTS // 8
local LYING: number = 2 -- Anti-ESP's kind for a sleeper or body, whose answer a worker reads from its bit alone
local ALL_SHOWN: number = 255
local CENTER: vector = vector.create(-2600, 0, -300)
local NEAR: number = 40
local RUNS: number = 7
local THROW_RUN: number = 3
local SEND_THROW_RUN: number = 5 -- The second worker's send throws, after the first worker's went

return function (): (boolean, string | nil)
	local run: number = 0
	local sends: { [number]: number } = {} -- The rounds sent in each run
	local calls: { [number]: { number } } = { {}, {} } -- The calls each worker's own hand-in carried, by run
	local resent: { [number]: { boolean } } = { {}, {} } -- Whether each worker's own hand-in asked it to resend

	local made: { [string]: any } = {}
	local Wire: any = Environment.load("src/Server/Relay/Wire.luau")
	function made.new(count: number, name: string, remote: any, settings: any): any
		local built: any = StandIn.new(count, name, remote, settings)
		local send: any = built.send

		built.send = function (self: any, worker: number, round: number, shared: buffer, own: buffer)
			if run == SEND_THROW_RUN and worker == WORKERS then
				error("A planted failure of the pool's send")
			end

			sends[run] = (sends[run] or 0) + 1
			calls[worker][run] = Wire.callCount(own)
			resent[worker][run] = Wire.resend(own)
			send(self, worker, round, shared, own)
		end

		made.made = built

		return built
	end

	local globals: any = Environment.load(GLOBALS, { [POOL] = made })
	local game: any = globals.game
	local tread: any = game:GetService("ReplicatedStorage").Packages.Tread
	local Example: any = globals.require(game:GetService("ServerScriptService").Fixtures.Config.Example)
	local Relay: any = globals.require(tread.Server.Relay)
	local Slots: any = globals.require(tread.Server.Slots)
	local Taps: any = globals.require(tread.Server.Taps)
	local State: any = globals.require(tread.Step.State)

	local shared: any = Example.shared()
	local server: any = Example.server()
	server.relay.workers = WORKERS
	local layout: any = globals.require(tread.Codec.Fields).compile(shared.fields)
	Slots.start(server.slots.reserve)

	local kinds: buffer = buffer.create(SLOTS)
	local teams: buffer = buffer.create(SLOTS * 8)
	buffer.fill(kinds, 0, LYING)
	for slot: number = 0, SLOTS - 1 do
		buffer.writef64(teams, slot * 8, 0 / 0)
	end

	local function answers(viewers: { any }): any
		local visible: buffer = buffer.create(#viewers * ROW_BYTES)
		buffer.fill(visible, 0, ALL_SHOWN)

		return { kinds = kinds, teams = teams, visible = visible, quiet = buffer.create(#viewers * ROW_BYTES) }
	end

	local function asked(_: any, _: { number }, _: number)
		error("The case's answers set no quiet bit, so the relay hands it no mark")
	end

	local viewers: { any } = {}
	local states: { [number]: any } = {}
	local throwing: boolean = false
	local blocks: number = 0

	local function traffic(key: any): number
		if throwing and key == viewers[2].key then
			error("A planted failure of the traffic port")
		end

		return 0
	end

	local function isHidden(_: any, _: number): boolean
		return false
	end

	local function send(_: { any }, _: buffer)
		blocks += 1
	end

	Relay.start({ shared = shared, server = server, layout = layout }, send, send, traffic, isHidden, answers, asked)
	Taps.start({
		layout = layout,
		wearing = Relay.wearing,
		reason = function (): string
			return "Clear"
		end,
	})
	local pool: any = made.made

	-- The first viewer homed on the first worker and the second on the second
	for index: number, name: string in { "First", "Second" } do
		local slot: number = Slots.take("Player")
		Slots.setEntry(slot, { kind = "Player", rig = "A" })

		local at: vector = CENTER + vector.create(index * 5, 0, 0)
		local state: any = State.new()
		state.position = at
		state.mode = "Ground"
		state.grounded = true
		state.groundMaterial = roblox.Enum.Material.Grass
		states[slot] = state

		table.insert(viewers, { key = { Name = name }, slot = slot, position = at, acknowledged = 0, received = 0 })
	end

	for current: number = 1, RUNS do
		run = current

		if run == THROW_RUN then
			Relay.setDistance(viewers[1].key, NEAR)
		end

		throwing = run == THROW_RUN
		local ran: boolean, failure: any = pcall(Relay.run, run, viewers, states, {})
		throwing = false

		if run == THROW_RUN then
			local dropped: boolean, refusal: any = pcall(Relay.drop)
			if ran or not string.find(`{failure}`, "planted failure", 1, true) then
				return false, `The throwing run gave {ran} "{failure}", not the traffic port's failure`
			elseif sends[run] ~= nil then
				return false, `The throwing run sent {sends[run]} rounds before its traffic read threw`
			elseif not Relay.finish() then
				return false, "The throwing run left a round out"
			elseif dropped or not string.find(`{refusal}`, "no round out", 1, true) then
				return false, `Relay.drop after the throwing run gave {dropped} {refusal}`
			end
		elseif run == SEND_THROW_RUN then
			pool:deliver()
			if ran or not string.find(`{failure}`, "pool's send", 1, true) then
				return false, `The run whose send threw gave {ran} "{failure}", not the pool's failure`
			elseif sends[run] ~= 1 or not Relay.finish() then
				return false, `The run whose send threw sent {sends[run]} rounds or left one out`
			end
		else
			if not ran then
				return false, `Run {run} threw: {failure}`
			end

			pool:deliver()
			if not Relay.finish() then
				return false, `Run {run}'s round was still out after its delivery`
			end
		end
	end

	-- The call queued before the throwing run reached its worker with the run after
	if (calls[1][THROW_RUN + 1] or 0) == 0 then
		return false, "The call queued before the throwing run never reached its worker"
	elseif sends[THROW_RUN + 1] ~= WORKERS or blocks == 0 then
		return false, `The run after the throw sent {sends[THROW_RUN + 1]} rounds and {blocks} blocks in all`
	end

	-- The worker sent the given-up round sends its views whole next, and the one never sent it doesn't need to
	if not resent[1][SEND_THROW_RUN + 1] or resent[2][SEND_THROW_RUN + 1] then
		return false, "The run after the send threw didn't ask just the worker sent the lost round to resend"
	end

	return true, nil
end
