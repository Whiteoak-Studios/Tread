--[[
    A landing runs the exact depenetration: a body set down sunk into the
    floor is moved clear with no report, and one set down inside the vault
    stays there and is reported stuck once, before its callbacks hear of it
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Intake = require("../../Fixtures/Commands/Intake")

local CLEARED_SLOT: number = 60
local STUCK_SLOT: number = 61
local SUNK: number = 0.3 -- Studs under the floor's top the first destination's feet are
local BURY: number = 1 -- Studs above the floor inside the vault the second destination's feet are

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

	-- Each callback notes how many stuck reports had been raised when it heard of the landing
	local heardAfter: { number } = {}
	Teleport.onTeleported(function (_: any)
		table.insert(heardAfter, #rig:reported("stuck"))
	end)

	local from: vector = vector.create(0, Geometry.floor, 0)

	-- 1) Sunk into the floor, freed by the rest height alone
	local cleared: any = Scene.state(from, true)
	local clearedCharacter: any = { player = rig.bot, _slot = CLEARED_SLOT, _generation = 1, _live = true }
	local sunk: any = roblox.CFrame.new(-15, Geometry.floor - SUNK, 15)
	Teleport.run(1)
	Teleport.schedule(clearedCharacter, sunk, cleared, rig.connection)
	Teleport.run(2)

	if cleared.position.y < Geometry.floor then
		return false, `A body set down sunk into the floor was left at {cleared.position.y}, under its top`
	elseif cleared.position.x ~= -15 or cleared.position.z ~= 15 then
		return false, `Freeing the body moved it sideways, to {cleared.position}`
	elseif #rig:reported("stuck") ~= 0 then
		return false, "A body freed by depenetration was reported stuck"
	elseif cleared.apex ~= sunk.Position.Y then
		return false, `The apex was {cleared.apex}, not the destination's height before depenetration`
	end

	-- 2) Inside the vault, deeper than every reach, where no spot frees it
	local vault: vector = vector.create(Geometry.vault.center.x, Geometry.floor + BURY, Geometry.vault.center.z)
	local stuck: any = Scene.state(from, true)
	local stuckCharacter: any = { player = rig.bot, _slot = STUCK_SLOT, _generation = 1, _live = true }
	Teleport.schedule(stuckCharacter, roblox.CFrame.new(vault.x, vault.y, vault.z), stuck, rig.connection)
	Teleport.run(3)

	local reports: { Intake.Heard } = {}
	for _, heard: Intake.Heard in rig.heard do
		if heard.kind == "stuck" then
			table.insert(reports, heard)
		end
	end

	if #reports ~= 1 then
		return false, `A body no spot frees was reported stuck {#reports} times, not once`
	elseif reports[1].player ~= rig.bot then
		return false, "The stuck report was not about the character's bot"
	elseif type(reports[1].measurement) ~= "number" or (reports[1].measurement :: number) < 0 then
		return false, `The stuck report measured {reports[1].measurement}, not how far the body sank`
	elseif stuck.position ~= vault then
		return false, `A body no spot frees was moved to {stuck.position}, not left at the destination`
	elseif #heardAfter ~= 2 or heardAfter[2] ~= 1 then
		return false, "The stuck body's callbacks heard of its landing before its stuck report"
	end

	return true, nil
end
