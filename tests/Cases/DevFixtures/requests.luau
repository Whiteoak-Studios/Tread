--[[
    The fixture loot, swing and build are judged from the server's cleared
    eye: a claimed source away from it is refused as source, a point past
    the reach from the eye as reach though the claim lies within reach of
    it, and a piece over a character's hull as overlap
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local DevServer = require("../../Fixtures/DevServer/Harness")
local Rig = require("../../Fixtures/Server/Rig")

local SETTLE: number = 30 -- Ticks for both bodies to land and the eye to settle
local ROAMED: number = 50 -- Studs the roaming client claims to stand from its body
local LEASH: number = 4 -- Studs from the eye a claim may lie and still pass, inside the 5-stud leash
local LOOT_IN: number = 5 -- Studs ahead of the eye, inside the 7.5-stud loot reach
local LOOT_OUT: number = 10 -- Past it from the eye, though within it from a claim LEASH studs toward it
local SWING_IN: number = 6 -- Inside the 7-stud swing reach
local SWING_OUT: number = 8
local BUILD_IN: number = 12 -- Inside the 32-stud build reach, clear of every hull
local BUILD_OUT: number = 40
local PIECE: number = 1 -- Studs on a side of the piece built

-- One request: what it is, the refusal expected of it, nil for one accepted, and the call
type Check = {
	label: string,
	expected: string?,
	run: () -> (boolean, string?),
}

-- A request's verdict against what the case expects of it, nil when it matches
local function differs(label: string, accepted: boolean, reason: string?, expected: string?): string?
	if expected == nil and not accepted then
		return `{label} was refused as {reason}`
	elseif expected ~= nil and (accepted or reason ~= expected) then
		return `{label} gave {accepted} and {reason}, not a refusal as {expected}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local dev: DevServer.Loaded = DevServer.load()
	local Requests: any = dev.require(dev.game:GetService("ServerScriptService").Server.Fixtures.Requests)

	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local builder: any = server:create(rig.mock:addBot("Builder"), rig:at(-20, 0))
	local other: any = server:create(rig.mock:addBot("Other"), rig:at(-20, -6))

	rig:tick(SETTLE)

	local piece: any = roblox.Vector3.new(PIECE, PIECE, PIECE)
	local eye: any = builder:getState().eye

	if pcall(Requests.build, builder, eye, roblox.CFrame.new(eye), piece) then
		return false, "Requests.build ran before Requests.start"
	end

	Requests.start(server)
	if pcall(Requests.start, server) then
		return false, "Requests.start ran a second time"
	end

	local function ahead(studs: number): any
		return eye + roblox.Vector3.new(0, 0, -studs)
	end

	local roamed: any = eye + roblox.Vector3.new(ROAMED, 0, 0)
	local leashed: any = ahead(LEASH)
	local overHull: any = roblox.CFrame.new(other:getState().hullCenter)

	local checks: { Check } = {
		{
			label = "a loot from the roamed spot",
			expected = "source",
			run = function (): (boolean, string?)
				return Requests.loot(builder, roamed, ahead(LOOT_IN))
			end,
		},
		{
			label = "a swing from the roamed spot",
			expected = "source",
			run = function (): (boolean, string?)
				return Requests.swing(builder, roamed, ahead(SWING_IN))
			end,
		},
		{
			label = "a build from the roamed spot",
			expected = "source",
			run = function (): (boolean, string?)
				return Requests.build(builder, roamed, roblox.CFrame.new(ahead(BUILD_IN)), piece)
			end,
		},
		{
			label = "a loot in reach",
			expected = nil,
			run = function (): (boolean, string?)
				return Requests.loot(builder, eye, ahead(LOOT_IN))
			end,
		},
		{
			label = "a loot past reach from the eye",
			expected = "reach",
			run = function (): (boolean, string?)
				return Requests.loot(builder, leashed, ahead(LOOT_OUT))
			end,
		},
		{
			label = "a swing in reach",
			expected = nil,
			run = function (): (boolean, string?)
				return Requests.swing(builder, leashed, ahead(SWING_IN))
			end,
		},
		{
			label = "a swing past reach",
			expected = "reach",
			run = function (): (boolean, string?)
				return Requests.swing(builder, eye, ahead(SWING_OUT))
			end,
		},
		{
			label = "a build in reach",
			expected = nil,
			run = function (): (boolean, string?)
				return Requests.build(builder, eye, roblox.CFrame.new(ahead(BUILD_IN)), piece)
			end,
		},
		{
			label = "a build past reach",
			expected = "reach",
			run = function (): (boolean, string?)
				return Requests.build(builder, eye, roblox.CFrame.new(ahead(BUILD_OUT)), piece)
			end,
		},
		{
			label = "a build over a hull",
			expected = "overlap",
			run = function (): (boolean, string?)
				return Requests.build(builder, eye, overHull, piece)
			end,
		},
	}

	for _, check: Check in checks do
		local accepted: boolean, reason: string? = check.run()
		local problem: string? = differs(check.label, accepted, reason, check.expected)
		if problem then
			return false, problem
		end
	end

	return true, nil
end
