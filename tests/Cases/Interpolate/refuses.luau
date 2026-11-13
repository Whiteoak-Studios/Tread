--[[
    Interpolate refuses work before start and a second start, a block that
    isn't one and a look part its declarations refuse, a frame's seconds
    below 0 or not finite, a slot outside the table, and a callback that
    isn't a function
--]]

--!strict
local Environment = require("../../Environment")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local INTERPOLATE: string = "src/Client/Interpolate.luau"
local SLOT: number = 70

-- Whether a call errors
local function refuses(call: (...any) -> ...any, ...: any): boolean
	return not pcall(call, ...)
end

return function (): (boolean, string | nil)
	local fresh: any = Environment.load(INTERPOLATE)

	local early: { [string]: () -> () } = {
		receive = function ()
			fresh.receive(buffer.create(8))
		end,
		frame = function ()
			fresh.frame(0)
		end,
		pose = function ()
			fresh.pose(0, {})
		end,
		slots = function ()
			fresh.slots({})
		end,
		death = function ()
			fresh.death(0, 0, 0, 0, 0)
		end,
	}

	for member: string, call: () -> () in early do
		if not refuses(call) then
			return false, `Interpolate.{member} ran before Interpolate.start`
		end
	end

	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate

	if not refuses(Interpolate.start, viewer.settings, viewer.rates, viewer.limits, {}) then
		return false, "Interpolate.start ran a second time"
	end

	-- 7 B, short of a header
	if not refuses(Interpolate.receive, buffer.create(7)) then
		return false, "A 7 B block was read"
	end

	-- A look entry whose 1 B look part runs out before its declarations' fields do
	viewer.announce(SLOT, 1, "A")

	local look: buffer = buffer.create(13)
	buffer.writeu16(look, 0, 1) -- Sequence
	buffer.writeu16(look, 2, 1) -- Tick
	buffer.writeu8(look, 6, 1) -- One look entry
	buffer.writeu16(look, 8, viewer.Record.id(SLOT, 1))
	buffer.writeu8(look, 10, 1) -- Its look part present
	buffer.writeu8(look, 11, 1) -- Of 1 B
	buffer.writeu8(look, 12, 0xFF)

	if not refuses(Interpolate.receive, look) then
		return false, "A look part its declarations refuse was applied"
	end

	for _, seconds: number in { -0.01, 0 / 0, math.huge } do
		if not refuses(Interpolate.frame, seconds) then
			return false, `A frame of {seconds} s ran`
		end
	end

	local state: any = viewer.State.new()
	for _, slot: number in { -1, viewer.Constants.SLOTS, 1.5 } do
		if not refuses(Interpolate.pose, slot, state) then
			return false, `Slot {slot} was posed`
		end
	end

	local members: { string } = { "onReveal", "onHide", "onDress", "onHold", "onFootstep" }
	for _, member: string in members do
		if not refuses(Interpolate[member], "callback") then
			return false, `Interpolate.{member} took a string`
		end
	end

	return true, nil
end
