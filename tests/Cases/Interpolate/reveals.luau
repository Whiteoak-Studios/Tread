--[[
    A reveal opens a stretch once, handing on the slot table's player and
    the look its block brought; repeats change nothing, a newer kind is told
    again, an older reveal is a stale repeat, and the slot draws from its
    first record once the render time reaches it
--]]

--!strict
local Game = require("../../Fixtures/Codec/Game")
local Same = require("../../Fixtures/Codec/Same")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local roblox: any = require("@lune/roblox")

local SLOT: number = 5
local OTHER: number = 6
local GENERATION: number = 2

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate
	local player: any = roblox.Instance.new("Folder")

	viewer.announce(SLOT, GENERATION, "A", player)
	viewer.announce(OTHER, GENERATION, "A")

	local function send(tick: number, kind: string?)
		local reveals: { any }? = nil
		if kind then
			reveals = { { slot = SLOT, generation = GENERATION, kind = kind } }
		end

		viewer.send({
			tick = tick,
			reveals = reveals,
			looks = { { slot = SLOT, generation = GENERATION, outfit = Game.high.slot, held = Game.high.held } },
			records = { { slot = SLOT, generation = GENERATION, position = vector.create(tick, 0, 0) } },
		})
	end

	-- The reveal, then two repeats of it with its look, as each rides until acknowledged
	send(10, "Player")
	send(11, "Player")
	send(12, "Player")

	if #viewer.reveals ~= 1 then
		return false, `A reveal and two repeats were told {#viewer.reveals} times, not once`
	end

	local told: { [string]: any } = viewer.reveals[1]
	if told.slot ~= SLOT or told.kind ~= "Player" or told.player ~= player then
		return false, `The reveal was told as slot {told.slot}, kind {told.kind}, without the slot table's player`
	end

	local differs: string? = Same(Game.high.slot, told.outfit, "the revealed look")
		or Same(Game.high.held, told.held, "the revealed held item")
	if differs then
		return false, differs
	end

	if #viewer.dresses ~= 1 or #viewer.holds ~= 1 then
		return false, `The repeated look was told {#viewer.dresses} and {#viewer.holds} times, not once each`
	end

	-- The render time lands at 9, before the first record
	Interpolate.frame(0)
	local drawn: boolean = viewer.pose(SLOT)
	if drawn then
		return false, "The slot drew before the render time reached its first record"
	end

	Interpolate.frame(0.05)
	local state: any
	drawn, state = viewer.pose(SLOT)
	if not drawn or state.position.x ~= 10 then
		return false, `At its first record's tick the slot drew {drawn} at {state.position}`
	end

	-- A newer kind, such as falling asleep in view, is told again
	send(13, "Sleeper")
	if #viewer.reveals ~= 2 or viewer.reveals[2].kind ~= "Sleeper" then
		return false, "A reveal of a new kind wasn't told as the slot's new kind"
	end

	-- An older reveal arriving late is a stale repeat
	send(12, "Player")
	if #viewer.reveals ~= 2 then
		return false, "A late reveal older than the newest was told"
	end

	-- A disconnected callback hears nothing more
	local heard: number = 0
	local disconnect: () -> () = Interpolate.onReveal(function ()
		heard += 1
	end)

	disconnect()
	viewer.send({ tick = 14, reveals = { { slot = OTHER, generation = GENERATION, kind = "Npc" } } })

	if heard ~= 0 or #viewer.reveals ~= 3 then
		return false, `After its disconnect a reveal callback heard {heard} reveals`
	end

	return true, nil
end
