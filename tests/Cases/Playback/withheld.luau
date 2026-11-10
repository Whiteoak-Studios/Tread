--[[
    A player the withheld frames carry is drawn marked withheld and
    outlined, dropped once 4 relay intervals pass with no withheld record of
    it, and a reveal on the observed frames ends its withholding and keeps
    it drawn
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 700
local FRAMES: number = 16
local HIDDEN: number = 11 -- Withheld from K + 1 to K + 5, then never again
local CAUGHT: number = 12 -- Withheld from K + 1 to K + 7, then revealed at K + 8
local TARGET: number = 9
local GENERATION: number = 1
local HIDDEN_LAST: number = 5
local REVEALED: number = 8
local INTERVALS: number = 4 -- Relay intervals a withheld character goes unrefreshed before it is dropped

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	rig.handshake()

	local clip: any = Clip.new(rig)
	local log: any = Clip.log(rig)
	local relay: number = rig.shared.rates.relay

	local spawned: { [number]: any } = {}
	handle:onSpawned(function (slot: any, _: Model)
		spawned[slot.id] = slot
	end)

	local function record(slot: number, tick: number): { [string]: any }
		return { slot = slot, generation = GENERATION, position = vector.create(slot, 0, tick - K) }
	end

	local ticks: { buffer } = { clip.keyframe({ tick = K }) }
	local withheld: { buffer } = {}

	for index: number = 0, FRAMES - 1 do
		local tick: number = K + index
		local reveals: { any } = {}
		local records: { any } = {}
		local hidden: { any } = {}

		if index == REVEALED then
			reveals = { { slot = CAUGHT, generation = GENERATION, kind = "Player" } }
		end

		if index >= REVEALED then
			table.insert(records, record(CAUGHT, tick))
		elseif index >= 1 then
			table.insert(hidden, record(CAUGHT, tick))
		end

		if index >= 1 and index <= HIDDEN_LAST then
			table.insert(hidden, record(HIDDEN, tick))
		end

		table.insert(
			ticks,
			clip.frame({
				tick = tick,
				blocks = { { tick = tick, reveals = reveals, records = records } },
				owner = { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, tick), lag = 0 },
			})
		)

		table.insert(withheld, clip.frame({ tick = tick, blocks = { { tick = tick, records = hidden } } }))
	end

	local playback: any = handle:play(ticks, withheld)

	-- 1) Withheld from the target, each is drawn marked withheld and outlined
	playback:render(3 / relay)
	for _, slot: number in { HIDDEN, CAUGHT } do
		local drawn: any = spawned[slot]
		if drawn == nil or Clip.out(rig.pool)[slot] == nil then
			return false, `Slot {slot}, which the withheld frames carry, wasn't drawn`
		elseif drawn.withheld ~= true then
			return false, `Slot {slot} was drawn as sent to the target, not withheld from it`
		elseif log.outlined[slot] ~= true then
			return false, `Slot {slot} was drawn without the spectate outline`
		end
	end

	-- 2) The one whose records stopped stays drawn for 4 intervals after its last, and is dropped past them
	playback:render((HIDDEN_LAST + INTERVALS) / relay)
	if Clip.out(rig.pool)[HIDDEN] == nil then
		return false, "The withheld character was dropped before 4 intervals passed with no record of it"
	end

	playback:render((HIDDEN_LAST + INTERVALS + 0.5) / relay)
	if Clip.out(rig.pool)[HIDDEN] ~= nil then
		return false, "The withheld character was never dropped once its records stopped"
	end

	-- 3) A reveal on the observed frames ends the other's withholding, and it stays drawn
	if Clip.out(rig.pool)[CAUGHT] == nil or spawned[CAUGHT].withheld ~= false then
		return false,
			`The revealed character's rig was out {Clip.out(rig.pool)[CAUGHT] ~= nil}, withheld {spawned[CAUGHT].withheld}`
	end

	playback:destroy()

	return true, nil
end
