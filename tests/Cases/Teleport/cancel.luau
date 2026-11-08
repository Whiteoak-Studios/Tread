--[[
    A cancelled teleport never lands and leaves the queue and range query
    alone, a cancel with nothing pending does nothing, a destroyed
    character's teleport is dropped, and the slot can teleport again
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Intake = require("../../Fixtures/Commands/Intake")

local PLAYER_SLOT: number = 3
local BOT_SLOT: number = 4
local FREE_SLOT: number = 5 -- A slot with no teleport, which a cancel leaves alone
local TIMEOUT: number = 0.12 -- Seconds, rounded up to 3 ticks at 20 Hz
local WAIT: number = 3
local LIFT: number = 0.5 -- Studs over the fixture floor each destination is, clear of it
local NEAR: number = 0.01 -- Studs the range query is asked within

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	local dataModel: any = rig.globals.game
	local tread: any = dataModel:GetService("ReplicatedStorage").Packages.Tread
	local fixtures: any = dataModel:GetService("ServerScriptService").Fixtures
	local Scene: any = rig.globals.require(fixtures.Step.Scene)
	local Geometry: any = rig.globals.require(fixtures.Step.Geometry)
	local casts: any = rig.globals.require(fixtures.Step.Collision)
	local Teleport: any = rig.globals.require(tread.Server.Teleport)
	local Range: any = rig.globals.require(tread.Server.Range)
	local Promise: any = rig.globals.require(dataModel:GetService("ReplicatedStorage").Packages.Promise)
	local server: any = rig.globals.require(fixtures.Config.Example).server()

	local finish: (() -> ())? = nil
	server.teleport.timeout = TIMEOUT
	server.prestream = function (_: any, _: any): any
		return Promise.new(function (resolve: () -> ())
			finish = resolve
		end)
	end

	Teleport.start({ shared = rig.shared, server = server }, Scene.world(casts(Geometry.parts)))

	local landed: { any } = {}
	Teleport.onTeleported(function (character: any)
		table.insert(landed, character)
	end)

	-- A player whose teleport waits on its prestream, with a queue and a place in the range query
	local player: any = roblox.Instance.new("Player")
	player.Name = "Cancelled"

	local from: vector = vector.create(0, Geometry.floor, 0)
	local destination: any = roblox.CFrame.new(-15, Geometry.floor + LIFT, 15)
	local state: any = Scene.state(from, true)
	local character: any = { player = player, _slot = PLAYER_SLOT, _generation = 1, _live = true }
	Range.set(PLAYER_SLOT, from, player.Name)

	rig:take(1)
	rig:send(rig:commands(3, 2))

	Teleport.run(1)
	Teleport.schedule(character, destination, state, rig.connection)
	Teleport.cancel(PLAYER_SLOT)
	Teleport.cancel(FREE_SLOT)

	if not finish then
		return false, "The prestream hook never ran for the player's teleport"
	end

	finish()
	for tick: number = 2, 2 + WAIT do
		Teleport.run(tick)
	end

	if #landed ~= 0 or state.position ~= from then
		return false, `A cancelled teleport landed the body at {state.position}`
	elseif rig.Commands.depth(rig.connection) ~= 2 then
		return false, `A cancelled teleport left {rig.Commands.depth(rig.connection)} commands queued, not 2`
	elseif #Range.near(from, NEAR) ~= 1 then
		return false, "A cancelled teleport moved the character in the range query"
	end

	-- A bot's teleport is ready at once, and its character is destroyed before the run that would land it
	local botState: any = Scene.state(from, true)
	local bot: any = { player = rig.bot, _slot = BOT_SLOT, _generation = 1, _live = true }
	Teleport.schedule(bot, destination, botState, rig.connection)
	bot._live = false

	Teleport.run(3 + WAIT)
	if #landed ~= 0 or botState.position ~= from then
		return false, "A teleport landed a character destroyed while it waited"
	end

	-- The slot cancelled before teleports again, and that one lands
	Teleport.schedule(character, destination, state, rig.connection)
	if not finish then
		return false, "The prestream hook never ran for the second teleport"
	end

	finish()
	Teleport.run(4 + WAIT)

	if #landed ~= 1 or landed[1] ~= character then
		return false, "The teleport after a cancel did not land"
	elseif state.position ~= vector.create(-15, Geometry.floor + LIFT, 15) then
		return false, `The teleport after a cancel set the body down at {state.position}`
	end

	return true, nil
end
