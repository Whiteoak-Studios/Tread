--[[
    The dev server's settings start the relay with no workers when
    Workspace's TreadRelayWorkers is absent or 0, with that many and a 1 s
    timeout above 0, and refuse anything but a whole number from 0
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local CONFIG: string = "dev/Server/Config/Tread.luau"
local ATTRIBUTE: string = "TreadRelayWorkers"
local WORKERS: number = 4
local TIMEOUT: number = 1 -- Seconds, the dev place's round timeout with workers
local RELAY_BUDGET: number = 0.005 -- Seconds, the dev place's relay budget

-- The folders the settings take from Workspace, each a path below it
local OCCLUDERS: { { string } } = {
	{ "TestContent", "CityBlock", "Occluders" },
	{ "TestContent", "Monuments", "Occluders" },
}

local REFUSED: { any } = { 2.5, -1, "four" } -- Values the attribute may not take

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local workspace: any = place.game:GetService("Workspace")
	local Config: any = place.tread("Config")

	for _, path: { string } in OCCLUDERS do
		local parent: any = workspace
		for _, name: string in path do
			local folder: any = parent:FindFirstChild(name)
			if not folder then
				folder = roblox.Instance.new("Folder")
				folder.Name = name
				folder.Parent = parent
			end

			parent = folder
		end
	end

	-- 1) Absent or 0, the relay table holds records as changes, the past and the budget alone, as before workers
	local absent: { [string]: any } = place.load(CONFIG)
	workspace:SetAttribute(ATTRIBUTE, 0)
	local none: { [string]: any } = place.load(CONFIG)
	local alone: { [string]: any } = { changes = true, budget = RELAY_BUDGET, past = true }

	if Config.hash(absent.relay) ~= Config.hash(alone) or Config.hash(none) ~= Config.hash(absent) then
		return false, `With {ATTRIBUTE} absent or 0, relay holds more than changes, past and budget, or the two differ`
	end

	-- 2) Above 0, that many workers and the timeout they need, nothing else changed
	workspace:SetAttribute(ATTRIBUTE, WORKERS)
	local some: { [string]: any } = place.load(CONFIG)
	local expected: { [string]: any } = {
		changes = true,
		budget = RELAY_BUDGET,
		workers = WORKERS,
		timeout = TIMEOUT,
		past = true,
	}

	local restored: { [string]: any } = table.clone(some)
	restored.relay = absent.relay

	if Config.hash(some.relay) ~= Config.hash(expected) then
		return false, `With {ATTRIBUTE} {WORKERS}, relay is not changes, past, {WORKERS} workers, a {TIMEOUT} s timeout`
	elseif Config.hash(restored) ~= Config.hash(absent) then
		return false, `With {ATTRIBUTE} {WORKERS}, a setting besides relay changed`
	end

	-- 3) Anything but a whole number from 0 is refused, naming the attribute
	for _, value: any in REFUSED do
		workspace:SetAttribute(ATTRIBUTE, value)

		local loaded: boolean, message: any = pcall(place.load, CONFIG)
		if loaded or not string.find(tostring(message), ATTRIBUTE, 1, true) then
			return false, `{ATTRIBUTE} {value} was not refused naming the attribute: {message}`
		end
	end

	return true, nil
end
