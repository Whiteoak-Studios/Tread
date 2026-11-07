--[[
    A slot table entry round-trips a taken slot's generation, rig mode and
    player and a freed slot's generation, through Volt's Slots, and a death
    message round-trips both slots and the push at its edges
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")
local Same = require("../../Fixtures/Codec/Same")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local STEPS: number = 3
local PUSH_STEP: number = 1 / 127

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local replicatedStorage: any = globals.game:GetService("ReplicatedStorage")
	local tread: any = replicatedStorage.Packages.Tread

	local server: any = globals.require(tread.Network.Server)
	local client: any = globals.require(tread.Network.Client)
	local mock: any = globals.require(replicatedStorage.Packages.Volt).mock
	local Reliable: any = globals.require(tread.Codec.Reliable)

	-- A taken slot with a player, one without, and a freed one. An Instance stands in for the slot's Player, which
	-- Lune can't make, and the entries go to the mock's own player
	local viewer: any = mock.players[1]
	local player: any = require("@lune/roblox").Instance.new("Folder")
	local entries: { { [string]: any } } = { {}, {}, {} }
	Reliable.write(entries[1], 4095, 15, "B", player)
	Reliable.write(entries[2], 0, 1, "A", nil)
	Reliable.write(entries[3], 17, 3, nil, nil)

	local taken: any = entries[1].taken
	Reliable.write(entries[1], 4095, 15, "A", nil)
	if entries[1].taken ~= taken then
		return false, "Writing a taken entry again made a new table for it"
	end

	Reliable.write(entries[1], 4095, 15, "B", player)

	local heard: { any }? = nil
	client.Slots.on(function (received: { any })
		heard = received
	end)

	-- The client's handshake goes out on its first flush, before which the server sends it nothing
	client.flush()
	for _ = 1, STEPS do
		mock:step()
	end

	server.Slots.fire(viewer, entries)
	server.flush()
	for _ = 1, STEPS do
		mock:step()
	end

	if not heard or #heard ~= 3 then
		return false, "The slot table entries never reached the client whole"
	end

	local expected: { { any } } = { { 4095, 15, "B", player }, { 0, 1, "A", nil }, { 17, 3, nil, nil } }
	for index: number, row: { any } in expected do
		local slot: number, generation: number, rig: string?, owner: any = Reliable.read(heard[index])
		if slot ~= row[1] or generation ~= row[2] or rig ~= row[3] or owner ~= row[4] then
			return false, `Entry {index} read as {slot}, {generation}, {rig} and {owner}`
		end
	end

	-- A death with each push component at its edges and its step
	type Death = { push: vector }
	local deaths: { Death } = {
		{ push = vector.create(1, 0, 0) },
		{ push = vector.create(0, -1, 0) },
		{ push = vector.create(PUSH_STEP, -PUSH_STEP, 0) },
		{ push = vector.zero },
		{ push = vector.create(0, 0, 2) }, -- Clamped to a whole unit
	}

	for index: number, death: Death in deaths do
		local character: number, body: number, x: number, y: number, z: number =
			Reliable.writeDeath(100, 7, 4095, 0, death.push)
		local slot: number, generation: number, bodySlot: number, bodyGeneration: number, push: vector =
			Reliable.readDeath(character, body, x, y, z)

		if slot ~= 100 or generation ~= 7 or bodySlot ~= 4095 or bodyGeneration ~= 0 then
			return false, `Death {index} named slots {slot}, {generation}, {bodySlot} and {bodyGeneration}`
		end

		local back: vector = vector.create(
			math.clamp(death.push.x, -1, 1),
			math.clamp(death.push.y, -1, 1),
			math.clamp(death.push.z, -1, 1)
		)
		local differs: string? = Same(back, push, `death {index}'s push`, 1e-9)
		if differs then
			return false, differs
		end
	end

	-- The five values go out through Volt's own writer
	server.Death.fire(viewer, Reliable.writeDeath(100, 7, 4095, 0, vector.create(-1, 0, 0)))

	local refused: boolean, why: string = Refuses("don't fit", Reliable.writeDeath, 4096, 0, 0, 0, vector.zero)
	if not refused then
		return false, `A death of slot 4096 was written: {why}`
	end

	return true, nil
end
