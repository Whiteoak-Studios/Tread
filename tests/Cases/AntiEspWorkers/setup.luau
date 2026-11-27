--[[
    No worker is ready, nor sent its setup, before the first slice's
    collect asks the pool, which sends the setup with the include list as it
    stood at start, though the game emptied its own table since; then packs
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	local include: { any } = harness.server.antiEsp.include
	local atStart: { any } = table.clone(include)

	if #atStart == 0 then
		return false, "The example's include list is empty, so nothing shows it crossing"
	elseif pool.setup ~= nil or pool:isReady(1) then
		return false, "A worker was set up or ready before any slice asked the pool"
	end

	-- The game edits its own table after start
	table.clear(include)

	local _, viewer: any = harness:player("Viewer", vector.zero)
	AntiEsp.isHidden(viewer, harness:body("Player", vector.create(0, 0, -20)))
	harness:slice(0)

	local sent: { any }? = pool.setup and pool.setup.include
	if sent == nil then
		return false, "The first slice's collect sent the workers no setup"
	elseif #sent ~= #atStart then
		return false, `The setup carried {#sent} instances to include, not the {#atStart} given at start`
	end

	for index: number, instance: any in atStart do
		if sent[index] ~= instance then
			return false, `The setup's include list differed from the one given at start at {index}`
		end
	end

	if #pool.sends ~= 1 or #harness.rays ~= 0 then
		return false, "Once set up, the first slice did not pack its test for a worker"
	end

	return true, nil
end
