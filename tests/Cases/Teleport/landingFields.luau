--[[
    A bot's teleport lands on the run after the call, setting every field the
    landing lists and keeping the posture and move mode, with its queue
    dropped and the range query moved
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Intake = require("../../Fixtures/Commands/Intake")

local SLOT: number = 7 -- The character's slot
local LIFT: number = 0.5 -- Studs over the fixture floor the destination is, clear of it
local YAW: number = 1.25 -- Radians the destination turns its look by from -Z
local NEAR: number = 0.01 -- Studs the range query is asked within
local LAST_EPOCH: number = 255 -- The full epoch's top, a u8

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
	local server: any = rig.globals.require(fixtures.Config.Example).server()

	Teleport.start({ shared = rig.shared, server = server }, Scene.world(casts(Geometry.parts)))

	-- A body caught in every state a landing clears or keeps
	local from: vector = vector.create(0, Geometry.floor, 0)
	local state: any = Scene.state(from, true)
	state.velocity = vector.create(3, 0, 4)
	state.facing = 0.5
	state.mode = "Mantle"
	state.mantleTicks = 3
	state.mantleRise = 2.5
	state.ladder = 5
	state.platform = 9
	state.apex = Geometry.floor + 3
	state.groundHeight = Geometry.floor - 2
	state.epoch = LAST_EPOCH
	state.posture = "Crouch"
	state.moveMode = "Noclip"

	local character: any = { player = rig.bot, _slot = SLOT, _generation = 1, _live = true }
	Range.set(SLOT, from, rig.bot.Name)

	-- Three commands wait in the queue the landing drops
	rig:take(1)
	rig:send(rig:commands(4, 3))
	if rig.Commands.depth(rig.connection) ~= 3 then
		return false, `{rig.Commands.depth(rig.connection)} commands waited before the teleport, not 3`
	end

	local heard: { any } = {}
	Teleport.onTeleported(function (landed: any)
		table.insert(heard, landed)
	end)

	local at: any = roblox.CFrame.new(-10, Geometry.floor + LIFT, 10) * roblox.CFrame.Angles(0, YAW, 0)
	local destination: vector = vector.create(-10, Geometry.floor + LIFT, 10)
	local facing: number = math.atan2(-at.LookVector.X, -at.LookVector.Z)

	Teleport.run(1)
	Teleport.schedule(character, at, state, rig.connection)

	-- A bot's destination is ready at once, and still the move waits for the run after the call
	Teleport.run(1)
	if state.position ~= from or #heard ~= 0 then
		return false, "The teleport landed on the run it was scheduled in"
	end

	Teleport.run(2)

	if #heard ~= 1 or heard[1] ~= character then
		return false, `The landing told {#heard} callbacks, not one with the character`
	elseif state.position ~= destination then
		return false, `The body stood at {state.position}, not the destination {destination}`
	elseif state.facing ~= facing or math.abs(facing - YAW) > 1e-6 then
		return false, `The body faced {state.facing}, not along the destination's look at {facing}`
	elseif state.velocity ~= vector.zero then
		return false, `The body kept a velocity of {state.velocity}`
	elseif state.mode ~= "Air" or state.mantleTicks ~= 0 or state.mantleRise ~= 0 then
		return false, `The body was left in {state.mode}, {state.mantleTicks} ticks into a {state.mantleRise} mantle`
	elseif state.ladder ~= 0 or state.platform ~= 0 then
		return false, `The body kept ladder {state.ladder} and platform {state.platform}`
	elseif state.apex ~= destination.y or state.groundHeight ~= destination.y then
		return false, `The apex was {state.apex} and the last ground {state.groundHeight}, not the destination's height`
	elseif state.epoch ~= 0 then
		return false, `The epoch went from {LAST_EPOCH} to {state.epoch}, not past its wrap to 0`
	elseif state.posture ~= "Crouch" or state.moveMode ~= "Noclip" then
		return false, `The landing changed the posture to {state.posture} or the move mode to {state.moveMode}`
	elseif #rig:reported("stuck") ~= 0 then
		return false, "A body landing clear was reported stuck"
	end

	if rig.Commands.depth(rig.connection) ~= 0 then
		return false, `{rig.Commands.depth(rig.connection)} commands still waited after the landing`
	end

	local _: any, standIn: boolean = rig:take(2)
	if not standIn then
		return false, "The tick after the landing ran a command queued before it"
	end

	local there: { string } = Range.near(destination, NEAR)
	if #there ~= 1 or there[1] ~= rig.bot.Name then
		return false, "The range query did not find the character at its destination"
	elseif #Range.near(from, NEAR) ~= 0 then
		return false, "The range query still found the character where it stood before"
	end

	Teleport.run(3)
	if #heard ~= 1 then
		return false, "One teleport landed twice"
	end

	return true, nil
end
