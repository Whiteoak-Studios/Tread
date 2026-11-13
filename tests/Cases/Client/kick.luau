--[[
    client:kick hands the pool a kick for the slot a spawn handed, as given,
    and none for a table its spawn didn't hand, for a slot with no rig or
    for a slot whose rig went away
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Handle = require("../../Fixtures/Client/Handle")

local OTHER: number = 3
local NOWHERE: number = 77 -- A slot no rig is drawn for
local GENERATION: number = 2
local TICK: number = 50
local SETTLE: number = 10 -- Frames until the render time reaches the record, past the interpolation delay
local PITCH: number = 0.25 -- Radians
local YAW: number = -0.125
local DURATION: number = 0.5 -- Seconds

-- One kick the pool was handed
type Kicked = { slot: number, pitch: number, yaw: number, duration: number }

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle

	-- The pool's stand-in has no kick, so one is added that writes each call down
	local kicks: { Kicked } = {}
	handle._rigs.kick = function (_: any, slot: number, pitch: number, yaw: number, duration: number)
		table.insert(kicks, { slot = slot, pitch = pitch, yaw = yaw, duration = duration })
	end

	local spawned: { [number]: any } = {}
	handle:onSpawned(function (slot: any, _: any)
		spawned[slot.id] = slot
	end)

	local other: any = roblox.Instance.new("Player")
	other.Name = "Other"

	rig.handshake()
	rig.slots({ { slot = OTHER, generation = GENERATION, rig = "A", player = other } })
	rig.relay({
		tick = TICK,
		reveals = { { slot = OTHER, generation = GENERATION, kind = "Player" } },
		records = {
			{ slot = OTHER, generation = GENERATION, position = vector.create(100, 5, 200), word = rig.word({}) },
		},
	})
	rig.frames(SETTLE)

	local slot: any = spawned[OTHER]
	if slot == nil then
		return false, `The reveal drew no rig for slot {OTHER}`
	end

	-- 1) The slot its spawn handed: the pool takes the kick as given
	handle:kick(slot, PITCH, YAW, DURATION)

	local kicked: Kicked? = kicks[1]
	if #kicks ~= 1 or kicked == nil then
		return false, `A kick on a drawn slot handed the pool {#kicks} kicks, not 1`
	elseif kicked.slot ~= OTHER or kicked.pitch ~= PITCH or kicked.yaw ~= YAW or kicked.duration ~= DURATION then
		local got: string = `{kicked.pitch}, {kicked.yaw} over {kicked.duration} s on slot {kicked.slot}`
		return false, `The pool was handed {got}, not {PITCH}, {YAW} over {DURATION} s on slot {OTHER}`
	end

	-- 2) A table naming the slot that its spawn didn't hand, and a slot with no rig
	handle:kick({ id = OTHER, kind = "Player", player = other, withheld = false }, PITCH, YAW, DURATION)
	handle:kick({ id = NOWHERE, kind = "Player", player = nil, withheld = false }, PITCH, YAW, DURATION)
	if #kicks ~= 1 then
		return false, `Kicks on slots with no rig drawn handed the pool {#kicks - 1} kicks`
	end

	-- 3) The slot its spawn handed, once its rig went away with its hide, which frames bring the render time to
	rig.relay({ tick = TICK + 1, hides = { { slot = OTHER, generation = GENERATION } } })
	rig.frames(SETTLE)
	if handle._rigged[OTHER] ~= nil then
		return false, `The hide left slot {OTHER}'s rig out`
	end

	handle:kick(slot, PITCH, YAW, DURATION)
	if #kicks ~= 1 then
		return false, "A kick on a slot whose rig went away was handed to the pool"
	end

	return true, nil
end
