--[[
    Predict refuses what it cannot run: any call before start, a second
    start, start's functions, the look among them, missing or a debt under
    one tick, a frame of negative, infinite or NaN seconds, an OwnerState
    that isn't one, the eye before a body, and a callback that's no function
--]]

--!strict
local Environment = require("../../Environment")
local Harness = require("../../Fixtures/Predict/Harness")

local PREDICT: string = "src/Client/Predict.luau"

-- Why a call that should error did not, or nil
local function refused(label: string, call: (...any) -> ...any, ...: any): string?
	local ran: boolean = pcall(call, ...)
	if ran then
		return `Predict took {label}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local fresh: any = Environment.load(PREDICT)
	local early: string? = refused("a frame before start", fresh.frame, 0)
		or refused("an OwnerState before start", fresh.receive, buffer.create(64))
		or refused("an eye before start", fresh.eye)
		or refused("a drawn state before start", fresh.state)
		or refused("a correction callback that isn't a function", fresh.onCorrected, "callback")
	if early then
		return false, early
	end

	-- A working rig's own settings, each broken in a fresh Predict
	local rig: any = Harness.new()
	local settings: any = rig.settings
	local function send(_: any) end
	local function acknowledged(): (number, number)
		return 0, 0
	end

	local function withSettings(change: (copy: any) -> ()): any
		local copy: any = table.clone(settings)
		copy.ticks = table.clone(settings.ticks)
		change(copy)

		return copy
	end

	local broken: { { any } } = {
		{ "send that isn't a function", settings, rig.world, "send", acknowledged },
		{ "acknowledged that isn't a function", settings, rig.world, send, nil },
		{ "settings that aren't a table", nil, rig.world, send, acknowledged },
		{
			"a sample that isn't a function",
			withSettings(function (copy: any)
				copy.sample = nil
			end),
			rig.world,
			send,
			acknowledged,
		},
		{
			"a look that isn't a function",
			withSettings(function (copy: any)
				copy.look = nil
			end),
			rig.world,
			send,
			acknowledged,
		},
		{
			"a delay that isn't a function",
			withSettings(function (copy: any)
				copy.delay = 0.15
			end),
			rig.world,
			send,
			acknowledged,
		},
		{
			"a time debt of 0",
			withSettings(function (copy: any)
				copy.ticks.debt = 0
			end),
			rig.world,
			send,
			acknowledged,
		},
	}

	for _, row: { any } in broken do
		local predict: any = Environment.load(PREDICT)
		local wrong: string? = refused(row[1], predict.start, row[2], row[3], row[4], row[5])
		if wrong then
			return false, wrong
		end
	end

	-- The rig's own Predict has started, so a second start, and its other refusals
	local predict: any = rig.Predict
	local short: buffer = buffer.create(20)
	local late: string? = refused("a second start", predict.start, settings, rig.world, send, acknowledged)
		or refused("an eye before the first OwnerState", predict.eye)
		or refused("a frame of -1 s", predict.frame, -1)
		or refused("a frame of infinite seconds", predict.frame, math.huge)
		or refused("a frame of NaN seconds", predict.frame, 0 / 0)
		or refused("an OwnerState that isn't a buffer", predict.receive, "state")
		or refused("an OwnerState too short to be one", predict.receive, short)
	if late then
		return false, late
	end

	return true, nil
end
