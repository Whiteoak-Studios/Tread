--[[
    Each teleport callback hears every landing once; one that throws stops
    neither the others nor the run, one disconnected hears no more, and a
    teleport a callback schedules lands on the next run
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Intake = require("../../Fixtures/Commands/Intake")

local FIRST_SLOT: number = 70
local SECOND_SLOT: number = 71
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
	local server: any = rig.globals.require(fixtures.Config.Example).server()

	Teleport.start({ shared = rig.shared, server = server }, Scene.world(casts(Geometry.parts)))

	local from: vector = vector.create(0, Geometry.floor, 0)
	local here: any = roblox.CFrame.new(-15, Geometry.floor + LIFT, 15)
	local there: any = roblox.CFrame.new(-15, Geometry.floor + LIFT, -15)

	local first: any = { player = rig.bot, _slot = FIRST_SLOT, _generation = 1, _live = true }
	local second: any = { player = rig.bot, _slot = SECOND_SLOT, _generation = 1, _live = true }
	local firstState: any = Scene.state(from, true)
	local secondState: any = Scene.state(from, true)

	local thrown: number = 0
	local heard: { any } = {}
	local follow: boolean = true

	Teleport.onTeleported(function (_: any)
		thrown += 1
		error("This teleport callback throws on purpose, to show the others still run")
	end)

	-- Hears every landing, and on the first one teleports the character in the slot after it
	local disconnect: () -> () = Teleport.onTeleported(function (character: any)
		table.insert(heard, character)

		if follow then
			follow = false
			Teleport.schedule(second, there, secondState, rig.connection)
		end
	end)

	Teleport.run(1)
	Teleport.schedule(first, here, firstState, rig.connection)

	local ran: boolean, problem: any = pcall(Teleport.run, 2)
	if not ran then
		return false, `A throwing teleport callback's error reached the run: {problem}`
	elseif thrown ~= 1 then
		return false, `The throwing callback ran {thrown} times for one landing`
	elseif #heard ~= 1 or heard[1] ~= first then
		return false, `The callback after the throwing one heard {#heard} landings, not the first character's`
	elseif secondState.position ~= from then
		return false, "A teleport scheduled from a callback landed on the run that called the callback"
	end

	Teleport.run(3)
	if #heard ~= 2 or heard[2] ~= second then
		return false, "The teleport scheduled from a callback did not land on the next run"
	elseif thrown ~= 2 then
		return false, `The throwing callback ran {thrown} times for two landings`
	end

	disconnect()
	disconnect()

	Teleport.schedule(first, there, firstState, rig.connection)
	Teleport.run(4)

	if #heard ~= 2 then
		return false, "A disconnected callback still heard a landing"
	elseif thrown ~= 3 then
		return false, "Disconnecting one callback stopped another"
	end

	return true, nil
end
