--[[
    Under the dev place's own shared table and server settings, a shot whose
    client reports the 0.10 s floor as its delay is rewound by those 0.10 s,
    the clamp holding it there rather than raising it
--]]

--!strict
local Environment = require("../../Environment")
local Harness = require("../../Fixtures/DevClient/Harness")
local Shared = require("../../Fixtures/DevShared/Harness")

local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local HISTORY: string = "src/Server/History.luau"
local STATE: string = "src/Step/State.luau"
local SERVER: string = "dev/Server/Config/Tread.luau"
local SLOT: number = 0
local TICK: number = 100 -- The shot's command's tick
local DELAY: number = 0.10 -- Seconds of interpolation delay the shooter's client reports, the dev floor
local STILL: number = 0 -- No round trip, jitter or queue wait, so the delay is the whole lag
local FAR: number = 0 -- A claim far outside any band, so the rewind gives the expected time
local NEAR: number = 1e-9

-- The folders the server settings take from Workspace, each a path below it
local OCCLUDERS: { { string } } = {
	{ "TestContent", "CityBlock", "Occluders" },
	{ "TestContent", "Monuments", "Occluders" },
}

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local workspace: any = place.game:GetService("Workspace")

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

	local shared: any = Shared.load().shared
	local server: any = place.load(SERVER)
	local State: any = Environment.load(STATE)
	local History: any = Environment.load(HISTORY)
	History.start(shared, server)

	-- The slot written at every tick of the history's length before the command's
	local relay: number = shared.rates.relay
	local state = State.new()
	for at: number = TICK - server.history.seconds * relay, TICK - 1 do
		History.write(SLOT, at, state, 0)
	end

	local now: number = TICK * relay / shared.rates.simulation
	local time: number = History.rewindFor(TICK, STILL, STILL, STILL, DELAY, FAR)
	local rewound: number = (now - time) / relay
	local lag: number = History.lag(STILL, STILL, DELAY)

	if math.abs(lag - DELAY) > NEAR or math.abs(rewound - DELAY) > NEAR then
		return false, `A shot reporting a {DELAY} s delay lagged {lag} s and was rewound by {rewound} s, not {DELAY}`
	end

	return true, nil
end
