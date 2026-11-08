--[[
    A prestream hook that throws, rejects at once or later, or gives no
    Promise counts the destination ready, so the teleport lands on the next
    run, and a bot's teleport lands at once without calling the hook
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Intake = require("../../Fixtures/Commands/Intake")

local LIFT: number = 0.5 -- Studs over the fixture floor each destination is, clear of it

-- How the game's hook fails for each player, each in a slot of its own
local FAILURES: { { name: string, slot: number } } = {
	{ name = "Throws", slot = 20 },
	{ name = "Rejects", slot = 21 },
	{ name = "Nothing", slot = 22 },
	{ name = "RejectsLater", slot = 23 },
}

local BOT_SLOT: number = 24

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

	local asked: { string } = {}
	local rejectLater: ((reason: string) -> ())? = nil

	server.prestream = function (player: any, _: any): any
		table.insert(asked, player.Name)

		if player.Name == "Throws" then
			error("This prestream hook throws on purpose, to show the teleport still lands")
		elseif player.Name == "Rejects" then
			return Promise.reject("This prestream hook rejects on purpose")
		elseif player.Name == "RejectsLater" then
			return Promise.new(function (_: any, reject: (reason: string) -> ())
				rejectLater = reject
			end)
		end

		return nil
	end

	Teleport.start({ shared = rig.shared, server = server }, Scene.world(casts(Geometry.parts)))

	local landed: { [any]: number } = {}
	Teleport.onTeleported(function (character: any)
		landed[character] = (landed[character] or 0) + 1
	end)

	local from: vector = vector.create(0, Geometry.floor, 0)
	local destination: any = roblox.CFrame.new(-15, Geometry.floor + LIFT, 15)
	local characters: { [string]: any } = {}

	Teleport.run(1)

	for _, failure in FAILURES do
		local player: any = roblox.Instance.new("Player")
		player.Name = failure.name

		local character: any = { player = player, _slot = failure.slot, _generation = 1, _live = true }
		characters[failure.name] = character
		Teleport.schedule(character, destination, Scene.state(from, true), rig.Connections.add(player))
	end

	local bot: any = { player = rig.bot, _slot = BOT_SLOT, _generation = 1, _live = true }
	Teleport.schedule(bot, destination, Scene.state(from, true), rig.connection)

	if #asked ~= #FAILURES then
		return false, `The prestream hook ran {#asked} times, not once for each of the {#FAILURES} players`
	end

	Teleport.run(2)

	for _, name: string in { "Throws", "Rejects", "Nothing" } do
		if landed[characters[name]] ~= 1 then
			return false, `The teleport whose hook failed as {name} did not land on the next run`
		end
	end

	if landed[bot] ~= 1 then
		return false, "The bot's teleport did not land on the next run"
	elseif landed[characters.RejectsLater] ~= nil then
		return false, "The teleport whose Promise is still pending landed"
	end

	if not rejectLater then
		return false, "The pending prestream's Promise never started"
	end

	rejectLater("This prestream hook rejects on purpose, later")
	Teleport.run(3)

	if landed[characters.RejectsLater] ~= 1 then
		return false, "The teleport whose Promise rejected later did not land on the next run"
	end

	return true, nil
end
