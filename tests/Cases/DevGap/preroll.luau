--[[
    The frames the gap check's client holds before a window, and the capture
    a window opens with from them: the hold's reach, the first arrival and
    thaw over later ones, and that capture carried through its line and back
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local TICKS: number = 10 -- Relay ticks the hold keeps by render time

type Place = { x: number, z: number }
type Frame = { render: number, drawn: boolean }
type Thaw = { from: Place, to: Place? }
type Held = { frame: Frame, arrived: boolean, thaw: Thaw? }

-- Render times held one after another, and the first of them each hold keeps: the hold at 670 keeps 660, exactly
-- TICKS older, the one at 672 drops it, and the one at 675.5 drops 663 and keeps 665.5
local RENDERS: { number } = { 660, 663, 665.5, 670, 672, 675.5 }
local FIRST: { number } = { 1, 1, 1, 1, 2, 3 }

-- Where the frozen rig stands as the window opens, the first thaw held, a later one with its rig out of the Workspace,
-- and one heard after the last frame held
local STOOD: Place = { x = 1999.5, z = -2025.75 }
local EARLIER: Thaw = { from = { x = 1999.5, z = -2027.25 }, to = { x = 1999.5, z = -2003.75 } }
local LATER: Thaw = { from = { x = 1999.5, z = -2010.5 }, to = nil }
local PENDING: Thaw = { from = { x = 1999.5, z = -2030 }, to = { x = 1999.5, z = -2001.25 } }

local ARRIVAL: number = 2 -- The first of the thawed frames a reveal arrived before, as one did the fourth

local function entry(render: number, drawn: boolean, arrived: boolean, thaw: Thaw?): Held
	return { frame = { render = render, drawn = drawn }, arrived = arrived, thaw = thaw }
end

-- Whether two places are the same, or both none
local function same(place: Place?, expected: Place?): boolean
	if place == nil or expected == nil then
		return place == expected
	end

	return place.x == expected.x and place.z == expected.z
end

-- Why a capture's frames aren't the held ones, in order, nil when they are
local function framesOf(capture: any, held: { Held }): string?
	if #capture.frames ~= #held then
		return `{#capture.frames} frames, not {#held}`
	end

	for index: number, kept: Held in held do
		local frame: Frame = capture.frames[index]
		if frame.render ~= kept.frame.render or frame.drawn ~= kept.frame.drawn then
			return `frame {index} at {frame.render} drawn {frame.drawn}, not {kept.frame.render} {kept.frame.drawn}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local GapLine: any = loaded.require(dataModel:GetService("ReplicatedStorage").Shared.Dev.GapLine)

	-- 1) Each hold keeps the frames within TICKS of the newest by render time, the one exactly TICKS older included
	local held: { Held } = {}
	for step: number, render: number in RENDERS do
		GapLine.hold(held, entry(render, false, false, nil), TICKS)

		local first: number = FIRST[step]
		if #held ~= step - first + 1 then
			return false, `Holding {render} kept {#held} frames, not the {step - first + 1} from {RENDERS[first]} on`
		end

		for index: number, kept: Held in held do
			local expected: number = RENDERS[first + index - 1]
			if kept.frame.render ~= expected then
				return false, `Holding {render} kept {kept.frame.render} at {index}, not {expected}`
			end
		end
	end

	-- 2) A capture begun from held frames: the first arrival's frame, and the first thaw's places over a later one and
	-- over the one heard since, with the held frames left as they were
	local thawed: { Held } = {
		entry(664, false, false, nil),
		entry(664.25, false, true, nil),
		entry(664.5, true, false, EARLIER),
		entry(664.75, true, true, LATER),
	}

	local before: { Held } = table.clone(thawed)
	local capture: any = GapLine.begin(thawed, STOOD, PENDING)
	local wrong: string? = framesOf(capture, thawed)
	if wrong then
		return false, `A capture begun from held frames holds {wrong}`
	elseif capture.arrival ~= ARRIVAL or capture.cut ~= 0 then
		return false, `A capture begun from held frames arrived at {capture.arrival} with {capture.cut} cut`
	elseif not same(capture.frozen, EARLIER.from) or not same(capture.thawed, EARLIER.to) then
		return false, "A capture begun from held frames didn't take the first thaw's places"
	end

	if #thawed ~= #before then
		return false, `Beginning a capture left {#thawed} frames held, not {#before}`
	end

	for index: number, kept: Held in before do
		if thawed[index] ~= kept then
			return false, `Beginning a capture changed frame {index} of those held`
		end
	end

	-- 3) That capture through its line and back, its frames, arrival and places kept
	local back: any = GapLine.decode(GapLine.encode(capture))
	if not back then
		return false, "A capture begun from held frames didn't come back through its line"
	end

	wrong = framesOf(back, thawed)
	if wrong then
		return false, `A capture begun from held frames came back through its line with {wrong}`
	elseif back.arrival ~= ARRIVAL or back.cut ~= 0 then
		return false, `A capture begun from held frames came back arrived at {back.arrival} with {back.cut} cut`
	elseif not same(back.frozen, EARLIER.from) or not same(back.thawed, EARLIER.to) then
		return false, "A capture begun from held frames came back without the first thaw's places"
	end

	-- 4) With no thaw held, the one heard since gives the places, and with neither the frozen rig standing does
	local bare: { Held } = { entry(680, false, false, nil), entry(680.25, true, false, nil) }
	local heard: any = GapLine.begin(bare, STOOD, PENDING)
	if heard.arrival ~= nil or not same(heard.frozen, PENDING.from) or not same(heard.thawed, PENDING.to) then
		return false, "A capture with no thaw held didn't take the one heard since"
	end

	local stood: any = GapLine.begin(bare, STOOD, nil)
	if stood.arrival ~= nil or not same(stood.frozen, STOOD) or stood.thawed ~= nil then
		return false, "A capture with no thaw at all didn't take where the frozen rig stands"
	end

	-- 5) No frames held: an empty capture, its frozen place where the rig stands
	local empty: any = GapLine.begin({}, STOOD, nil)
	wrong = framesOf(empty, {})
	if wrong or empty.arrival ~= nil or empty.cut ~= 0 or not same(empty.frozen, STOOD) or empty.thawed ~= nil then
		return false, "A capture begun from no frames wasn't empty with where the frozen rig stands"
	end

	return true, nil
end
