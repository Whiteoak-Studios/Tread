--[[
    The dev game's shared table is the approved example's but for its engine
    casts, head slide, crouch slide, 2.5-stud mantle reach, Stand waist and
    Stand body radius, and a copy with those set alike hashes alike
--]]

--!strict
local Harness = require("../../Fixtures/DevShared/Harness")

local MANTLE_REACH: number = 2.5 -- Studs past the hull's front, the dev place's
local STAND_WAIST: number = 2.4 -- Studs, the DevRig's Waist joint above its lowest point
local STAND_BODY: number = 1.7 -- Studs, the smallest tenth that holds every Stand zone at any pitch and lean

-- Every key either table holds, sorted
local function keys(a: { [string]: any }, b: { [string]: any }): { string }
	local names: { string } = {}

	for name: string in a do
		table.insert(names, name)
	end

	for name: string in b do
		if a[name] == nil then
			table.insert(names, name)
		end
	end

	table.sort(names)

	return names
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local Config: any = loaded.Config
	local shared: { [string]: any } = loaded.shared
	local example: { [string]: any } = loaded.Example.shared()

	-- The one part that differs by design: an include list where the fixture passes four functions
	local collision: { [string]: any } = shared.collision
	local include: { any }? = collision.include
	if not include or #include ~= 2 or include[1] ~= loaded.content or include[2] ~= loaded.terrain then
		return false, "collision.include is not Workspace.TestContent and Workspace.Terrain"
	end

	for name: string in collision do
		if name ~= "include" then
			return false, `collision gives {name} beside its include list`
		end
	end

	-- The hash names each instance of the include list, which the fixture's functions don't give
	if Config.hash(shared) == Config.hash(example) then
		return false, "The two hashed alike with different collision tables, so the hash read neither"
	end

	local copy: { [string]: any } = table.clone(shared)
	copy.collision = example.collision

	-- The other parts that differ by design: the dev place's own head slide, where Frontier Zero has set none, its
	-- crouch slide, which Frontier Zero has asked for none of, its longer mantle reach, and its Stand waist and body,
	-- fitted to the DevRig, where Frontier Zero sizes its own shapes with its Ballistics
	local stand: { [string]: any } = shared.hitShapes.Stand
	if shared.step.slide == nil or example.step.slide ~= nil then
		return false, "The dev table gives no crouch slide, or the approved example's gives one"
	elseif shared.step.mantleReach ~= MANTLE_REACH then
		return false, `The dev table's mantle reach is {shared.step.mantleReach} studs, not {MANTLE_REACH}`
	elseif stand.waist ~= STAND_WAIST or stand.body.radius ~= STAND_BODY then
		return false, `The dev table's Stand waist is {stand.waist} and its body {stand.body.radius} studs`
	end

	local step: { [string]: any } = table.clone(shared.step)
	step.headSlide = example.step.headSlide
	step.mantleReach = example.step.mantleReach
	step.slide = nil
	copy.step = step

	local body: { [string]: any } = table.clone(stand.body)
	body.radius = example.hitShapes.Stand.body.radius

	local standCopy: { [string]: any } = table.clone(stand)
	standCopy.waist = example.hitShapes.Stand.waist
	standCopy.body = body

	local hitShapes: { [string]: any } = table.clone(shared.hitShapes)
	hitShapes.Stand = standCopy
	copy.hitShapes = hitShapes

	if Config.hash(copy) == Config.hash(example) then
		return true, nil
	end

	-- Each top-level key that hashes differently, for the report
	local differ: { string } = {}
	for _, name: string in keys(copy, example) do
		if Config.hash({ [name] = copy[name] }) ~= Config.hash({ [name] = example[name] }) then
			table.insert(differ, name)
		end
	end

	return false, `The dev table differs from the approved example's in {table.concat(differ, ", ")}`
end
