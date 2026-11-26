--[[
    The gap check's judge: a frame is late only when its render time falls
    in an open tick, by the wire's 16 bits, while the rig was undrawn; the
    rig's draw is found from the reveal's arrival on; the jump needs both ends
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local WRAP: number = 2 ^ 16 -- A block's relay tick is a u16

type Frame = { render: number, drawn: boolean }
type Place = { x: number, z: number }

local function frame(render: number, drawn: boolean): Frame
	return { render = render, drawn = drawn }
end

-- A set of open ticks, as the tracker keys them
local function opened(Gap: any, ticks: { number }): { [number]: boolean }
	local open: { [number]: boolean } = {}
	for _, tick: number in ticks do
		open[Gap.wire(tick)] = true
	end

	return open
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local Gap: any = loaded.require(server.Gap)

	-- 1) Ticks 100 to 102 open. Two undrawn frames of tick 100 come before the reveal's arrival in the same tick, which
	-- draws the rig; a frame of tick 102 is undrawn again; frames in the closed ticks 99 and 103 count nothing
	local split: { Frame } = {
		frame(99.5, false),
		frame(100.2, false),
		frame(100.6, false),
		frame(100.9, true),
		frame(101.3, true),
		frame(102.5, false),
		frame(103.1, false),
	}

	local late: number, drawnAt: number? = Gap.judge(split, 4, opened(Gap, { 100, 101, 102 }))
	if late ~= 3 or drawnAt ~= 4 then
		return false, `Frames split inside an open tick gave {late} late, drawn at {drawnAt}, not 3 late, drawn at 4`
	end

	-- 2) The rig still drawn as the window opened, then hidden; its reveal arrives at frame 4 with no past, so it draws
	-- only at frame 6. The first frame, drawn before the arrival, is never the reveal's draw
	local frozen: { Frame } = {
		frame(98.0, true),
		frame(98.5, false),
		frame(99.0, false),
		frame(99.4, false),
		frame(99.8, false),
		frame(100.3, true),
	}

	late, drawnAt = Gap.judge(frozen, 4, opened(Gap, { 99, 100 }))
	if late ~= 3 or drawnAt ~= 6 then
		return false,
			`A reveal that drew two frames after its arrival gave {late} late, drawn at {drawnAt}, not 3 and 6`
	end

	-- 3) No arrival gives no draw, and an arrival no drawn frame follows gives none either, the frames still judged
	late, drawnAt = Gap.judge(frozen, nil, opened(Gap, { 98 }))
	if late ~= 1 or drawnAt ~= nil then
		return false, `Frames with no arrival gave {late} late, drawn at {drawnAt}, not 1 and none`
	end

	local never: { Frame } = { frame(10.5, false), frame(11.5, false) }
	late, drawnAt = Gap.judge(never, 1, opened(Gap, { 10, 11 }))
	if late ~= 2 or drawnAt ~= nil then
		return false, `An arrival never drawn gave {late} late, drawn at {drawnAt}, not 2 and none`
	end

	-- 4) Across the wire's wrap: the server's ticks 65535 and 65536 open, a client whose render time counts from a
	-- first block a whole wrap later, frames at those ticks late and the one after not
	local crossing: any = Gap.crossing("pass", "near", 1, 1)
	for _, tick: number in { WRAP - 1, WRAP } do
		Gap.track(crossing, {
			tick = tick,
			zone = true,
			hull = true,
			body = true,
			reason = "Clear",
			revealed = nil,
			hid = false,
		})
	end

	local wrapped: { Frame } = {
		frame(2 * WRAP - 0.5, false),
		frame(2 * WRAP + 0.25, false),
		frame(2 * WRAP + 1.5, false),
	}

	late = Gap.judge(wrapped, nil, crossing.bodyOpen)
	if late ~= 2 then
		return false, `Frames across the wire's wrap gave {late} late, not 2`
	end

	-- 5) The jump stays behind the walls only when both its places are known and both are hidden
	local function hidden(place: Place): boolean
		return place.z < 0
	end

	local behind: Place = { x = 0, z = -20 }
	local shown: Place = { x = 0, z = 3 }
	local jumps: { { frozen: Place?, thawed: Place?, hidden: boolean } } = {
		{ frozen = behind, thawed = { x = 0, z = -2 }, hidden = true },
		{ frozen = behind, thawed = shown, hidden = false },
		{ frozen = shown, thawed = behind, hidden = false },
		{ frozen = nil, thawed = behind, hidden = false },
		{ frozen = behind, thawed = nil, hidden = false },
	}

	for index: number, jump: { frozen: Place?, thawed: Place?, hidden: boolean } in jumps do
		local judged: boolean = Gap.behind(jump.frozen, jump.thawed, hidden)
		if judged ~= jump.hidden then
			return false, `Jump {index} was judged behind the walls {judged}, not {jump.hidden}`
		end
	end

	return true, nil
end
