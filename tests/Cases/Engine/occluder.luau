--[[
    Engine.occluder refuses what occlusion refuses, naming antiEsp.include,
    and casts as occlusion does, every part of the list met CanCollide off
    or on and no water, giving the instance the ray met, or nil for none
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local ENGINE: string = "src/Step/Engine.luau"
local CONSTANTS: string = "src/Constants.luau"
local STATE: string = "src/Step/State.luau"
local DATATYPE: string = "^%u" -- A name Lune's library holds a Roblox datatype, Enum or Instance under

-- One Raycast the stand-in Workspace took
type Cast = {
	origin: any,
	direction: any,
	params: any,
}

--[[
    Engine run over a stand-in Workspace whose Raycast keeps each call and
    answers with what the case sets, and a RaycastParams of plain tables,
    as Lune has neither
--]]

local function standIn(): (any, { Cast }, { result: any })
	local casts: { Cast } = {}
	local answer: { result: any } = { result = nil }

	local workspace: any = {
		Raycast = function (_: any, origin: any, direction: any, params: any): any
			table.insert(casts, { origin = origin, direction = direction, params = params })

			return answer.result
		end,
	}

	local modules: { [string]: any } = { Constants = Environment.load(CONSTANTS), State = Environment.load(STATE) }
	local scope: { [string]: any } = {
		game = {
			GetService = function (_: any, _: string): any
				return workspace
			end,
		},

		script = { Parent = { State = "State", Parent = { Constants = "Constants" } } },

		require = function (target: string): any
			return modules[target]
		end,
	}

	for name: string, value: any in roblox do
		if name:match(DATATYPE) then
			scope[name] = value
		end
	end

	scope.RaycastParams = {
		new = function (): { [string]: any }
			return {}
		end,
	}

	local chunk: () -> any = luau.load(fs.readFile(ENGINE), { debugName = ENGINE, environment = scope })

	return chunk(), casts, answer
end

return function (): (boolean, string | nil)
	local Engine: any, casts: { Cast }, answer: { result: any } = standIn()
	local folder: any = roblox.Instance.new("Folder")

	local rows: { { any } } = {
		{ "no include", "antiEsp.include must be a list of Instances", nil },
		{ "a string", "antiEsp.include must be a list of Instances", "Occluders" },
		{ "a list holding a number", "antiEsp.include[2] must be an Instance", { folder, 7 } },
	}

	for _, row: { any } in rows do
		local refused: boolean, why: string = Refuses(row[2], Engine.occluder, row[3])
		if not refused then
			return false, `Engine.occluder of {row[1]} went another way: {why}`
		end
	end

	local include: { any } = { folder }
	local occluder: (origin: vector, direction: vector) -> any = Engine.occluder(include)
	local occlusion: (origin: vector, direction: vector) -> boolean = Engine.occlusion(include)
	local origin: vector = vector.create(1, 2, 3)
	local direction: vector = vector.create(0, 0, -40)

	-- 1) A hit gives the instance it met, from a cast of the list with CanCollide not respected and no water
	local part: any = roblox.Instance.new("Part")
	answer.result = { Instance = part }

	local met: any = occluder(origin, direction)
	local cast: Cast = casts[1]
	local params: any = cast.params

	if met ~= part then
		return false, `A cast that met a part gave {met}`
	elseif
		params.FilterType ~= roblox.Enum.RaycastFilterType.Include or params.FilterDescendantsInstances ~= include
	then
		return false, "The cast's filter was not the include list's"
	elseif params.RespectCanCollide ~= false or params.IgnoreWater ~= true then
		return false, "The cast respected CanCollide or met water"
	elseif cast.origin ~= roblox.Vector3.new(1, 2, 3) or cast.direction ~= roblox.Vector3.new(0, 0, -40) then
		return false, `The cast went from {cast.origin} along {cast.direction}, not the ray's copies`
	elseif occlusion(origin, direction) ~= true then
		return false, "Engine.occlusion said the same hit was open"
	end

	-- 2) A miss gives nil, and occlusion's answer for it is open
	answer.result = nil
	local missed: any = occluder(origin, direction)
	if missed ~= nil or occlusion(origin, direction) ~= false then
		return false, `A cast that met nothing gave {missed}`
	end

	-- Each cast once a call, occlusion's over a filter of its own with the same settings
	local other: any = casts[2].params
	if #casts ~= 4 or other == params or other.RespectCanCollide ~= false or other.IgnoreWater ~= true then
		return false, `The four calls made {#casts} casts, or occlusion's filter was occluder's or set otherwise`
	end

	return true, nil
end
