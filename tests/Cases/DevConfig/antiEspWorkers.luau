--[[
    The dev server's settings start anti-ESP with no workers when
    Workspace's TreadAntiEspWorkers is absent or 0, with that many above 0,
    and refuse anything but a whole number from 0
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local CONFIG: string = "dev/Server/Config/Tread.luau"
local ATTRIBUTE: string = "TreadAntiEspWorkers"
local WORKERS: number = 3

-- The folders the settings take from Workspace, each a path below it
local OCCLUDERS: { { string } } = {
	{ "TestContent", "CityBlock", "Occluders" },
	{ "TestContent", "Monuments", "Occluders" },
}

local REFUSED: { any } = { 2.5, -1, "three" } -- Values the attribute may not take

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

	-- 1) Absent or 0, anti-ESP has no workers key, and the two settings are the same
	local absent: { [string]: any } = place.load(CONFIG)
	workspace:SetAttribute(ATTRIBUTE, 0)
	local none: { [string]: any } = place.load(CONFIG)

	if absent.antiEsp.workers ~= nil or Config.hash(none) ~= Config.hash(absent) then
		return false, `With {ATTRIBUTE} absent or 0, antiEsp holds workers, or the two settings differ`
	end

	-- 2) Above 0, that many workers, nothing else changed
	workspace:SetAttribute(ATTRIBUTE, WORKERS)
	local some: { [string]: any } = place.load(CONFIG)

	local antiEsp: { [string]: any } = table.clone(some.antiEsp)
	antiEsp.workers = nil
	local restored: { [string]: any } = table.clone(some)
	restored.antiEsp = antiEsp

	if some.antiEsp.workers ~= WORKERS then
		return false, `With {ATTRIBUTE} {WORKERS}, antiEsp.workers is {some.antiEsp.workers}`
	elseif Config.hash(restored) ~= Config.hash(absent) then
		return false, `With {ATTRIBUTE} {WORKERS}, a setting besides antiEsp.workers changed`
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
