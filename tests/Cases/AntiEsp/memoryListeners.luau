--[[
    Verdict memory's switch owns its listeners: no include instance holds
    one while memory is off, each holds one of each of its three signals
    while it is on, however often it is turned on, and none once it is off
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local SIGNALS: { string } = { "DescendantAdded", "DescendantRemoving", "AncestryChanged" }
local NONE: number = 0
local ONE: number = 1
local ON: boolean = true -- Verdict memory's switch
local OFF: boolean = false

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(function (_: any, server: any)
		-- A second listed instance beside the example's folder, so each one is shown to hold its own
		local more: any = roblox.Instance.new("Folder")
		more.Name = "MoreOccluders"
		table.insert(server.antiEsp.include, more)
	end)

	local AntiEsp: any = Harness.AntiEsp
	local include: { any } = harness.server.antiEsp.include

	-- The first signal of an include instance that holds other than count connections, nil when none does
	local function differs(count: number): string?
		for _, instance: any in include do
			for _, name: string in SIGNALS do
				local connected: number = instance[name]:Connected()
				if connected ~= count then
					return `{instance.Name}'s {name} held {connected} connections, not {count}`
				end
			end
		end

		return nil
	end

	-- Each switch in turn, and the connections each signal holds after it
	local steps: { { name: string, on: boolean?, count: number } } = {
		{ name = "before memory was ever on", on = nil, count = NONE },
		{ name = "with memory on", on = ON, count = ONE },
		{ name = "with memory turned on twice in a row", on = ON, count = ONE },
		{ name = "with memory off", on = OFF, count = NONE },
		{ name = "with memory turned off twice in a row", on = OFF, count = NONE },
		{ name = "with memory on again", on = ON, count = ONE },
	}

	for _, step in steps do
		if step.on ~= nil then
			AntiEsp.useMemory(step.on)
		end

		local differed: string? = differs(step.count)
		if differed then
			return false, `{step.name}, {differed}`
		end
	end

	return true, nil
end
