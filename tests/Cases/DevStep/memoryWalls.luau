--[[
    The memory run's scenario builds its 20 walls among the city block's
    occluders, runs the memory run only once anti-ESP's query is open before
    them and blocked after, and takes them down whatever the run did
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local SCENARIO: string = "dev/Server/Scenarios/BenchStepMemory.luau"
local EYE: number = 4.17 -- Studs above the floor a standing body's eye sits, as the dev place's shared table has it
local FOLDER: string = "BenchStepMemory"
local LINE: string = "Bots Rooms150/before seed 1: drove and cleaned up" -- What the stand-in memory run gives

-- Where the query is asked from and along, worked by hand: the first room's center at the eye, 30 studs to the next
local ORIGIN: vector = vector.create(-4120, 1010 + EYE, -120)
local DIRECTION: vector = vector.create(30, 0, 0)

-- What the stand-in query answers: the walls as the engine meets them, nothing at all, or something everywhere
type Mode = "parts" | "open" | "solid"

-- Whether the segment from an origin along a direction meets a part's box, its Size about its CFrame's position
local function crosses(part: any, origin: vector, direction: vector): boolean
	local center: any = part.CFrame.Position
	local enter: number, leave: number = 0, 1

	for _, axis: string in { "X", "Y", "Z" } do
		local at: number = (origin :: any)[string.lower(axis)] - center[axis]
		local step: number = (direction :: any)[string.lower(axis)]
		local half: number = part.Size[axis] / 2

		if step == 0 then
			if math.abs(at) > half then
				return false
			end
		else
			local near: number, far: number = (-half - at) / step, (half - at) / step
			enter = math.max(enter, math.min(near, far))
			leave = math.min(leave, math.max(near, far))
		end
	end

	return enter <= leave
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local packages: any = dataModel:GetService("ReplicatedStorage").Packages
	local Cells: any = loaded.require(server.Bots.Cells)
	local rooms: any = loaded.require(server.Bots.Config).scenarios.Rooms150.groups[1]

	local testContent: any = roblox.Instance.new("Folder")
	testContent.Name = "TestContent"
	testContent.Parent = dataModel:GetService("Workspace")

	local cityBlock: any = roblox.Instance.new("Folder")
	cityBlock.Name = "CityBlock"
	cityBlock.Parent = testContent

	local occluders: any = roblox.Instance.new("Folder")
	occluders.Name = "Occluders"
	occluders.Parent = cityBlock

	local include: { any } = { occluders }
	local mode: Mode = "parts"
	local throwing: boolean = false
	local built: { { any } } = {} -- Each include list a query was built from
	local asked: { string } = {} -- Each query's origin and direction
	local runs: { string } = {} -- Each memory run's kind, and what stood among the occluders as it ran
	local standing: { any } = {}
	local parts: { any } = {} -- Each part in the first thing that stood there, read while it stood, since it goes after

	local engine: any = {
		occlusion = function (list: { any }): any
			table.insert(built, list)

			return function (origin: vector, direction: vector): boolean
				table.insert(asked, `{origin} {direction}`)
				if mode == "open" then
					return false
				elseif mode == "solid" then
					return true
				end

				for _, part: any in occluders:GetDescendants() do
					if part:IsA("BasePart") and crosses(part, origin, direction) then
						return true
					end
				end

				return false
			end
		end,
	}

	local benchStep: any = function (kind: string?): (boolean, string | nil)
		table.insert(runs, tostring(kind))
		standing = {}
		parts = {}
		for _, child: any in occluders:GetChildren() do
			table.insert(standing, { name = child.Name, folder = child:IsA("Folder") })
		end

		for _, part: any in (occluders:GetChildren()[1] or occluders):GetChildren() do
			local shaped: boolean = part:IsA("Part")
				and part.Shape == roblox.Enum.PartType.Block
				and part.Anchored == true
				and part.CanCollide == false
				and part.CanQuery == true
				and part.CanTouch == false

			table.insert(parts, { name = part.Name, shaped = shaped, at = part.CFrame.Position, size = part.Size })
		end

		if throwing then
			error("a stand-in throw", 0)
		end

		return true, LINE
	end

	local stand: any = {
		get = function (): (any, any, any)
			return {}, { step = { eyeStanding = EYE } }, { antiEsp = { include = include } }
		end,
	}

	local results: { [any]: any } = {
		[server.Scenarios.BenchStep] = benchStep,
		[server.Game] = stand,
		[packages.Tread.Step.Engine] = engine,
	}

	local load: (target: any) -> any =
		Kit.loader(dataModel, { [server.Scenarios.BenchStepMemory] = SCENARIO }, results, loaded.require)
	local BenchStepMemory: any = load(server.Scenarios.BenchStepMemory)

	-- 1) The walls stand in one folder among the occluders while the memory run runs, each a Block part only queries
	-- meet, where the rooms' walls are, and go once it ends
	local passed: boolean, line: string? = BenchStepMemory()
	local folder: any = standing[1]
	local expected: string = `{ORIGIN} {DIRECTION}`

	if not passed or line ~= LINE then
		return false, `The memory run among its walls gave {passed}: {line}`
	elseif table.concat(runs, ",") ~= "memory" then
		return false, `The scenario ran {table.concat(runs, ",")}, not the memory run once`
	elseif #standing ~= 1 or folder.name ~= FOLDER or not folder.folder then
		return false, `{#standing} things stood among the occluders as the run ran, not the {FOLDER} folder`
	elseif #built ~= 1 or built[1] ~= include then
		return false, `The query was built {#built} times, not once from the include list the server started with`
	elseif table.concat(asked, ",") ~= `{expected},{expected}` then
		return false, `The query was asked {table.concat(asked, ",")}, not twice {expected}`
	elseif #occluders:GetChildren() > 0 then
		return false, "The walls were left standing after the run"
	end

	local walls: { any } = Cells.walls(rooms.spawn, rooms.count)
	if #parts ~= #walls or #walls ~= 20 then
		return false, `{#parts} walls stood, not the rooms' {#walls}`
	end

	-- Matched by place, since the folder's children need keep no order
	local unmatched: { any } = table.clone(walls)
	for _, part: any in parts do
		if not part.shaped then
			return false, `The wall {part.name} is not an anchored Block part only queries meet`
		end

		local found: number? = nil
		for index: number, wall: any in unmatched do
			if (part.at - wall.center).Magnitude < 1e-3 and (part.size - wall.size).Magnitude < 1e-3 then
				found = index
			end
		end

		if found == nil then
			return false, `A wall stood {part.size} at {part.at}, where the rooms have none`
		end

		table.remove(unmatched, found)
	end

	-- 2) Walls the query passes through: no run, the failure named, the walls gone
	mode = "open"
	table.clear(runs)
	passed, line = BenchStepMemory()
	if
		passed
		or not string.find(line or "", "its walls left anti-ESP's query between its first two rooms open", 1, true)
	then
		return false, `With walls the query passes through, the scenario gave {passed}: {line}`
	elseif #runs > 0 or #occluders:GetChildren() > 0 then
		return false, "With walls the query passes through, the memory run ran or the walls stayed"
	end

	-- 3) Something blocking the query before any wall stands: asked once, so no wall built to ask again, no run, and
	-- the failure named
	mode = "solid"
	local askedBefore: number = #asked
	passed, line = BenchStepMemory()
	if passed or not string.find(line or "", "was blocked before any wall stood", 1, true) then
		return false, `With the query blocked before the walls, the scenario gave {passed}: {line}`
	elseif #runs > 0 or #asked ~= askedBefore + 1 or #occluders:GetChildren() > 0 then
		return false, "With the query blocked before the walls, it built them or ran"
	end

	-- 4) A memory run that throws: the run fails with its throw, and the walls go
	mode = "parts"
	throwing = true
	passed, line = BenchStepMemory()
	throwing = false
	if passed or not string.find(line or "", "Step benchmark verdict memory run threw: a stand-in throw", 1, true) then
		return false, `With the memory run throwing, the scenario gave {passed}: {line}`
	elseif #runs ~= 1 or #occluders:GetChildren() > 0 then
		return false, "With the memory run throwing, it ran otherwise than once or left its walls"
	end

	-- 5) A place with no occluder folder: nothing built, no run, the failure named
	occluders.Parent = nil
	passed, line = BenchStepMemory()
	if passed or not string.find(line or "", "Occluders is missing", 1, true) then
		return false, `With no occluder folder, the scenario gave {passed}: {line}`
	elseif #runs ~= 1 or #built ~= 4 then
		return false, "With no occluder folder, the scenario built a query or ran"
	end

	return true, nil
end
