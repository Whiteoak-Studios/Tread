--[[
    What the local player sees of their own body: their world rig, and the
    spectated target's, hidden on their own screen until the game shows it,
    and their first-person copy, head out of view, arms and chest as asked
--]]

--!strict
local FirstPerson = {}
FirstPerson.__index = FirstPerson

local HIDDEN: number = 1 -- A LocalTransparencyModifier that hides a part on this screen alone
local SHOWN: number = 0

-- The regions of the copy a part falls in, as bits, so a piece welded across two takes both
local BODY: number = 1 -- Every part's, so hiding it hides the whole copy
local HEAD: number = 2
local CHEST: number = 4
local ARMS: number = 8

-- The logical joints whose moved part starts a region; every other joint's part is the body's alone
local REGIONS: { [string]: number } = {
	Neck = HEAD,
	Waist = CHEST,
	LeftShoulder = ARMS,
	LeftElbow = ARMS,
	LeftWrist = ARMS,
	RightShoulder = ARMS,
	RightElbow = ARMS,
	RightWrist = ARMS,
}

-- What a game shows or hides: the copy's arms, its chest, the whole copy, or the local player's world rig
export type Part = "arms" | "chest" | "copy" | "rig"

-- The first-person copy as the pool holds it: its model and its own joints by logical name
export type Copy = {
	rig: Model,
	joints: { [string]: AnimationConstraint },
}

type Shown = { [Part]: boolean }

type Fields = {
	_shown: Shown, -- The game's settings, kept from one body to the next
	_world: Model?, -- The local player's world rig, while it has one
	_watched: Model?, -- The spectated target's world rig, which takes the same setting, while there is one
	_copy: Copy?, -- Its first-person copy, nil when none could be dressed
	_regions: { [BasePart | Decal]: number }, -- Each of the copy's parts and decals by the regions it falls in
}

-- Sets every part and decal of a model, its attire and held item included, to one level
local function level(model: Model, value: number)
	for _, item: Instance in model:GetDescendants() do
		if item:IsA("BasePart") or item:IsA("Decal") then
			item.LocalTransparencyModifier = value
		end
	end
end

-- The two parts a weld holds together, a Weld, Motor6D or other joint, a WeldConstraint or a RigidConstraint
local function ends(item: Instance): (BasePart?, BasePart?)
	if item:IsA("JointInstance") then
		return item.Part0, item.Part1
	elseif item:IsA("WeldConstraint") then
		return item.Part0, item.Part1
	elseif item:IsA("RigidConstraint") then
		local attachment0: Attachment? = item.Attachment0
		local attachment1: Attachment? = item.Attachment1
		local part0: Instance? = attachment0 and attachment0.Parent
		local part1: Instance? = attachment1 and attachment1.Parent

		if part0 and part1 and part0:IsA("BasePart") and part1:IsA("BasePart") then
			return part0, part1
		end
	end

	return nil, nil
end

local function link(links: { [BasePart]: { BasePart } }, from: BasePart, to: BasePart)
	local linked: { BasePart }? = links[from]
	if linked then
		table.insert(linked, to)
	else
		links[from] = { to }
	end
end

--[[
    Spreads one region from the part its joint moves to every part welded
    to it, piece to piece, and never through another part a joint moves,
    so a hat on the head takes the head's region and the torso never does
--]]

local function spread(
	regions: { [BasePart | Decal]: number },
	links: { [BasePart]: { BasePart } },
	moved: { [BasePart]: number },
	from: BasePart,
	region: number
)
	regions[from] = bit32.bor(regions[from], region)

	local queue: { BasePart } = { from }
	local at: number = 1
	while at <= #queue do
		local linked: { BasePart }? = links[queue[at]]
		at += 1

		if linked then
			for _, part: BasePart in linked do
				if moved[part] == nil and bit32.band(regions[part], region) == 0 then
					regions[part] = bit32.bor(regions[part], region)
					table.insert(queue, part)
				end
			end
		end
	end
end

--[[
    Why a part and a shown flag can't be shown: the part none of the four,
    or shown no boolean, else nil
--]]

function FirstPerson.refuse(part: unknown, shown: unknown): string | nil
	if part ~= "arms" and part ~= "chest" and part ~= "copy" and part ~= "rig" then
		return `takes "arms", "chest", "copy" or "rig" as the part, not {part}`
	elseif type(shown) ~= "boolean" then
		return `takes shown as a boolean, not a {typeof(shown)}`
	end

	return nil
end

--[[
    The local player's view of their own rigs, with nothing to hide yet: the
    copy's arms, chest and whole self shown, and the world rig hidden once
    there is one
--]]

function FirstPerson.new(): Self
	return setmetatable({
		_shown = { arms = true, chest = true, copy = true, rig = false },
		_world = nil :: Model?,
		_watched = nil :: Model?,
		_copy = nil :: Copy?,
		_regions = {} :: { [BasePart | Decal]: number },
	}, FirstPerson)
end

