--[[
    A landing whose collision throws is warned, its body put back exactly as
    it stood with its queue kept, reported as stage under decode, and dropped,
    while the teleport in the slot after it still lands on the same run
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Intake = require("../../Fixtures/Commands/Intake")

local THROWS_SLOT: number = 80
local LANDS_SLOT: number = 81
local THROWS_PAST: number = 100 -- Studs along X past which the case's collision throws
local LIFT: number = 0.5 -- Studs over the fixture floor each destination is, clear of it
local EPOCH: number = 6

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	local dataModel: any = rig.globals.game
	local tread: any = dataModel:GetService("ReplicatedStorage").Packages.Tread
	local fixtures: any = dataModel:GetService("ServerScriptService").Fixtures
	local Scene: any = rig.globals.require(fixtures.Step.Scene)
	local Geometry: any = rig.globals.require(fixtures.Step.Geometry)
	local casts: any = rig.globals.require(fixtures.Step.Collision)
	local Teleport: any = rig.globals.require(tread.Server.Teleport)
	local server: any = rig.globals.require(fixtures.Config.Example).server()

	-- The fixture casts, but for a rest query past THROWS_PAST, which throws as a game's broken function would
	local fixture: any = casts(Geometry.parts)
	local collision: any = table.clone(fixture)
	collision.rest = function (center: vector, size: vector): number?
		if center.x > THROWS_PAST then
			error("This collision throws on purpose, to show the landing is put back")
		end

		return fixture.rest(center, size)
	end

	Teleport.start({ shared = rig.shared, server = server }, Scene.world(collision))

	local landed: { any } = {}
	Teleport.onTeleported(function (character: any)
		table.insert(landed, character)
	end)

	local from: vector = vector.create(0, Geometry.floor, 0)
	local throwsState: any = Scene.state(from, true)
	throwsState.velocity = vector.create(1, 0, 2)
	throwsState.epoch = EPOCH
	throwsState.ladder = 3

	local throws: any = { player = rig.bot, _slot = THROWS_SLOT, _generation = 1, _live = true }
	local other: { Name: string } = { Name = "Other" }
	local lands: any = { player = other, _slot = LANDS_SLOT, _generation = 1, _live = true }
	local landsState: any = Scene.state(from, true)

	rig:take(1)
	rig:send(rig:commands(3, 2))

	Teleport.run(1)
	Teleport.schedule(
		throws,
		roblox.CFrame.new(THROWS_PAST + 50, Geometry.floor + LIFT, 0),
		throwsState,
		rig.connection
	)
	Teleport.schedule(lands, roblox.CFrame.new(-15, Geometry.floor + LIFT, 15), landsState, rig.Connections.add(other))
	Teleport.run(2)

	if throwsState.position ~= from or throwsState.velocity ~= vector.create(1, 0, 2) then
		return false, `The failed landing left the body at {throwsState.position}, moving at {throwsState.velocity}`
	elseif throwsState.epoch ~= EPOCH or throwsState.ladder ~= 3 or throwsState.mode ~= "Ground" then
		return false, "The failed landing was not put back: its epoch, ladder or mode changed"
	elseif rig.Commands.depth(rig.connection) ~= 2 then
		return false, "The failed landing dropped its queue"
	end

	local stages: { number | string } = rig:reported("stage")
	if #stages ~= 1 or stages[1] ~= "decode" then
		return false, `The failed landing was reported as {#stages} stage reports, not one under decode`
	elseif #landed ~= 1 or landed[1] ~= lands then
		return false, "The teleport after the failed one did not land on the same run, alone"
	elseif landsState.position ~= vector.create(-15, Geometry.floor + LIFT, 15) then
		return false, `The teleport after the failed one set its body down at {landsState.position}`
	end

	Teleport.run(3)
	if #landed ~= 1 or throwsState.position ~= from then
		return false, "The failed teleport was tried again"
	end

	return true, nil
end
