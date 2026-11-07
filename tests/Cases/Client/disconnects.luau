--[[
    Every client signal runs each callback under its own xpcall, so one that
    throws stops neither the next callback nor the rest of the message, the
    marker callback gets the spawn's Slot, each disconnect closure ends its
    callback, and a callback that is no function is refused
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Handle = require("../../Fixtures/Client/Handle")

local OWN: number = 9
local FIRST: number = 3 -- Drawn while the callbacks are connected
local SECOND: number = 5 -- Revealed in the same block as FIRST, after FIRST's spawn throws
local LATER: number = 4 -- Drawn once they are disconnected
local GENERATION: number = 1
local TICK: number = 50
local FRAMES: number = 12
local OFFSET: vector = vector.create(5, 0, 0) -- Where a replaying OwnerState sits from the body

local SIGNALS: { string } = { "onSpawned", "onDespawned", "onFootstep", "onCorrected", "onMarker" }

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool

	-- Two callbacks a signal: the first throws, and the second writes down its first argument
	local heard: { [string]: { any } } = {}
	local thrown: { [string]: number } = {}
	local disconnects: { () -> () } = {}

	for _, signal: string in SIGNALS do
		heard[signal] = {}
		thrown[signal] = 0

		table.insert(
			disconnects,
			handle[signal](handle, function (...: any)
				thrown[signal] += 1
				error(`This {signal} callback throws on purpose, to show the others still run`)
			end)
		)

		table.insert(
			disconnects,
			handle[signal](handle, function (first: any, ...: any)
				table.insert(heard[signal], first)
			end)
		)
	end

	local step: { [string]: any } =
		{ at = vector.create(1, 0, 1), kind = "Walk", material = roblox.Enum.Material.Grass }
	local function draw(slot: number, tick: number, extra: number?)
		local reveals: { any } = { { slot = slot, generation = GENERATION, kind = "Npc" } }
		if extra then
			table.insert(reveals, { slot = extra, generation = GENERATION, kind = "Npc" })
		end

		rig.relay({ tick = tick, reveals = reveals, footsteps = { step } })
	end

	local at: vector = vector.create(0, 50, 0)
	local function replay(tick: number, command: number)
		rig.owner(rig.body(at + OFFSET, command, tick))
	end

	rig.handshake()
	rig.slots({
		{ slot = FIRST, generation = GENERATION, rig = "A" },
		{ slot = SECOND, generation = GENERATION, rig = "A" },
		{ slot = LATER, generation = GENERATION, rig = "A" },
	})
	draw(FIRST, TICK, SECOND)
	pool.marker(FIRST, "Step", "Left")

	rig.own(OWN, GENERATION)
	rig.owner(rig.body(at, 0, TICK))
	rig.frames(2)
	replay(TICK + 1, 1)
	rig.relay({ tick = TICK + 1, hides = { { slot = FIRST, generation = GENERATION } } })
	rig.frames(FRAMES)

	for _, signal: string in SIGNALS do
		if thrown[signal] < 1 or #heard[signal] < 1 then
			return false, `{signal}'s callbacks ran {thrown[signal]} and {#heard[signal]} times, not at least once each`
		end
	end

	local spawned: { any } = heard.onSpawned
	if #spawned ~= 3 or spawned[1].id ~= FIRST or spawned[2].id ~= SECOND or spawned[3].id ~= OWN then
		return false,
			`{#spawned} spawns were told, not slot {FIRST}'s, slot {SECOND}'s after it threw, then the owner's`
	elseif heard.onMarker[1] ~= spawned[1] then
		return false, "The marker callback got another table than the Slot its rig's spawn gave"
	elseif heard.onDespawned[1] ~= spawned[1] then
		return false, "The despawn told another table than the Slot its spawn gave"
	elseif typeof(heard.onFootstep[1].at) ~= "Vector3" then
		return false, "The footstep callback got no copy on Vector3"
	end

	for _, disconnect: () -> () in disconnects do
		disconnect()
	end

	local counts: { [string]: number } = {}
	for _, signal: string in SIGNALS do
		counts[signal] = #heard[signal] + thrown[signal]
	end

	draw(LATER, TICK + 2)
	pool.marker(LATER, "Step", "Right")
	replay(TICK + 3, 3)
	rig.relay({ tick = TICK + 3, hides = { { slot = LATER, generation = GENERATION } } })
	rig.frames(FRAMES)

	for _, signal: string in SIGNALS do
		if #heard[signal] + thrown[signal] ~= counts[signal] then
			return false, `{signal}'s callbacks still ran once disconnected`
		end
	end

	if #pool.of("release") < 2 then
		return false, "The second hide never reached the pool, so the case proved nothing"
	end

	for _, signal: string in SIGNALS do
		local refused: boolean, reason: any = pcall(handle[signal], handle, 5)
		if refused then
			return false, `{signal} took a number as its callback`
		elseif not string.find(tostring(reason), "takes a function", 1, true) then
			return false, `{signal} refused a number as "{reason}"`
		end
	end

	return true, nil
end
