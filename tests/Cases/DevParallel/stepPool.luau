--[[
    The pool clones the template it is given, and the parallel worker when
    given none, each clone named, numbered and in the pool's folder while
    the body runs, and every one taken away after it
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")

local MARK: string = "Template" -- An attribute each template carries, which its clones copy
local GIVEN: string = "the stand-in"
local DEFAULT: string = "the worker"
local HOME: string = "ParallelProbe" -- The pool's folder under ServerScriptService
local WORKERS: number = 2

-- How one clone stood while the body ran
type Seen = {
	actor: any,
	class: string,
	name: string,
	worker: unknown,
	mark: unknown,
	home: string?,
	service: string?,
}

--[[
    Runs the pool with that many workers and the template, or none, giving
    each clone as the body saw it, or why the pool stopped short
--]]

local function pooled(Pool: any, Work: any, workers: number, template: any?): ({ Seen }, string?)
	local seen: { Seen } = {}
	local stopped: string? = Pool.with(workers, function (actors: { any }): string?
		for _, actor: any in actors do
			local parent: any = actor.Parent
			table.insert(seen, {
				actor = actor,
				class = actor.ClassName,
				name = actor.Name,
				worker = actor:GetAttribute(Work.WORKER),
				mark = actor:GetAttribute(MARK),
				home = parent and parent.Name,
				service = parent and parent.Parent and parent.Parent.ClassName,
			})
		end

		return nil
	end, template)

	return seen, stopped
end

-- Why the clones seen are not that many of the template carrying the mark and the class, or nil when they are
local function wrong(seen: { Seen }, workers: number, mark: string, class: string): string?
	if #seen ~= workers then
		return `the body saw {#seen} clones, not {workers}`
	end

	for index: number, clone: Seen in seen do
		local named: string =
			`clone {index}, {clone.class} {clone.name} with worker {clone.worker} and mark {clone.mark}`
		if clone.class ~= class or clone.name ~= `Worker{index}` or clone.worker ~= index or clone.mark ~= mark then
			return `{named}, is no {class} Worker{index} of {mark}`
		elseif clone.home ~= HOME or clone.service ~= "ServerScriptService" then
			return `{named} sat in {clone.home} under {clone.service}`
		elseif clone.actor.Parent ~= nil then
			return `{named} was still parented after the pool`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local Pool: any = loaded.require(server.Parallel.Pool)
	local Work: any = loaded.require(server.Parallel.Work)

	-- Each template marked bound, so its clones copy the mark and the pool's wait for their topics passes at once
	local standIn: any = roblox.Instance.new("Actor")
	standIn.Name = "StandIn"
	standIn:SetAttribute(Work.BOUND, true)
	standIn:SetAttribute(MARK, GIVEN)

	local worker: any = server.Parallel.Worker
	worker:SetAttribute(Work.BOUND, true)
	worker:SetAttribute(MARK, DEFAULT)

	-- 1) Given a template, the clones are its own
	local seen: { Seen }, stopped: string? = pooled(Pool, Work, WORKERS, standIn)
	local problem: string? = stopped or wrong(seen, WORKERS, GIVEN, "Actor")
	if problem then
		return false, `With a template given, {problem}`
	end

	-- 2) Given none, the clones are the parallel worker's, which the harness mounts as a Folder
	seen, stopped = pooled(Pool, Work, 1, nil)
	problem = stopped or wrong(seen, 1, DEFAULT, worker.ClassName)
	if problem then
		return false, `With no template, {problem}`
	end

	-- 3) Neither template moved or took a worker's number
	local numbered: boolean = standIn:GetAttribute(Work.WORKER) ~= nil or worker:GetAttribute(Work.WORKER) ~= nil
	if standIn.Parent ~= nil or numbered then
		return false, "A template was moved or numbered as a worker"
	end

	return true, nil
end