--[[
    Takes a new body's rigs, the world rig and its copy, each hidden on
    this screen as the game's settings say, which stay from the last body

    @ copy | nil when the copy couldn't be dressed, which leaves the world rig alone
--]]

function FirstPerson.build(self: Self, world: Model, copy: Copy?)
	self._world = world
	self._copy = copy
	self:refresh()
end

--[[
    Hides again what the settings hide, once a dress or hold hook may have
    added or taken parts: every part of the world rig takes the rig's
    setting, and each of the copy's takes its regions' settings, its attire
    and held item read again from what they are welded to
--]]

function FirstPerson.refresh(self: Self)
	-- Whiteoak TODO: a part a game adds to the local player's rigs outside dress and hold shows until the next of
	-- those hooks; listen to each rig's DescendantAdded, if a game adds parts on its own
	local copy: Copy? = self._copy
	if copy then
		self:_read(copy)
	end

	self:_apply()
end

--[[
    Reads which region each part and decal of the copy falls in: a part a
    joint moves falls in its joint's, and a piece in that of every such part
    its welds reach, a decal in its part's, and the rest in the body's alone
--]]

function FirstPerson._read(self: Self, copy: Copy)
	local regions: { [BasePart | Decal]: number } = self._regions
	table.clear(regions)

	local items: { Instance } = copy.rig:GetDescendants()

	-- 1) Every part starts as the body's alone
	for _, item: Instance in items do
		if item:IsA("BasePart") then
			regions[item] = BODY
		end
	end

	-- 2) The welds between them, each way
	local links: { [BasePart]: { BasePart } } = {}
	for _, item: Instance in items do
		local part0: BasePart?, part1: BasePart? = ends(item)
		if part0 and part1 and regions[part0] and regions[part1] then
			link(links, part0, part1)
			link(links, part1, part0)
		end
	end

	-- 3) The parts the joints move, the root part among them, each with its joint's region or none
	local moved: { [BasePart]: number } = {}
	for logical: string, joint: AnimationConstraint in copy.joints do
		local holder: Instance? = (joint.Attachment0 :: Attachment).Parent
		if holder and holder:IsA("BasePart") and moved[holder] == nil then
			moved[holder] = 0
		end

		moved[(joint.Attachment1 :: Attachment).Parent :: BasePart] = REGIONS[logical] or 0
	end

	for part: BasePart, region: number in moved do
		if region ~= 0 then
			spread(regions, links, moved, part, region)
		end
	end

	-- 4) A decal or texture shows as the part it is on does
	for _, item: Instance in items do
		if item:IsA("Decal") then
			local on: Instance? = item.Parent
			if on and on:IsA("BasePart") then
				regions[item] = regions[on] or BODY
			else
				regions[item] = BODY
			end
		end
	end
end

-- Sets every part of the rigs as the settings say: each world rig's all alike, and the copy's by their regions
function FirstPerson._apply(self: Self)
	local shown: Shown = self._shown
	local rig: number = shown.rig and SHOWN or HIDDEN

	local world: Model? = self._world
	if world then
		level(world, rig)
	end

	local watched: Model? = self._watched
	if watched then
		level(watched, rig)
	end

	-- The copy's head always hides, since the eye sits inside it
	local hidden: number = HEAD
	if not shown.arms then
		hidden = bit32.bor(hidden, ARMS)
	end
	if not shown.chest then
		hidden = bit32.bor(hidden, CHEST)
	end
	if not shown.copy then
		hidden = bit32.bor(hidden, BODY)
	end

	for item: BasePart | Decal, region: number in self._regions do
		item.LocalTransparencyModifier = bit32.band(region, hidden) ~= 0 and HIDDEN or SHOWN
	end
end

--[[
    Shows or hides part of the local player's own body on this screen, a
    setting that holds from one body to the next
--]]

function FirstPerson.show(self: Self, part: Part, shown: boolean)
	if self._shown[part] == shown then
		return
	end

	self._shown[part] = shown
	self:_apply()
end

--[[
    Takes the spectated target's world rig, which takes the rig setting as
    the local player's own does, or nil for none. The one it replaces is
    shown again, as the pool and a body need it
--]]

function FirstPerson.watch(self: Self, world: Model?)
	local watched: Model? = self._watched
	if watched == world then
		return
	elseif watched then
		level(watched, SHOWN)
	end

	self._watched = world
	self:_apply()
end

--[[
    Gives the local player's rigs back as the pool and a body need them,
    every part and decal shown, before they are undressed or ragdolled. The
    game's settings stay for the next body
--]]

function FirstPerson.release(self: Self)
	local world: Model? = self._world
	if world then
		level(world, SHOWN)
	end

	local copy: Copy? = self._copy
	if copy then
		level(copy.rig, SHOWN)
	end

	self._world = nil
	self._copy = nil
	table.clear(self._regions)
end

export type FirstPerson = Self
type Self = typeof(setmetatable({} :: Fields, FirstPerson))

return FirstPerson
