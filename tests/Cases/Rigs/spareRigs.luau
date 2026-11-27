--[[
    With pool.spare the frame's end builds the pool toward its spare rigs,
    perFrame.builds a frame or all at once with none, each outside the
    Workspace, and a checkout takes one with no build of its own, while a
    checkout from an empty pool still builds at once; with no pool.spare
    the frame's end builds none
--]]

--!strict
local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local SPARE: number = 3
local BUILDS: number = 2

return function (): (boolean, string | nil)
	-- Lune loads no animation, so Animate's stand-in plays nothing
	local Animate: { [string]: any } = {
		check = function (_: any) end,
		places = function (_: any, _: any): { any }
			return {}
		end,
		stop = function (_: any) end,
		release = function (_: any) end,
	}

	local Rigs: any = Environment.load(RIGS, { [ANIMATE] = Animate })
	local Rig = Environment.load(RIG)

	-- Every build the pools make, through the module's own table as the frame's end calls it
	local built: number = 0
	local build: (self: any) -> any = Rigs._build
	Rigs._build = function (self: any): any
		built += 1
		return build(self)
	end

	local function poolOf(spare: number?, builds: number?): any
		local settings: any = Rig.settings({})
		settings.pool = spare and { spare = spare }
		settings.perFrame = { builds = builds }

		return Rigs.new(settings, Rig.drawDistance, Rig.collision())
	end

	-- 1) Two a frame toward three, then none once the pool holds them, every one out of the Workspace
	local rigs: any = poolOf(SPARE, BUILDS)
	local counts: { number } = {}
	for _ = 1, 3 do
		rigs:frame()
		table.insert(counts, built)
	end

	if table.concat(counts, ",") ~= "2,3,3" then
		return false, `The frames' ends had built {table.concat(counts, ",")} rigs, not 2, then 3, then 3`
	end

	for _, entry: any in rigs._pool do
		if entry.rig.Parent ~= nil then
			return false, `A spare rig was built into {entry.rig.Parent:GetFullName()}`
		end
	end

	-- 2) Checkouts take the spare rigs with no build of their own, and one from the empty pool builds at once
	for slot: number = 1, SPARE do
		rigs:checkout(slot, {})
	end

	if built ~= SPARE then
		return false, `Checkouts from the spare rigs built {built - SPARE} rigs of their own`
	end

	rigs:checkout(SPARE + 1, {})
	if built ~= SPARE + 1 then
		return false, "A checkout from the empty pool built no rig at once"
	end

	-- The frame after refills it as before, two a frame
	rigs:frame()
	if built ~= SPARE + 1 + BUILDS then
		return false, `The frame's end after the checkouts built {built - SPARE - 1} rigs, not {BUILDS}`
	end

	rigs:destroy()

	-- 3) With no cap on builds the frame's end builds every spare rig at once, and with no spare rigs none
	built = 0
	local uncapped: any = poolOf(SPARE, nil)
	uncapped:frame()
	if built ~= SPARE then
		return false, `With no cap on builds, the frame's end built {built} rigs, not {SPARE}`
	end
	uncapped:destroy()

	built = 0
	local none: any = poolOf(nil, BUILDS)
	none:frame()
	if built ~= 0 then
		return false, `With no spare rigs, the frame's end built {built}`
	end
	none:destroy()

	return true, nil
end
