--[[
    The client parallel probes' cases' mount: the dev client's Config and
    the probes' Lines, Work and Bend in a fresh fake game beside the dev
    game's server side, each run in place as the dev client's folder holds it
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../DevServer/Harness")
local Kit = require("../Exploits/Kit")

local CONFIG: string = "dev/Client/Config.luau"
local LINES: string = "dev/Client/Parallel/Lines.luau"
local WORK: string = "dev/Client/Parallel/Work.luau"
local BEND: string = "dev/Client/Parallel/Bend.luau"

export type Mounted = {
	loaded: Harness.Loaded, -- The fake game, its require and its server side
	config: { [string]: any }, -- What the dev client's Config gives
	Lines: any,
	Work: any,
	Bend: any,
}

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

-- The dev client's folder with its Config, and its Parallel folder with the probes' modules, each required once
return function (): Mounted
	local loaded: Harness.Loaded = Harness.load()
	local replicated: any = loaded.game:GetService("ReplicatedStorage")

	local client: any = create("Folder", "Client", replicated)
	local parallel: any = create("Folder", "Parallel", client)
	local config: any = create("ModuleScript", "Config", client)
	local lines: any = create("ModuleScript", "Lines", parallel)
	local work: any = create("ModuleScript", "Work", parallel)
	local bend: any = create("ModuleScript", "Bend", parallel)

	local files: { [any]: string } = { [config] = CONFIG, [lines] = LINES, [work] = WORK, [bend] = BEND }
	local load: (target: any) -> any = Kit.loader(loaded.game, files, {}, loaded.require)

	return {
		loaded = loaded,
		config = load(config),
		Lines = load(lines),
		Work = load(work),
		Bend = load(bend),
	}
end
