--[[
    With no prestream hook, a player's teleport is ready at once with
    streaming off and waits for a stream around the destination with it on;
    a stream that throws counts as ready, and a bot streams nothing
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes and implementMethod
local task = require("@lune/task")

local Intake = require("../../Fixtures/Commands/Intake")

local OFF_SLOT: number = 50
local ON_SLOT: number = 51
local THROWS_SLOT: number = 52
local BOT_SLOT: number = 53
local LIFT: number = 0.5 -- Studs over the fixture floor the destination is, clear of it
local HOLD_RUNS: number = 3 -- Runs the stream stays held through
local HOLD_LIMIT: number = 5 -- Real seconds the stand-in holds a stream before it gives up by itself
local RETURN_LIMIT: number = 2 -- Real seconds the case waits for a released stream to return

type Asked = { player: any, position: any, timeout: number }

return function (): (boolean, string | nil)
	-- Lune's Player has no RequestStreamAroundAsync, so a stand-in keeps each request and holds it until released,
	-- and since Lune refuses a method registered twice, no other case registers it
	local asked: { Asked } = {}
	local holding: boolean = false
	local throwing: boolean = false
	local returned: number = 0

	roblox.implementMethod("Player", "RequestStreamAroundAsync", function (player: any, position: any, timeout: number)
		table.insert(asked, { player = player, position = position, timeout = timeout })
		if throwing then
			error("This stream fails on purpose, to show the teleport still lands")
		end

		local deadline: number = os.clock() + HOLD_LIMIT
		while holding and os.clock() < deadline do
			task.wait()
		end

		returned += 1
	end)

	local rig: Intake.Intake = Intake.new()
	local dataModel: any = rig.globals.game
	local tread: any = dataModel:GetService("ReplicatedStorage").Packages.Tread
	local fixtures: any = dataModel:GetService("ServerScriptService").Fixtures
	local Scene: any = rig.globals.require(fixtures.Step.Scene)
	local Geometry: any = rig.globals.require(fixtures.Step.Geometry)
	local casts: any = rig.globals.require(fixtures.Step.Collision)
	local Teleport: any = rig.globals.require(tread.Server.Teleport)
	local server: any = rig.globals.require(fixtures.Config.Example).server()
	server.prestream = nil

	Teleport.start({ shared = rig.shared, server = server }, Scene.world(casts(Geometry.parts)))

	local landed: { [any]: number } = {}
	Teleport.onTeleported(function (character: any)
		landed[character] = (landed[character] or 0) + 1
	end)

	local from: vector = vector.create(0, Geometry.floor, 0)
	local at: any = roblox.CFrame.new(-15, Geometry.floor + LIFT, 15)
	local tick: number = 1

	-- A player whose character teleports in slot
	local function teleport(slot: number, name: string): any
		local player: any = roblox.Instance.new("Player")
		player.Name = name

		local character: any = { player = player, _slot = slot, _generation = 1, _live = true }
		Teleport.schedule(character, at, Scene.state(from, true), rig.Connections.add(player))

		return character
	end

	-- 1) Streaming off: nothing to stream, so the next run lands it
	Teleport.run(tick)
	local off: any = teleport(OFF_SLOT, "Off")
	tick += 1
	Teleport.run(tick)

	if landed[off] ~= 1 then
		return false, "With streaming off, a player's teleport did not land on the next run"
	elseif #asked ~= 0 then
		return false, "With streaming off, a teleport asked the engine to stream"
	end

	-- 2) Streaming on: the stream holds the teleport until it returns
	dataModel:GetService("Workspace").StreamingEnabled = true
	holding = true

	local on: any = teleport(ON_SLOT, "On")
	if #asked ~= 1 then
		return false, `With streaming on, a teleport asked for {#asked} streams, not 1`
	elseif asked[1].player ~= on.player or asked[1].position ~= at.Position then
		return false, "The stream was not asked for around the destination, for the teleporting player"
	elseif asked[1].timeout ~= server.teleport.timeout then
		return false, `The stream gives up after {asked[1].timeout} s, not the teleport timeout`
	end

	for _ = 1, HOLD_RUNS do
		tick += 1
		Teleport.run(tick)
		if landed[on] ~= nil then
			return false, `The teleport landed on tick {tick}, while its stream was still held`
		end
	end

	holding = false
	local deadline: number = os.clock() + RETURN_LIMIT
	while returned == 0 and os.clock() < deadline do
		task.wait()
	end

	if returned == 0 then
		return false, `The released stream had not returned after {RETURN_LIMIT} s`
	end

	tick += 1
	Teleport.run(tick)
	if landed[on] ~= 1 then
		return false, "The teleport did not land on the run after its stream returned"
	end

	-- 3) A stream that throws is warned, and the destination counts as ready
	throwing = true
	local throws: any = teleport(THROWS_SLOT, "Throws")
	tick += 1
	Teleport.run(tick)
	throwing = false

	if landed[throws] ~= 1 then
		return false, "The teleport whose stream threw did not land on the next run"
	end

	-- 4) A bot streams nothing, even while streaming is on
	local before: number = #asked
	local bot: any = { player = rig.bot, _slot = BOT_SLOT, _generation = 1, _live = true }
	Teleport.schedule(bot, at, Scene.state(from, true), rig.connection)
	tick += 1
	Teleport.run(tick)

	if #asked ~= before then
		return false, "A bot's teleport asked the engine to stream"
	elseif landed[bot] ~= 1 then
		return false, "A bot's teleport did not land on the next run with streaming on"
	end

	return true, nil
end
