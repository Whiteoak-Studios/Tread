--[[
    When the sampler records a box: a first read seeds, a walker that moved
    records one, and one that kept its place, a body in another move mode
    and a read of the same tick record none, while ticks lost are counted
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local SETTLES: string = "dev/Server/Parallel/Settles.luau"
local CAP: number = 8
local LAST_TICK: number = 65535 -- The top of the u16 a state's tick wraps in

-- The step block's keys the box reads
local SETTINGS: { [string]: number } = { radius = 1.25, standing = 5, crouched = 3 }

-- One read: what the case sets on a bot's state first, and the counts after it
type Step = {
	label: string,
	key: string,
	tick: number,
	position: vector,
	moveMode: string,
	counts: string,
}

local STEPS: { Step } = {
	{
		label = "a first read",
		key = "first",
		tick = 100,
		position = vector.create(0, 3, 0),
		moveMode = "Walk",
		counts = "0 reads, 0 walkers, 0 recorded, 0 skipped",
	},
	{
		label = "a walker that moved",
		key = "first",
		tick = 101,
		position = vector.create(1, 3, 0),
		moveMode = "Walk",
		counts = "1 reads, 1 walkers, 1 recorded, 0 skipped",
	},
	{
		label = "a walker that kept its place",
		key = "first",
		tick = 102,
		position = vector.create(1, 3, 0),
		moveMode = "Walk",
		counts = "2 reads, 1 walkers, 1 recorded, 0 skipped",
	},
	{
		label = "a noclip body that moved",
		key = "first",
		tick = 103,
		position = vector.create(2, 3, 0),
		moveMode = "Noclip",
		counts = "3 reads, 1 walkers, 1 recorded, 0 skipped",
	},
	{
		label = "a walker read again on the same tick, moved",
		key = "first",
		tick = 103,
		position = vector.create(3, 3, 0),
		moveMode = "Walk",
		counts = "3 reads, 1 walkers, 1 recorded, 0 skipped",
	},
	{
		label = "a walker whose tick jumped by 3",
		key = "first",
		tick = 106,
		position = vector.create(4, 3, 0),
		moveMode = "Walk",
		counts = "4 reads, 2 walkers, 2 recorded, 2 skipped",
	},
	{
		label = "a second bot's first read",
		key = "second",
		tick = LAST_TICK,
		position = vector.create(10, 3, 10),
		moveMode = "Walk",
		counts = "4 reads, 2 walkers, 2 recorded, 2 skipped",
	},
	{
		label = "the second bot moved across the tick's wrap",
		key = "second",
		tick = 0,
		position = vector.create(11, 3, 10),
		moveMode = "Walk",
		counts = "5 reads, 3 walkers, 3 recorded, 2 skipped",
	},
}

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local packages: any = dataModel:GetService("ReplicatedStorage").Packages
	local State: any = loaded.require(packages.Tread.Step.State)

	-- Characters and the bot harness's runs stand in empty, since the case hands each read its state
	local results: { [any]: any } = { [packages.Tread.Server.Characters] = {}, [server.Bots.Run] = {} }
	local Settles: any =
		Kit.loader(dataModel, { [server.Parallel.Settles] = SETTLES }, results, loaded.require)(server.Parallel.Settles)

	local sampler: any = Settles.new("Case", CAP, SETTINGS)
	local states: { [string]: any } = {}

	for _, step: Step in STEPS do
		local state: any = states[step.key] or State.new()
		states[step.key] = state
		state.tick = step.tick
		state.position = step.position
		state.moveMode = step.moveMode

		Settles.read(sampler, step.key, state)

		local recording: any = Settles.recording(sampler)
		local counts: string = `{recording.reads} reads, {recording.walkers} walkers, `
			.. `{recording.recorded} recorded, {recording.skipped} skipped`
		if counts ~= step.counts then
			return false, `After {step.label} the sampler counted {counts}, not {step.counts}`
		elseif recording.dropped ~= 0 or recording.failed ~= 0 then
			return false, `After {step.label} it dropped {recording.dropped} and counted {recording.failed} failed`
		end
	end

	return true, nil
end
