--[[
    A teleport whose prestream never settles waits the timeout's ticks,
    rounded up, with the body where it stands, then lands on the run that
    reaches them, and the Promise's late finish lands nothing more
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Intake = require("../../Fixtures/Commands/Intake")

local SLOT: number = 12 -- The character's slot
local TIMEOUT: number = 0.12 -- Seconds, 2.4 ticks at 20 Hz, so rounding up waits 3 where rounding would wait 2
local WAIT: number = 3
local CALLED: number = 10 -- The tick the last run had when the teleport was scheduled
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

	local ticks: number = rig.shared.rates.simulation * TIMEOUT
	if math.ceil(ticks) ~= WAIT or math.round(ticks) == WAIT then
		return false, `The case's timeout is {ticks} ticks, which no longer tells rounding up from rounding`
	end

	-- The game's hook hands back a Promise only the case settles
	local finish: (() -> ())? = nil
	server.teleport.timeout = TIMEOUT
	server.prestream = function (_: any, _: any): any
		return Promise.new(function (resolve: () -> ())
			finish = resolve
		end)
	end

	Teleport.start({ shared = rig.shared, server = server }, Scene.world(casts(Geometry.parts)))

	local player: any = roblox.Instance.new("Player")
	player.Name = "Waiting"

	local from: vector = vector.create(0, Geometry.floor, 0)
	local state: any = Scene.state(from, true)
	local character: any = { player = player, _slot = SLOT, _generation = 1, _live = true }
	local connection: any = rig.Connections.add(player)

	local landed: number = 0
	Teleport.onTeleported(function (_: any)
		landed += 1
	end)

	Teleport.run(CALLED)
	Teleport.schedule(character, roblox.CFrame.new(20, Geometry.floor + LIFT, -30), state, connection)

	for tick: number = CALLED + 1, CALLED + WAIT - 1 do
		Teleport.run(tick)
		if landed ~= 0 or state.position ~= from then
			return false, `The teleport landed on tick {tick}, before its {WAIT}-tick deadline`
		end
	end

	Teleport.run(CALLED + WAIT)
	if landed ~= 1 then
		return false, `The teleport had not landed by its deadline, tick {CALLED + WAIT}`
	elseif state.position ~= vector.create(20, Geometry.floor + LIFT, -30) then
		return false, `The timed-out teleport set the body down at {state.position}, not its destination`
	end

	if not finish then
		return false, "The prestream hook never ran for the player's teleport"
	end

	finish()
	Teleport.run(CALLED + WAIT + 1)
	if landed ~= 1 then
		return false, "The prestream's finish after the deadline landed the teleport again"
	end

	return true, nil
end
