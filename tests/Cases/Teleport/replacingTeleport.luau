--[[
    A second teleport replaces the first: the first's late finish lands
    nothing, the wait counts from the second call, and the body lands once,
    at the second destination
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Intake = require("../../Fixtures/Commands/Intake")

local SLOT: number = 40 -- The character's slot
local TIMEOUT: number = 0.12 -- Seconds, rounded up to 3 ticks at 20 Hz
local WAIT: number = 3
local LIFT: number = 0.5 -- Studs over the fixture floor each destination is, clear of it

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	local dataModel: any = rig.globals.game
	local tread: any = dataModel:GetService("ReplicatedStorage").Packages.Tread
	local fixtures: any = dataModel:GetService("ServerScriptService").Fixtures
	local Scene: any = rig.globals.require(fixtures.Step.Scene)
	local Geometry: any = rig.globals.require(fixtures.Step.Geometry)
	local casts: any = rig.globals.require(fixtures.Step.Collision)
	local Teleport: any = rig.globals.require(tread.Server.Teleport)
	local Promise: any = rig.globals.require(dataModel:GetService("ReplicatedStorage").Packages.Promise)
	local server: any = rig.globals.require(fixtures.Config.Example).server()

	-- Each call's Promise is resolved only by the case, in the order the calls came
	local finishes: { () -> () } = {}
	server.teleport.timeout = TIMEOUT
	server.prestream = function (_: any, _: any): any
		return Promise.new(function (resolve: () -> ())
			table.insert(finishes, resolve)
		end)
	end

	Teleport.start({ shared = rig.shared, server = server }, Scene.world(casts(Geometry.parts)))

	local player: any = roblox.Instance.new("Player")
	player.Name = "Twice"

	local from: vector = vector.create(0, Geometry.floor, 0)
	local first: vector = vector.create(-15, Geometry.floor + LIFT, -15)
	local second: vector = vector.create(15, Geometry.floor + LIFT, -15)
	local state: any = Scene.state(from, true)
	local character: any = { player = player, _slot = SLOT, _generation = 1, _live = true }
	local connection: any = rig.Connections.add(player)

	local landed: number = 0
	Teleport.onTeleported(function (_: any)
		landed += 1
	end)

	Teleport.run(1)
	Teleport.schedule(character, roblox.CFrame.new(first.x, first.y, first.z), state, connection)
	Teleport.run(2)
	Teleport.schedule(character, roblox.CFrame.new(second.x, second.y, second.z), state, connection)

	if #finishes ~= 2 then
		return false, `The prestream hook ran {#finishes} times for two teleports`
	end

	-- The first's destination is ready only after the second replaced it
	finishes[1]()

	-- The first's deadline would have been tick 1 + WAIT, and the second's is 2 + WAIT
	for tick: number = 3, 1 + WAIT do
		Teleport.run(tick)
		if landed ~= 0 or state.position ~= from then
			return false, `The replaced teleport landed the body at {state.position} on tick {tick}`
		end
	end

	Teleport.run(2 + WAIT)
	if landed ~= 1 then
		return false, `The second teleport had not landed by its own deadline, tick {2 + WAIT}`
	elseif state.position ~= second then
		return false, `The body landed at {state.position}, not the second destination {second}`
	end

	finishes[2]()
	Teleport.run(3 + WAIT)
	if landed ~= 1 then
		return false, "The second teleport's late finish landed it again"
	end

	return true, nil
end
