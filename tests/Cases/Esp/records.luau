--[[
    A block Tread's own codec wrote turns into one box a slot, switched on
    after it came: at the record's feet, turned by its yaw, the hull's size
    by its posture, named from the slot table or the reveal, with the count
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Rig = require("../../Fixtures/Esp/Rig")

local TICK: number = 50
local FRAMES: number = 3
local CLOSE: number = 1e-3 -- Studs and shares a placed value may differ by, since a part holds float32
local QUARTER: number = math.pi / 2

-- One character as the block carries it, and what its box should show
type Case = {
	slot: number,
	generation: number,
	kind: string,
	player: boolean, -- Whether the slot table names a Player for it
	at: vector,
	yaw: number,
	word: { [string]: any },
	crouched: boolean, -- Whether its box takes the crouched hull
	name: string?, -- What its label names it, the Player's name where nil
	look: vector, -- Its box's look, the yaw's
}

local CASES: { Case } = {
	{
		slot = 3,
		generation = 2,
		kind = "Player",
		player = true,
		at = vector.create(100.5, 5.25, -200.75),
		yaw = QUARTER,
		word = {},
		crouched = false,
		look = vector.create(-1, 0, 0),
	},
	{
		slot = 4,
		generation = 1,
		kind = "Player",
		player = false,
		at = vector.create(-12.25, 0.5, 40),
		yaw = math.pi,
		word = { posture = "Crouch" },
		crouched = true,
		name = "Bot",
		look = vector.create(0, 0, 1),
	},
	{
		slot = 5,
		generation = 1,
		kind = "Npc",
		player = false,
		at = vector.create(7, -3.5, 7),
		yaw = 0,
		word = { posture = "Downed" },
		crouched = true,
		name = "NPC",
		look = vector.create(0, 0, -1),
	},
	{
		slot = 6,
		generation = 3,
		kind = "Sleeper",
		player = false,
		at = vector.create(0, 1, 0),
		yaw = -QUARTER,
		word = {},
		crouched = false,
		name = "Sleeper",
		look = vector.create(1, 0, 0),
	},
	{
		slot = 7,
		generation = 1,
		kind = "Body",
		player = false,
		at = vector.create(300, 20, 300),
		yaw = 0,
		word = { mode = "Swim" },
		crouched = true,
		name = "Body",
		look = vector.create(0, 0, -1),
	},
}

local function near(a: any, b: vector): boolean
	return math.abs(a.X - b.x) < CLOSE and math.abs(a.Y - b.y) < CLOSE and math.abs(a.Z - b.z) < CLOSE
end

return function (): (boolean, string | nil)
	local rig: any = Rig.new()
	local step: any = rig.shared.step
	local switch: (on: boolean) -> () = rig.startEsp()

	local other: any = roblox.Instance.new("Player")
	other.Name = "Other"

	local entries: { any } = {}
	local reveals: { any } = {}
	local records: { any } = {}
	for _, case: Case in CASES do
		table.insert(entries, {
			slot = case.slot,
			generation = case.generation,
			rig = "A",
			player = case.player and other or nil,
		})
		table.insert(reveals, { slot = case.slot, generation = case.generation, kind = case.kind })
		table.insert(records, {
			slot = case.slot,
			generation = case.generation,
			position = case.at,
			yaw = case.yaw,
			word = rig.word(case.word),
		})
	end

	rig.slots(entries)
	rig.relay({ tick = TICK, reveals = reveals, records = records })
	rig.frames(FRAMES)

	if rig.drawn() then
		return false, "The ESP drew before it was switched on"
	end

	-- Every message went on to Tread's client, which drew each revealed slot itself
	local checkouts: number = #rig.pool.of("checkout")
	if checkouts ~= #CASES then
		return false, `Tread's client checked out {checkouts} rigs with the ESP hooked, not {#CASES}`
	end

	switch(true)
	rig.frames(FRAMES)

	local width: number = step.radius * 2
	for _, case: Case in CASES do
		local anchor: any, box: any, label: any = rig.slot(case.slot)
		if not anchor then
			return false, `Slot {case.slot} got no box`
		end

		local height: number = case.crouched and step.crouched or step.standing
		local center: vector = case.at + vector.create(0, height / 2, 0)

		if not near(anchor.CFrame.Position, center) then
			return false, `Slot {case.slot}'s box sits at {anchor.CFrame.Position}, not its hull's center {center}`
		elseif not near(anchor.CFrame.LookVector, case.look) then
			return false, `Slot {case.slot}'s box looks along {anchor.CFrame.LookVector}, not its yaw's {case.look}`
		elseif not near(box.Size, vector.create(width, height, width)) then
			return false, `Slot {case.slot}'s box is {box.Size}, not the {width} by {height} hull`
		elseif not box.Visible or not box.AlwaysOnTop then
			return false, `Slot {case.slot}'s box is hidden or drawn behind walls`
		end

		local name: string = case.name or other.Name
		if not string.find(label.Text, name, 1, true) then
			return false, `Slot {case.slot}'s label reads "{label.Text}", not naming {name}`
		end
	end

	local count: any = rig.count()
	if not count or not string.find(count.Text, `{#CASES} slots`, 1, true) then
		return false, `The count reads "{count and count.Text}", not the last block's {#CASES} slots`
	end

	-- A newer record moves its box while the ESP draws
	local moved: vector = vector.create(-50, 10, 60.5)
	rig.relay({
		tick = TICK + 1,
		records = { { slot = 3, generation = 2, position = moved, word = rig.word({}) } },
	})
	rig.frames(FRAMES)

	local anchor: any = rig.slot(3)
	if not near(anchor.CFrame.Position, moved + vector.create(0, step.standing / 2, 0)) then
		return false, `Slot 3's box stayed at {anchor.CFrame.Position} after a record moved it to {moved}`
	elseif not string.find(rig.count().Text, "1 slots", 1, true) then
		return false, `The count reads "{rig.count().Text}" after a block of one record`
	end

	switch(false)

	return true, nil
end
