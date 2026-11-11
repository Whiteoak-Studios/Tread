--[[
    How much Parallel Luau work the running server runs at once: the loop
    timed serially, then each worker count's batches, a line a count and a
    closing summary, with no bots loading the server
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Pool = require(ServerScriptService.Server.Parallel.Pool)
local Summary = require(ServerScriptService.Server.Parallel.Summary)

local WORKERS: { number } = require(ServerScriptService.Server.Config.Parallel).workers
local REPEATS: number = require(ServerScriptService.Server.Config.Parallel).repeats
local SEPARATOR: string = "; " -- Between the problems

return function (): (boolean, string | nil)
	local passes: number, serial: { number } = Pool.serial()
	local counts: { Summary.Measured } = {}
	local problems: { string } = {}

	for _, workers: number in WORKERS do
		local batches: { Summary.Batch }, stopped: string? = Pool.run(workers, passes)
		local measured: Summary.Measured = Summary.measure(workers, REPEATS, batches)
		table.insert(counts, measured)
		print(Summary.line(measured))

		if stopped then
			table.insert(problems, `{workers} workers stopped short: {stopped}`)
		end

		-- A start before the send can only mean the workers' os.clock() is not the main thread's
		if measured.early > 0 then
			local early: string = `{workers} workers: {measured.early} batches had a worker start before the send`
			table.insert(problems, `{early}, so the workers' clock is not the main thread's`)
		end
	end

	local summary: string = Summary.close(serial, passes, counts)
	print(summary)

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, summary
end
