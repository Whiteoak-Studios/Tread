--[[
    A hide closes its stretch once the render time passes its tick, not when
    it arrives; a newer reveal before then takes it back, a reveal older
    than it is a stale repeat, and a newer one after it opens a new stretch
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local HIDDEN: number = 6 -- Hidden at 25
local BACK: number = 7 -- Hidden at 25 and revealed again at 26
local GENERATION: number = 1

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate

	viewer.announce(HIDDEN, GENERATION, "A")
	viewer.announce(BACK, GENERATION, "A")

	local function count(list: { any }, slot: number): number
		local found: number = 0
		for _, entry: any in list do
			if entry == slot or (type(entry) == "table" and entry.slot == slot) then
				found += 1
			end
		end

		return found
	end

	-- Each slot is sent from 20, with a record a tick until its hide
	for tick: number = 20, 27 do
		local reveals: { any } = {}
		local hides: { any } = {}
		local records: { any } = {}

		if tick == 20 then
			table.insert(reveals, { slot = HIDDEN, generation = GENERATION, kind = "Player" })
			table.insert(reveals, { slot = BACK, generation = GENERATION, kind = "Player" })
		elseif tick == 25 then
			table.insert(hides, { slot = HIDDEN, generation = GENERATION })
			table.insert(hides, { slot = BACK, generation = GENERATION })
		elseif tick == 26 then
			table.insert(reveals, { slot = BACK, generation = GENERATION, kind = "Player" })
		end

		if tick < 25 then
			table.insert(records, { slot = HIDDEN, generation = GENERATION, position = vector.create(tick, 0, 0) })
		end

		if tick ~= 25 then
			table.insert(records, { slot = BACK, generation = GENERATION, position = vector.create(tick, 0, 0) })
		end

		viewer.send({ tick = tick, reveals = reveals, hides = hides, records = records })
	end

	if #viewer.hides ~= 0 then
		return false, "A hide was told when it arrived, before the render time reached it"
	end

	-- Every block came at once, so the render time lands 3 ticks behind the newest at 24, then moves to 24.5
	Interpolate.frame(0)
	Interpolate.frame(0.025)

	local renderTime: number = Interpolate.renderTime()
	if count(viewer.hides, HIDDEN) ~= 0 or not viewer.pose(HIDDEN) then
		return false, `At render time {renderTime}, before the hide's tick, the slot was no longer drawn`
	end

	-- To 25.5, past it
	Interpolate.frame(0.05)

	local closed: number = count(viewer.hides, HIDDEN)
	if closed ~= 1 then
		return false, `Past the hide's tick, at {Interpolate.renderTime()}, its stretch was told closed {closed} times`
	elseif viewer.pose(HIDDEN) then
		return false, "The slot still drew after its stretch closed"
	end

	if count(viewer.hides, BACK) ~= 0 or not viewer.pose(BACK) then
		return false, "A reveal newer than a waiting hide didn't take the hide back"
	end

	-- A reveal older than the hide, arriving late, is a stale repeat
	viewer.send({ tick = 24, reveals = { { slot = HIDDEN, generation = GENERATION, kind = "Player" } } })
	if count(viewer.reveals, HIDDEN) ~= 1 then
		return false, "A late reveal from before the hide opened the stretch again"
	end

	-- A newer one opens a new stretch
	viewer.send({ tick = 29, reveals = { { slot = HIDDEN, generation = GENERATION, kind = "Player" } } })
	if count(viewer.reveals, HIDDEN) ~= 2 then
		return false, "A reveal after the hide didn't open a new stretch"
	end

	-- A disconnected hide callback hears nothing more
	local heard: number = 0
	local disconnect: () -> () = Interpolate.onHide(function ()
		heard += 1
	end)

	disconnect()
	viewer.send({ tick = 30, hides = { { slot = BACK, generation = GENERATION } } })
	Interpolate.frame(0.5)

	if heard ~= 0 or count(viewer.hides, BACK) ~= 1 then
		return false, `After its disconnect a hide callback heard {heard} hides`
	end

	return true, nil
end
