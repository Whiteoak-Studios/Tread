--[[
    Teleport refuses calls before its start and a second start, a bad
    destination or a destroyed character, a bad or backward tick, a callback
    that is no function and a cancel of no slot, and lands nothing refused
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Intake = require("../../Fixtures/Commands/Intake")

local SLOT: number = 90
local LAST_TICK: number = 5 -- The tick the run is given before the refusals

type Refusal = { label: string, by: string, call: () -> () }

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	local dataModel: any = rig.globals.game
	local tread: any = dataModel:GetService("ReplicatedStorage").Packages.Tread
	local fixtures: any = dataModel:GetService("ServerScriptService").Fixtures
	local Scene: any = rig.globals.require(fixtures.Step.Scene)
	local Geometry: any = rig.globals.require(fixtures.Step.Geometry)
	local casts: any = rig.globals.require(fixtures.Step.Collision)
	local Teleport: any = rig.globals.require(tread.Server.Teleport)
	local bound: number = rig.globals.require(tread.Constants).PLAY_BOUND
	local slots: number = rig.globals.require(tread.Constants).SLOTS
	local server: any = rig.globals.require(fixtures.Config.Example).server()
	local settings: any = { shared = rig.shared, server = server }
	local world: any = Scene.world(casts(Geometry.parts))

	local from: vector = vector.create(0, Geometry.floor, 0)
	local state: any = Scene.state(from, true)
	local character: any = { player = rig.bot, _slot = SLOT, _generation = 1, _live = true }
	local floor: number = Geometry.floor

	local function schedule(at: any): () -> ()
		return function ()
			Teleport.schedule(character, at, state, rig.connection)
		end
	end

	-- Before the start, every member but cancel and onTeleported refuses
	local early: { Refusal } = {
		{ label = "a teleport before the start", by = "character:teleport", call = schedule(roblox.CFrame.new()) },
		{
			label = "a run before the start",
			by = "Teleport.run",
			call = function ()
				Teleport.run(1)
			end,
		},
	}

	local function refuse(list: { Refusal }): string?
		for _, refusal: Refusal in list do
			local ran: boolean, problem: any = pcall(refusal.call)
			if ran then
				return `{refusal.by} took {refusal.label}`
			elseif not tostring(problem):find(refusal.by, 1, true) then
				return `{refusal.label} failed with "{problem}", not {refusal.by}'s refusal`
			end
		end

		return nil
	end

	local before: string? = refuse(early)
	if before then
		return false, before
	end

	Teleport.start(settings, world)
	Teleport.run(LAST_TICK)

	local nowhere: any = roblox.CFrame.new(0, floor, 0, 0 / 0, 0, 0 / 0, 0, 1, 0, 0, 0, 0 / 0)
	if nowhere.LookVector.X == nowhere.LookVector.X then
		return false, "The case's CFrame that looks nowhere has a look Lune keeps finite"
	end

	local refusals: { Refusal } = {
		{
			label = "a second start",
			by = "Teleport.start",
			call = function ()
				Teleport.start(settings, world)
			end,
		},
		{ label = "no destination", by = "character:teleport", call = schedule(nil) },
		{ label = "a Vector3", by = "character:teleport", call = schedule(roblox.Vector3.new(0, floor, 0)) },
		{ label = "a string", by = "character:teleport", call = schedule("0, 1100, 0") },
		{
			label = "X past the play bound",
			by = "character:teleport",
			call = schedule(roblox.CFrame.new(bound + 1, floor, 0)),
		},
		{
			label = "Z past the play bound",
			by = "character:teleport",
			call = schedule(roblox.CFrame.new(0, floor, -bound - 1)),
		},
		{ label = "an endless height", by = "character:teleport", call = schedule(roblox.CFrame.new(0, math.huge, 0)) },
		{ label = "a height of NaN", by = "character:teleport", call = schedule(roblox.CFrame.new(0, 0 / 0, 0)) },
		{ label = "X of NaN", by = "character:teleport", call = schedule(roblox.CFrame.new(0 / 0, floor, 0)) },
		{ label = "a look that is NaN", by = "character:teleport", call = schedule(nowhere) },
	}

	for _, tick: any in { LAST_TICK - 1, LAST_TICK + 0.5, 0 / 0, math.huge, "6", false } do
		table.insert(refusals, {
			label = `the tick {tick}`,
			by = "Teleport.run",
			call = function ()
				Teleport.run(tick)
			end,
		})
	end

	-- A list holds no nil, so each nil is a refusal of its own
	table.insert(refusals, {
		label = "no callback",
		by = "server:onTeleported",
		call = function ()
			Teleport.onTeleported(nil)
		end,
	})

	table.insert(refusals, {
		label = "no slot to cancel",
		by = "Teleport.cancel",
		call = function ()
			Teleport.cancel(nil)
		end,
	})

	for _, callback: any in { false, 3, "callback", {} } do
		table.insert(refusals, {
			label = `a callback of {callback}`,
			by = "server:onTeleported",
			call = function ()
				Teleport.onTeleported(callback)
			end,
		})
	end

	for _, slot: any in { -1, slots, 1.5, 0 / 0, "3", false } do
		table.insert(refusals, {
			label = `the slot {slot} to cancel`,
			by = "Teleport.cancel",
			call = function ()
				Teleport.cancel(slot)
			end,
		})
	end

	local refused: string? = refuse(refusals)
	if refused then
		return false, refused
	end

	-- A destroyed character, refused last since the case's character stays destroyed after it
	character._live = false
	local destroyed: string? = refuse({
		{
			label = "a destroyed character",
			by = "character:teleport",
			call = schedule(roblox.CFrame.new(-15, floor, 15)),
		},
	})

	if destroyed then
		return false, destroyed
	end

	local landed: number = 0
	Teleport.onTeleported(function (_: any)
		landed += 1
	end)

	Teleport.run(LAST_TICK + 1)
	if landed ~= 0 or state.position ~= from then
		return false, "A refused teleport landed"
	end

	return true, nil
end
