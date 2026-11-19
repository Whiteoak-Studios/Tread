--[[
    Builds occluders, a solid part and terrain far from the dev game's
    content, checks which of Engine.occlusion's rays through them block, and
    removes everything it made, its terrain put back as it was
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Engine = require(ReplicatedStorage.Packages.Tread.Step.Engine)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)

local ORIGIN: Vector3 = Vector3.new(4000, 600, 4000) -- Far from the dev game's content and its plaza
local SPACING: number = 40 -- Studs between the lanes, one ray down each
local REACH: number = 30 -- How far each ray goes, through its block halfway along it
local BLOCK: Vector3 = Vector3.new(8, 8, 2) -- Each part's size, thin along its ray
local TERRAIN: Vector3 = Vector3.new(12, 12, 12) -- Each terrain block's, whole voxels at its center
local VOXEL: number = 4 -- The voxel size ReadVoxels and WriteVoxels take
local HEARTBEAT_WAIT: number = 5 -- Seconds each wait for a Heartbeat may take before the scenario fails
local SEPARATOR: string = "; " -- Between the problems in one report

-- The lane each check's ray runs down
local OCCLUDER_LANE: number = 0
local CAMERA_LANE: number = 1
local SOLID_LANE: number = 2
local WATER_LANE: number = 3
local ROCK_LANE: number = 4

-- One ray's check: what its include list holds, its lane and whether it should be blocked
type Check = {
	name: string,
	include: { Instance },
	lane: number,
	blocked: boolean,
}

-- What a terrain block replaced, so it can be put back
type Saved = {
	region: Region3,
	materials: { { { Enum.Material } } },
	occupancies: { { { number } } },
}

-- Where a lane's ray starts, and the middle of its reach, where its block sits
local function start(lane: number): Vector3
	return ORIGIN + Vector3.new(lane * SPACING, 0, 0)
end

local function middle(lane: number): Vector3
	return start(lane) + Vector3.new(0, 0, REACH / 2)
end

-- A part across a lane's ray, anchored and queryable, colliding or not
local function block(name: string, lane: number, canCollide: boolean, parent: Instance): Part
	local made: Part = Instance.new("Part")
	made.Name = name
	made.Anchored = true
	made.CanCollide = canCollide
	made.CanQuery = true
	made.CanTouch = false
	made.Size = BLOCK
	made.CFrame = CFrame.new(middle(lane))
	made.Parent = parent

	return made
end

-- Fills a terrain block across a lane's ray with a material, keeping what its voxels held before
local function fill(lane: number, material: Enum.Material): Saved
	local terrain: Terrain = Workspace.Terrain
	local center: Vector3 = middle(lane)
	local region: Region3 = Region3.new(center - TERRAIN / 2, center + TERRAIN / 2):ExpandToGrid(VOXEL)
	local materials: { { { Enum.Material } } }, occupancies: { { { number } } } = terrain:ReadVoxels(region, VOXEL)

	terrain:FillBlock(CFrame.new(center), TERRAIN, material)

	return { region = region, materials = materials, occupancies = occupancies }
end

--[[
    Waits for the next Heartbeat, up to HEARTBEAT_WAIT seconds, and gives
    whether one came. A terrain ray meets a FillBlock or a WriteVoxels only
    from the next Heartbeat, so one cast sooner meets the terrain as it was
--]]

local function heartbeat(): boolean
	local came: boolean = false
	local connection: RBXScriptConnection = RunService.Heartbeat:Once(function ()
		came = true
	end)

	local deadline: number = os.clock() + HEARTBEAT_WAIT
	while not came and os.clock() < deadline do
		task.wait()
	end

	connection:Disconnect() -- Already gone once it fired, and dropped here when it never did

	return came
end

--[[
    Whether a filled block's voxels hold again what they held before it was
    filled, read by index, since ReadVoxels' arrays also carry a Size field
--]]

local function restored(put: Saved): boolean
	local materials: { { { Enum.Material } } }, occupancies: { { { number } } } =
		Workspace.Terrain:ReadVoxels(put.region, VOXEL)

	for x: number = 1, #put.materials do
		for y: number = 1, #put.materials[x] do
			for z: number = 1, #put.materials[x][y] do
				if materials[x][y][z] ~= put.materials[x][y][z] or occupancies[x][y][z] ~= put.occupancies[x][y][z] then
					return false
				end
			end
		end
	end

	return true
end

return function (): (boolean, string | nil)
	local problems: { string } = {}
	local terrain: Terrain = Workspace.Terrain

	local root: Folder = Instance.new("Folder")
	root.Name = "Occlusion"

	-- The design's occluder folder, held under a Camera, which never replicates
	local holder: Camera = Instance.new("Camera")
	holder.Name = "OcclusionHolder"
	local held: Folder = Instance.new("Folder")
	held.Name = "Occluders"
	held.Parent = holder

	local occluders: Folder = Instance.new("Folder")
	occluders.Name = "Occluders"
	occluders.Parent = root

	local outside: Folder = Instance.new("Folder")
	outside.Name = "Outside"
	outside.Parent = root

	block("Occluder", OCCLUDER_LANE, false, occluders)
	block("HeldOccluder", CAMERA_LANE, false, held)
	block("Solid", SOLID_LANE, true, outside)

	root.Parent = Workspace
	holder.Parent = Workspace

	local saved: { Saved } = {}
	local ran: boolean, failure: any = pcall(function ()
		table.insert(saved, fill(WATER_LANE, Enum.Material.Water))
		table.insert(saved, fill(ROCK_LANE, Enum.Material.Rock))

		if not heartbeat() then
			table.insert(problems, `no Heartbeat within {HEARTBEAT_WAIT} s of the terrain fills, so no ray was cast`)

			return
		end

		-- The water lane holds water, so its open result below is the water's and never an empty lane's
		local withWater: RaycastParams = RaycastParams.new()
		withWater.FilterType = Enum.RaycastFilterType.Include
		withWater.FilterDescendantsInstances = { terrain }
		withWater.IgnoreWater = false

		local wet: RaycastResult? = Workspace:Raycast(start(WATER_LANE), Vector3.new(0, 0, REACH), withWater)
		if not wet or wet.Material ~= Enum.Material.Water then
			table.insert(problems, "a ray down the water lane, water counted, met no terrain water")
		end

		local checks: { Check } = {
			{
				name = "a CanCollide-off occluder in the include list",
				include = { occluders },
				lane = OCCLUDER_LANE,
				blocked = true,
			},
			{
				name = "a CanCollide-off occluder held under a Camera",
				include = { held },
				lane = CAMERA_LANE,
				blocked = true,
			},
			{
				name = "a CanCollide-on part outside the include list",
				include = { occluders, held, terrain },
				lane = SOLID_LANE,
				blocked = false,
			},
			{ name = "that part with its folder included", include = { outside }, lane = SOLID_LANE, blocked = true },
			{ name = "terrain water", include = { terrain }, lane = WATER_LANE, blocked = false },
			{ name = "solid terrain", include = { terrain }, lane = ROCK_LANE, blocked = true },
		}

		for _, check: Check in checks do
			local blocked: (origin: vector, direction: vector) -> boolean = Engine.occlusion(check.include)
			local origin: vector = Engine.toVector(start(check.lane))
			local found: boolean = blocked(origin, vector.create(0, 0, REACH))

			if found ~= check.blocked then
				local expected: string = check.blocked and "blocked" or "open"
				table.insert(problems, `a ray through {check.name} was not {expected}`)
			end
		end

		-- The step's own casts respect CanCollide, so the same occluder never stops a body or its eye
		local casts: State.Collision = Engine.collision({ occluders })
		local through: State.Hit? = casts.ray(Engine.toVector(start(OCCLUDER_LANE)), vector.create(0, 0, REACH))
		casts.destroy()

		if through ~= nil then
			table.insert(problems, "the step's ray met the CanCollide-off occluder")
		end
	end)

	if not ran then
		table.insert(problems, `the checks threw: {failure}`)
	end

	-- Everything it made goes, the terrain it filled put back as it was, whatever the checks did
	for _, put: Saved in saved do
		terrain:WriteVoxels(put.region, VOXEL, put.materials, put.occupancies)

		if not restored(put) then
			table.insert(problems, `the terrain at {put.region.CFrame.Position} was not put back as it was`)
		end
	end

	-- So the next scenario's rays never meet the terrain this one filled
	if not heartbeat() then
		table.insert(problems, `no Heartbeat within {HEARTBEAT_WAIT} s of the terrain being put back`)
	end

	root:Destroy()
	holder:Destroy()

	if Workspace:FindFirstChild("Occlusion") or Workspace:FindFirstChild("OcclusionHolder") then
		table.insert(problems, "a part or folder it made was left in Workspace")
	end

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, nil
end
