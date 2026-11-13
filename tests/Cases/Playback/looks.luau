--[[
    A clip rig wears the look and holds the item its life's newest parts by
    the clip tick give: the keyframe's before a later look entry and that
    one after it, a held part of 0 B clearing the hands, and a seek back
    putting the earlier ones back
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 800
local FRAMES: number = 12
local DRESSED: number = 13
local TARGET: number = 9
local GENERATION: number = 1
local FIRST_HEAD: number = 1 -- The keyframe's look, a slot-table field the example declares
local SECOND_HEAD: number = 2 -- The look entry's at K + 5
local ITEM: number = 5 -- The keyframe's held item
local RESTYLED: number = 5
local EMPTIED: number = 8

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	rig.handshake()

	local clip: any = Clip.new(rig)
	Clip.log(rig)
	local relay: number = rig.shared.rates.relay

	local record: { [string]: any } = { slot = DRESSED, generation = GENERATION, position = vector.zero }
	local ticks: { buffer } = {
		clip.keyframe({
			tick = K,
			characters = {
				{
					slot = DRESSED,
					generation = GENERATION,
					kind = "Player",
					record = {},
					outfit = { head = FIRST_HEAD },
					held = { item = ITEM },
				},
			},
		}),
	}

	for index: number = 0, FRAMES - 1 do
		local tick: number = K + index
		local looks: { any } = {}
		if index == RESTYLED then
			looks = { { slot = DRESSED, generation = GENERATION, outfit = { head = SECOND_HEAD } } }
		elseif index == EMPTIED then
			looks = { { slot = DRESSED, generation = GENERATION, empty = true } }
		end

		table.insert(
			ticks,
			clip.frame({
				tick = tick,
				blocks = { { tick = tick, looks = looks, records = { record } } },
				owner = { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, tick), lag = 0 },
			})
		)
	end

	-- The look and held item the pool last gave the rig, from its checkout and every dress and hold since
	local function worn(): (number?, number?)
		local head: number? = nil
		local item: number? = nil

		for _, call: any in pool.calls do
			if call.slot == DRESSED then
				if call.member == "checkout" or call.member == "dress" then
					head = call.outfit.head
				elseif call.member == "hold" then
					item = call.held and call.held.item
				elseif call.member == "release" then
					head, item = nil, nil
				end
			end
		end

		return head, item
	end

	local playback: any = handle:play(ticks)

	-- One render's look and held item, against the ones expected
	local function check(time: number, head: number, item: number?, when: string): string?
		playback:render(time)

		local wornHead: number?, wornItem: number? = worn()
		if wornHead ~= head or wornItem ~= item then
			return `{when}, the rig wore head {wornHead} and held {wornItem}, not {head} and {item}`
		end

		return nil
	end

	local problem: string? = check(2 / relay, FIRST_HEAD, ITEM, "Before the look entry")
		or check(6 / relay, SECOND_HEAD, ITEM, "After the look entry")
		or check(9 / relay, SECOND_HEAD, nil, "After a held part of 0 B")
		or check(2 / relay, FIRST_HEAD, ITEM, "After a seek back")
	if problem then
		return false, problem
	end

	playback:destroy()

	return true, nil
end
