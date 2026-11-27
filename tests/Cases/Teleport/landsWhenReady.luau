--[[
    A player's teleport hands the game's prestream hook the player and the
    destination once, leaves the body where it stands while the hook's
    Promise is pending, and lands on the first run after it resolves
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Intake = require("../../Fixtures/Commands/Intake")

local SLOT: number = 30 -- The character's slot
local PENDING_RUNS: number = 4 -- Runs the hook's Promise stays pending through
local LIFT: number = 0.5 -- Studs over the fixture floor the destination is, clear of it

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

	-- The game's hook keeps what it was handed and a Promise only the case resolves
	local asked: { { player: any, at: any } } = {}
	local finish: (() -> ())? = nil
	server.prestream = function (player: any, at: any): any
		table.insert(asked, { player = player, at = at })

		return Promise.new(function (resolve: () -> ())
			finish = resolve
		end)
	end

	Teleport.start({ shared = rig.shared, server = server }, Scene.world(casts(Geometry.parts)))

	local player: any = roblox.Instance.new("Player")
	player.Name = "Streaming"

	local from: vector = vector.create(0, Geometry.floor, 0)
	local state: any = Scene.state(from, true)
	local character: any = { player = player, _slot = SLOT, _generation = 1, _live = true }
	local at: any = roblox.CFrame.new(-20, Geometry.floor + LIFT, 15)

	local landed: number = 0
	Teleport.onTeleported(function (_: any)
		landed += 1
	end)

	Teleport.run(1)
	Teleport.schedule(character, at, state, rig.Connections.add(player))

	if #asked ~= 1 then
		return false, `The prestream hook ran {#asked} times for one teleport`
	elseif asked[1].player ~= player or asked[1].at ~= at then
		return false, "The prestream hook was not handed the player and the destination"
	end

	for tick: number = 2, 1 + PENDING_RUNS do
		Teleport.run(tick)
		if landed ~= 0 or state.position ~= from then
			return false, `The teleport landed on tick {tick}, while the hook's Promise was still pending`
		end
	end

	if not finish then
		return false, "The prestream hook's Promise never started"
	end

	finish()
	Teleport.run(2 + PENDING_RUNS)

	if landed ~= 1 then
		return false, "The teleport did not land on the run after its destination was ready"
	elseif state.position ~= vector.create(-20, Geometry.floor + LIFT, 15) then
		return false, `The body stood at {state.position}, not the destination`
	end

	return true, nil
end
