--[[
    Probe P10: the boxes settle's exact check is handed on each bot load,
    then the bounds query beside it on the main thread and on step worker
    clones, passing only when every load ran and the probe found no problem
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = require(ReplicatedStorage.Shared.Dev.Config)

local Bounds = require(ServerScriptService.Server.Parallel.Bounds)
local Config = require(ServerScriptService.Server.Bots.Config)
local Run = require(ServerScriptService.Server.Bots.Run)
local Settles = require(ServerScriptService.Server.Parallel.Settles)

local LOADS: { string } = require(ServerScriptService.Server.Config.Parallel).bounds.loads
local TIMING: Config.Timing = require(ServerScriptService.Server.Config.Parallel).bounds.timing
local CAP: number = require(ServerScriptService.Server.Config.Parallel).bounds.cap
local PARALLEL_BOXES: number = require(ServerScriptService.Server.Config.Parallel).bounds.parallelBoxes
local SEPARATOR: string = "; " -- Between the failed loads' lines and the problems

return function (): (boolean, string | nil)
	local recordings: { Bounds.Recording } = {}
	local failures: { string } = {}

	-- A load whose run failed still hands on what it recorded, so the rest of the probe runs
	for _, name: string in LOADS do
		local sampler: Settles.Sampler = Settles.new(name, CAP, Shared.step)
		local passed: boolean, line: string = Run.run(name, TIMING, Settles.probe(sampler))
		print(line)

		if not passed then
			table.insert(failures, line)
		end

		table.insert(recordings, Settles.recording(sampler))
	end

	local lines: { string }, problems: { string } = Bounds.run(recordings, PARALLEL_BOXES)
	for _, line: string in lines do
		print(line)
	end

	table.move(problems, 1, #problems, #failures + 1, failures)

	if #failures > 0 then
		return false, table.concat(failures, SEPARATOR)
	end

	return true, nil
end
