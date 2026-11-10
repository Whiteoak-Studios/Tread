--[[
    Interpolate.revealOpen tells every reveal callback again of each
    stretch open now, with its kind, look and held item, and of no stretch
    a hide or the slot table has closed
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local GENERATION: number = 1
local PLAYER: number = 3
local SLEEPER: number = 4
local HIDDEN: number = 5
local FREED: number = 6
local TICK: number = 10
local HEAD: number = 9 -- A slot-table field the codec fixture declares
local CHEST: number = 2
local ITEM: number = 7
local FRAME: number = 1 / 20 -- A relay interval, past which the hide's tick falls behind the render time
local FRAMES: number = 10

return function (): (boolean, string | nil)
	local viewer: any = Viewer.new()
	local Interpolate: any = viewer.Interpolate

	for _, slot: number in { PLAYER, SLEEPER, HIDDEN, FREED } do
		viewer.announce(slot, GENERATION, "A")
	end

	local function record(slot: number): { [string]: any }
		return { slot = slot, generation = GENERATION, position = vector.create(slot, 0, 0) }
	end

	viewer.send({
		tick = TICK,
		reveals = {
			{ slot = PLAYER, generation = GENERATION, kind = "Player" },
			{ slot = SLEEPER, generation = GENERATION, kind = "Sleeper" },
			{ slot = HIDDEN, generation = GENERATION, kind = "Player" },
			{ slot = FREED, generation = GENERATION, kind = "Player" },
		},
		looks = {
			{
				slot = PLAYER,
				generation = GENERATION,
				outfit = { head = HEAD, chest = CHEST, colors = {} },
				held = { item = ITEM },
			},
		},
		records = { record(PLAYER), record(SLEEPER), record(HIDDEN), record(FREED) },
	})

	-- One stretch hidden once the render time passes its hide, and one ended by the slot table
	viewer.send({ tick = TICK + 1, hides = { { slot = HIDDEN, generation = GENERATION } } })
	for _ = 1, FRAMES do
		Interpolate.frame(FRAME)
	end
	viewer.announce(FREED, GENERATION, nil)

	table.clear(viewer.reveals)
	Interpolate.revealOpen()

	local told: { [number]: any } = {}
	for _, reveal: any in viewer.reveals do
		told[reveal.slot] = reveal
	end

	local player: any = told[PLAYER]
	if player == nil or player.kind ~= "Player" then
		return false, "The open player's stretch wasn't raised again as a player"
	elseif player.outfit.head ~= HEAD or player.held == nil or player.held.item ~= ITEM then
		return false, "The open player's stretch was raised again without its look or held item"
	elseif told[SLEEPER] == nil or told[SLEEPER].kind ~= "Sleeper" then
		return false, "The open sleeper's stretch wasn't raised again as a sleeper"
	elseif told[HIDDEN] ~= nil then
		return false, "A stretch its hide closed was raised again"
	elseif told[FREED] ~= nil then
		return false, "A stretch the slot table ended was raised again"
	end

	return true, nil
end
