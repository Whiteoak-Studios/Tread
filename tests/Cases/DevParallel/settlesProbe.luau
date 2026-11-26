--[[
    The sampler's probe: its start connects one Heartbeat that reads every
    entry the fleet's list holds, a read that throws counted and the window
    going on, and its stop disconnects it and gives the counts' line
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local SETTLES: string = "dev/Server/Parallel/Settles.luau"
local CAP: number = 8
local ENDED: string = "This character has ended" -- What the stand-in's state read throws for a character that ended

-- The step block's keys the box reads
local SETTINGS: { [string]: number } = { radius = 1.25, standing = 5, crouched = 3 }

local KEPT: string = `2 kept, 0 dropped past the cap of {CAP}`
local LINE: string = `Case: 2 reads of a new tick, 2 of them walkers that moved ({KEPT}), 0 ticks skipped, 4 reads threw, `
	.. `first failure {ENDED}`

-- A walking state on a tick, at a point
local function standing(State: any, tick: number, position: vector): any
	local state: any = State.new()
	state.tick = tick
	state.position = position

	return state
end

local function counts(Settles: any, sampler: any): string
	local recording: any = Settles.recording(sampler)

	return `{recording.reads} reads, {recording.recorded} recorded, {recording.failed} failed`
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local packages: any = dataModel:GetService("ReplicatedStorage").Packages
	local State: any = loaded.require(packages.Tread.Step.State)

	-- The harness's Heartbeat fires on Lune's clock, so the module's game answers RunService with one the case fires
	local callbacks: { [{ nil }]: () -> () } = {}
	local heartbeat: any = {
		Connect = function (_: any, callback: () -> ()): any
			local token: { nil } = {}
			callbacks[token] = callback

			return {
				Disconnect = function (_: any)
					callbacks[token] = nil
				end,
			}
		end,
	}

	local function beat()
		for _, callback: () -> () in table.clone(callbacks) do
			callback()
		end
	end

	local function connected(): number
		local count: number = 0
		for _ in callbacks do
			count += 1
		end

		return count
	end

	local place: any = {
		GetService = function (_: any, name: string): any
			if name == "RunService" then
				return { Heartbeat = heartbeat }
			end

			return dataModel:GetService(name)
		end,
	}

	-- A character's state as the case's entries hold it, a throw for one that ended, as the fleet's handle gives
	local characters: any = {
		stateOf = function (character: any): any
			if character.state == nil then
				error(ENDED, 0)
			end

			return character.state
		end,
	}

	local results: { [any]: any } = { [packages.Tread.Server.Characters] = characters, [server.Bots.Run] = {} }
	local Settles: any =
		Kit.loader(place, { [server.Parallel.Settles] = SETTLES }, results, loaded.require)(server.Parallel.Settles)

	local sampler: any = Settles.new("Case", CAP, SETTINGS)
	local probe: any = Settles.probe(sampler)
	local walker: any = { character = { state = standing(State, 20, vector.create(0, 3, 0)) } }
	local ended: any = { character = {} }
	local entries: { any } = { walker, ended }

	-- 1) The start connects one Heartbeat; its first beat seeds the walker and counts the ended one's read
	probe.start(entries)
	if connected() ~= 1 then
		return false, `The start left {connected()} Heartbeat connections, not 1`
	end

	beat()
	if counts(Settles, sampler) ~= "0 reads, 0 recorded, 1 failed" then
		return false, `The first beat counted {counts(Settles, sampler)}, not a seed and one failed read`
	end

	-- 2) The walker's step is recorded on the next beat, the ended read counted again and the window going on
	walker.character.state.tick = 21
	walker.character.state.position = vector.create(1, 3, 0)
	beat()
	if counts(Settles, sampler) ~= "1 reads, 1 recorded, 2 failed" then
		return false, `The walker's step counted {counts(Settles, sampler)}, not one box and two failed reads`
	end

	-- 3) A bot the fleet's list gains after the start is read from the next beat on
	local late: any = { character = { state = standing(State, 5, vector.create(50, 3, 50)) } }
	table.insert(entries, late)
	beat()

	late.character.state.tick = 6
	late.character.state.position = vector.create(51, 3, 50)
	beat()
	if counts(Settles, sampler) ~= "2 reads, 2 recorded, 4 failed" then
		return false,
			`A bot added after the start counted {counts(Settles, sampler)}, not its box and four failed reads`
	end

	-- 4) The stop disconnects the Heartbeat and gives the counts' line, and a beat after it reads nothing
	local line: string = probe.stop({})
	if connected() ~= 0 then
		return false, `The stop left {connected()} Heartbeat connections`
	elseif line ~= LINE then
		return false, `The stop gave "{line}", not "{LINE}"`
	end

	beat()
	if counts(Settles, sampler) ~= "2 reads, 2 recorded, 4 failed" then
		return false, `A beat after the stop counted {counts(Settles, sampler)}`
	end

	-- 5) A start again holds one connection however often it is called, and forgets each bot's last read
	probe.start(entries)
	probe.start(entries)
	if connected() ~= 1 then
		return false, `Two starts left {connected()} Heartbeat connections, not 1`
	end

	walker.character.state.tick = 22
	walker.character.state.position = vector.create(2, 3, 0)
	beat()
	probe.stop({})
	if counts(Settles, sampler) ~= "2 reads, 2 recorded, 5 failed" then
		return false, `The walker's first read of a new window counted {counts(Settles, sampler)}, not a seed`
	elseif connected() ~= 0 then
		return false, `The second stop left {connected()} Heartbeat connections`
	end

	return true, nil
end
