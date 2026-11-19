--[[
    The versus run's receive line reads every StatsItem named for receiving
    beside the two rates, prints one that errors, has gone or gives no
    number as unreadable, says when none were found, and keeps to 2,048 B
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local RECEIVE: string = "dev/Client/Receive.luau"
local CONFIG: string = "dev/Client/Config.luau"
local PLAYER: string = "Mike"
local FAILURE: string = "it passed its 90 s deadline with ClientReceive still set"
local LOCKED: string = "the case's locked tree"
local LINE_BYTES: number = 2048 -- clientCost's line, string(1..2048) in dev/Schemas/Dev.volt
local COUNTERS: number = 40 -- Readable candidates with long names, more than the line holds

-- The case's own receive values, so its answers stand whatever the dev client tunes
local RECEIVE_VALUES: { [string]: any } = {
	attribute = "ClientReceive",
	interval = 1,
	longest = 90,
	percentiles = { 0.5, 0.95, 0.99 },
}

local FOUND: string =
	"Stats.Network.IncomingText | Stats.Network.Packets Received | Stats.Network.Received kBps | Stats.Network.Recv Gone"

-- The rates first as they print without candidates, then the readable candidate, then the unreadable ones by name
local NO_FRAMES: string = "no frame was sampled" -- The frame figures of a window whose render step never ran
local RATES: string = "Mike: Stats.DataReceiveKbps p50 2 p95 3 p99 3 n 3; Stats.PhysicsReceiveKbps p50 20 p95 30 p99 30 n 3; "
	.. "Stats.DataReceiveKbps + Stats.PhysicsReceiveKbps p50 22 p95 33 p99 33 n 3"
local LINE: string = `{RATES}; {NO_FRAMES}; Stats.Network.Received kBps p50 4 p95 6 p99 6 n 3; `
	.. "Stats.Network.IncomingText unreadable in 3 of 3 reads: GetValue gave a string; "
	.. "Stats.Network.Packets Received unreadable in 3 of 3 reads: lacking capability Plugin; "
	.. "Stats.Network.Recv Gone unreadable in 3 of 3 reads: it has left the Stats tree"

local ONE_SAMPLE: string = "Mike: Stats.DataReceiveKbps p50 1 p95 1 p99 1 n 1; Stats.PhysicsReceiveKbps p50 2 p95 2 p99 2 n 1; "
	.. "Stats.DataReceiveKbps + Stats.PhysicsReceiveKbps p50 3 p95 3 p99 3 n 1"
local UNSEARCHABLE: string = `{ONE_SAMPLE}; {NO_FRAMES}; Stats unsearchable for StatsItems: {LOCKED}`
local NONE: string = `{ONE_SAMPLE}; {NO_FRAMES}; no StatsItem in Stats is named for receiving`
local CUT: string = "15 more left out at the line's 2048 B"
local CUT_FAILED: string = `16 more left out at the line's 2048 B, then {FAILURE}`

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

-- A StatsItem standing in, under the tree when a parent is given, or anything else named so when it is no StatsItem
local function item(name: string, parent: any, isItem: boolean, getValue: (() -> any)?): { [string]: any }
	return {
		Name = name,
		Parent = parent,

		IsA = function (_: any, className: string): boolean
			return isItem and className == "StatsItem"
		end,

		GetFullName = function (_: any): string
			return `Stats.Network.{name}`
		end,

		GetValue = function (_: any): any
			if not getValue then
				error(`{name} has no value`)
			end

			return getValue()
		end,
	}
end

-- Stats standing in, its rates set by the case and its tree the items given
local function statsOf(items: { any }): { [string]: any }
	return {
		DataReceiveKbps = 0,
		PhysicsReceiveKbps = 0,

		GetDescendants = function (_: any): { any }
			return items
		end,
	}
end

-- A window as the receive keeps one, with no frame sampled
local function windowOf(candidates: { any }, search: string?): { [string]: any }
	return {
		label = "case",
		data = {},
		physics = {},
		frames = {},
		heap = {},
		cpu = {},
		gpu = {},
		candidates = candidates,
		search = search,
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local replicated: any = dataModel:GetService("ReplicatedStorage")

	-- The dev client's folder, with its Config and the receive, and the dev scope's client module standing in
	local folder: any = create("Folder", "Client", replicated)
	local files: { [any]: string } = {
		[create("ModuleScript", "Config", folder)] = CONFIG,
		[create("ModuleScript", "Receive", folder)] = RECEIVE,
	}

	local results: { [any]: any } = { [replicated.Shared.Network.Client] = { clientCost = { fire = function () end } } }
	local load: (target: any) -> any = Kit.loader(dataModel, files, results, loaded.require)
	load(folder.Config).receive = RECEIVE_VALUES
	local Receive: any = load(folder.Receive)

	-- 1) Only StatsItems named for receiving are found, by full name, whichever way the name puts it
	local tree: { [string]: any } = {}
	local reads: number = 0
	local readable: { number } = { 4, 2, 6 }
	local stats: { [string]: any } = statsOf({
		item("Packets Received", tree, true, function (): any
			error("lacking capability Plugin", 0)
		end),
		item("Data Ping", tree, true, function (): any
			return 50
		end),
		item("Received Folder", tree, false, nil),
		item("Recv Gone", nil, true, function (): any
			return 1
		end),
		item("Received kBps", tree, true, function (): any
			reads += 1
			return readable[reads]
		end),
		item("IncomingText", tree, true, function (): any
			return "text"
		end),
	})

	local found: { any }, search: string? = Receive.find(stats)
	local names: { string } = {}
	for _, candidate: any in found do
		table.insert(names, candidate.name)
	end

	if table.concat(names, " | ") ~= FOUND or search ~= nil then
		return false, `The search found "{table.concat(names, " | ")}" with {search}, not "{FOUND}"`
	end

	-- 2) Three samples: the rates as before, the readable candidate's figures, and each unreadable one with its failure
	local window: { [string]: any } = windowOf(found, nil)
	for sample: number = 1, 3 do
		stats.DataReceiveKbps = sample
		stats.PhysicsReceiveKbps = 10 * sample
		Receive.read(window, stats)
	end

	local measured: boolean, line: string = Receive.summary(window, PLAYER, nil)
	if not measured or line ~= LINE then
		return false, `Three samples gave {measured} with "{line}", not true with "{LINE}"`
	end

	-- 3) A tree that can't be searched says so, and so does one with no candidate
	local locked: { [string]: any } = statsOf({})
	locked.GetDescendants = function (_: any): { any }
		error(LOCKED, 0)
	end

	local none: { any }, why: string? = Receive.find(locked)
	local blocked: { [string]: any } = windowOf(none, why)
	local empty: { [string]: any } = windowOf({}, nil)
	for _, each: { [string]: any } in { blocked, empty } do
		each.data = { 1 }
		each.physics = { 2 }
	end

	local searched: boolean, unsearchable: string = Receive.summary(blocked, PLAYER, nil)
	local named: boolean, unnamed: string = Receive.summary(empty, PLAYER, nil)
	if not searched or not named or unsearchable ~= UNSEARCHABLE or unnamed ~= NONE then
		return false, `An unsearchable tree gave "{unsearchable}" and an empty one "{unnamed}"`
	end

	-- 4) More candidates than the line holds: those that fit, then how many were left out, within 2,048 B
	-- with a failure too. The names are long enough that the failure's ending leaves one more out
	local many: { any } = {}
	for index: number = 1, COUNTERS do
		table.insert(
			many,
			item(`Received Long Counter Number {string.format("%03d", index)}`, tree, true, function (): any
				return index
			end)
		)
	end

	local crowded: { [string]: any } = statsOf(many)
	crowded.DataReceiveKbps = 1
	crowded.PhysicsReceiveKbps = 2

	-- One sample of every crowded candidate, its line's problem given, nil when it fits and ends as it should
	local function crowd(failure: string?, ending: string): string?
		local full: { [string]: any } = windowOf((Receive.find(crowded)), nil)
		Receive.read(full, crowded)

		local _, cut: string = Receive.summary(full, PLAYER, failure)
		local tail: string = string.sub(cut, -#ending)
		if #cut > LINE_BYTES or tail ~= ending then
			return `A crowded line gave {#cut} B ending "{tail}", not at most {LINE_BYTES} ending "{ending}"`
		end

		return nil
	end

	local problem: string? = crowd(nil, CUT) or crowd(FAILURE, CUT_FAILED)
	if problem then
		return false, problem
	end

	return true, nil
end
