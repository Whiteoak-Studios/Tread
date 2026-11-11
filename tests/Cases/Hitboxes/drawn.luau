--[[
    Switched on, the hitboxes draw the owner's body and every other drawn
    character at the state Tread draws it in: its hull standing or crouched,
    the lying box only while downed or lying, and the hit shapes of the
    posture it is hit through, placed at its feet, facing, lean and aim pitch
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local Vector3: any = roblox.Vector3

local DRAWN: string = "Hitboxes" -- The Workspace folder the hitboxes draw in
local OWNER: string = "-1" -- The owner's body's drawing
local OWN: number = 9
local CROUCHED: number = 20 -- An NPC crouched, turned and leaning
local DOWNED: number = 21 -- A bot's character downed
local SLEEPER: number = 22 -- A sleeper whose records say it stands, which lies all the same
local GENERATION: number = 1
local TICK: number = 50
local OWNER_TICK: number = 100
local FRAMES: number = 6
local FEET: vector = vector.create(0, 50, 0)
local AT: vector = vector.create(12, 3, -40)
local YAW: number = 1.25 -- Radians
local LEAN: number = 12 -- Degrees, to the right
local PITCH: number = 0.5 -- Radians the crouched NPC aims up by
local PITCH_STEP: number = (math.pi / 2) / 127 -- Radians a record's i8 pitch steps by, 127 to 90°
local LEVEL: number = 0 -- The aim pitch the level placement the crouched NPC's head moves back from takes
local CLOSE: number = 1e-3

-- Why an adornment sits off where it was due, or nil when it sits there
local function placed(name: string, got: any, want: any): string?
	if got == nil then
		return `The {name} was never drawn`
	elseif not got.Visible then
		return `The {name} was hidden`
	elseif (got.CFrame.Position - want).Magnitude > CLOSE then
		return `The {name} sat at {got.CFrame.Position}, not {want}`
	end

	return nil
end

-- Why a drawn capsule sits off a placed shape, or nil when its cylinder and both spheres sit on it
local function onShape(anchor: any, name: string, shape: any): string?
	local from: any = Vector3.new(shape.from.x, shape.from.y, shape.from.z)
	local to: any = Vector3.new(shape.to.x, shape.to.y, shape.to.z)
	local shaft: any = anchor:FindFirstChild(name)

	local failure: string? = placed(`{name} capsule's cylinder`, shaft, (from + to) / 2)
		or placed(`{name} capsule's first sphere`, anchor:FindFirstChild(`{name}From`), from)
		or placed(`{name} capsule's second sphere`, anchor:FindFirstChild(`{name}To`), to)

	local length: number = (to - from).Magnitude
	if failure then
		return failure
	elseif math.abs(shaft.Height - length) > CLOSE or math.abs(shaft.Radius - shape.radius) > CLOSE then
		return `The {name} capsule's cylinder was {shaft.Height} long at {shaft.Radius}, not its shape's`
	elseif length > 0 and math.abs(shaft.CFrame.ZVector:Dot((to - from).Unit)) < 1 - CLOSE then
		return `The {name} capsule's cylinder stood along {shaft.CFrame.ZVector}, not between its two points`
	end

	return nil
end

-- Whether two sizes match within a property's float32 rounding
local function same(a: any, b: any): boolean
	return (a - b).Magnitude <= CLOSE
end

-- Whether two CFrames stand at the same place turned the same way, within a property's float32 rounding
local function aligned(a: any, b: any): boolean
	return same(a.Position, b.Position) and same(a.LookVector, b.LookVector) and same(a.UpVector, b.UpVector)
end

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local mounted: Kit.Mounted = Kit.mount(rig)
	local workspace: any = rig.globals.game:GetService("Workspace")
	local Public: any = rig.globals.require(rig.tread.Step.Public)
	local Shapes: any = rig.globals.require(rig.tread.Step.Shapes)

	local switch: (on: boolean) -> () =
		mounted.require(mounted.exploits.Hitboxes).start({ client = rig.handle, shared = rig.shared })

	rig.handshake()
	rig.own(OWN, GENERATION)
	rig.owner(rig.body(FEET, 0, OWNER_TICK))

	local kinds: { [number]: string } = { [CROUCHED] = "Npc", [DOWNED] = "Player", [SLEEPER] = "Sleeper" }
	local words: { [number]: number } = {
		[CROUCHED] = rig.word({ posture = "Crouch" }),
		[DOWNED] = rig.word({ posture = "Downed" }),
		[SLEEPER] = rig.word({}),
	}

	local entries: { any } = {}
	for slot: number in kinds do
		table.insert(entries, { slot = slot, generation = GENERATION, rig = "A" })
	end
	rig.slots(entries)

	switch(true)

	for tick: number = TICK, TICK + FRAMES do
		local reveals: { any } = {}
		local records: { any } = {}

		for slot: number, kind: string in kinds do
			if tick == TICK then
				table.insert(reveals, { slot = slot, generation = GENERATION, kind = kind })
			end

			local lean: number = slot == CROUCHED and LEAN or 0
			local pitch: number = slot == CROUCHED and PITCH or 0
			table.insert(records, {
				slot = slot,
				generation = GENERATION,
				position = AT + vector.create(slot, 0, 0),
				yaw = YAW,
				pitch = pitch,
				lean = lean,
				word = words[slot],
			})
		end

		rig.relay({ tick = tick, reveals = reveals, records = records })
		rig.frames(1)
	end
	rig.frames(FRAMES)

	local drawn: any = workspace:FindFirstChild(DRAWN)
	if not drawn then
		return false, "Switched on, the hitboxes drew no folder"
	end

	local step: any = rig.shared.step
	local states: { [string]: any } = {
		[OWNER] = rig.Predict.state(),
		[`{CROUCHED}`] = rig.handle._states[CROUCHED],
		[`{DOWNED}`] = rig.handle._states[DOWNED],
		[`{SLEEPER}`] = rig.handle._states[SLEEPER],
	}

	-- 1) The owner's hull is the standing box the client's own state hands the game
	local ownerAnchor: any = drawn:FindFirstChild(OWNER)
	local own: any = rig.handle:getState()
	local ownHull: any = ownerAnchor and ownerAnchor:FindFirstChild("Hull")
	if
		not ownHull
		or not aligned(ownHull.CFrame, own.standingBox.cframe)
		or not same(ownHull.Size, own.standingBox.size)
	then
		return false, "The owner's hull wasn't the standing box its state gives"
	elseif math.abs(ownHull.Size.Y - step.standing) > CLOSE or ownerAnchor.Lying.Visible then
		return false, `The standing owner's hull was {ownHull.Size.Y} tall, or its lying box showed`
	elseif drawn:FindFirstChild(`{OWN}`) then
		return false, "The owner's own slot was drawn a second time from the interpolation"
	end

	-- 2) Each remote's hull stands on the feet Tread drew it at, crouched for the downed and the crouched
	local poses: { [number]: vector } = {}
	local pitches: { [number]: number } = {}
	for _, call: any in rig.pool.of("pose") do
		poses[call.slot] = call.position
		pitches[call.slot] = call.pitch
	end

	local heights: { [number]: number } = { [CROUCHED] = step.crouched, [DOWNED] = step.crouched }
	for slot: number, height: number in heights do
		local anchor: any = drawn:FindFirstChild(`{slot}`)
		local hull: any = anchor and anchor:FindFirstChild("Hull")
		local feet: vector = poses[slot]
		local failure: string? = placed(`slot {slot}'s hull`, hull, Vector3.new(feet.x, feet.y + height / 2, feet.z))

		if failure then
			return false, failure
		elseif math.abs(hull.Size.Y - height) > CLOSE then
			return false, `Slot {slot}'s hull was {hull.Size.Y} tall, not {height}`
		end
	end

	-- 3) The lying box only for the downed and the sleeper, where the state's lying box puts it
	for key: string, state: any in states do
		local anchor: any = drawn:FindFirstChild(key)
		local lies: boolean = key == `{DOWNED}` or key == `{SLEEPER}`
		local boxes: any = Public.new()
		Public.fill(boxes, state, rig.handle._world, vector.zero, vector.zero)

		if not anchor then
			return false, `Nothing was drawn for {key}`
		elseif anchor.Lying.Visible ~= lies then
			return false, `{key}'s lying box showed {anchor.Lying.Visible}, where it lies {lies}`
		elseif
			lies
			and not (
				aligned(anchor.Lying.CFrame, boxes.lyingBox.cframe) and same(anchor.Lying.Size, boxes.lyingBox.size)
			)
		then
			return false, `{key}'s lying box wasn't the lying box its state gives`
		end
	end

	-- 4) Every capsule of the posture each is hit through, at its feet, facing, lean and the aim pitch its rig was
	-- posed with, a sleeper's Downed
	local postures: { [string]: string } =
		{ [OWNER] = "Stand", [`{CROUCHED}`] = "Crouch", [`{DOWNED}`] = "Downed", [`{SLEEPER}`] = "Downed" }
	local slots: { [string]: number } =
		{ [OWNER] = OWN, [`{CROUCHED}`] = CROUCHED, [`{DOWNED}`] = DOWNED, [`{SLEEPER}`] = SLEEPER }

	for key: string, posture: string in postures do
		local state: any = states[key]
		local pitch: number? = pitches[slots[key]]
		if pitch == nil then
			return false, `{key}'s rig was never posed, so its aim pitch is unknown`
		end

		local shapes: any = Shapes.cross(rig.shared.hitShapes[posture])
		local into: any = Shapes.cross(rig.shared.hitShapes[posture])
		Shapes.place(shapes, into, state.position, state.facing, state.lean, pitch)

		local anchor: any = drawn:FindFirstChild(key)
		local failure: string? = onShape(anchor, "Body", into.body)
		for name: string, shape: any in into.zones do
			failure = failure or onShape(anchor, name, shape)
		end

		if failure then
			return false, `{key}: {failure}`
		end
	end

	-- The crouched NPC's lean reached its shapes: its head sits off the line its legs stand on
	local crouched: any = drawn:FindFirstChild(`{CROUCHED}`)
	local head: any = crouched.head.CFrame.Position
	local legs: any = crouched.legsFrom.CFrame.Position
	if states[`{CROUCHED}`].lean == 0 or math.abs(head.X - legs.X) + math.abs(head.Z - legs.Z) < CLOSE then
		return false, "The leaning NPC's head was drawn straight over its legs"
	end

	-- Its aim pitch reached them too: the head sits back along its facing from where it would sit level
	local npc: any = states[`{CROUCHED}`]
	local aimed: number? = pitches[CROUCHED]
	local level: any = Shapes.cross(rig.shared.hitShapes.Crouch)
	Shapes.place(Shapes.cross(rig.shared.hitShapes.Crouch), level, npc.position, npc.facing, npc.lean, LEVEL)

	local levelHead: vector = (level.zones.head.from + level.zones.head.to) / 2
	local backX: number, backZ: number = math.sin(npc.facing), math.cos(npc.facing)
	local moved: number = (head.X - levelHead.x) * backX + (head.Z - levelHead.z) * backZ
	if aimed == nil or math.abs(aimed - PITCH) > PITCH_STEP then
		return false, `The crouched NPC's rig was posed at a pitch of {aimed}, not its record's {PITCH}`
	elseif moved < CLOSE then
		return false, `Aiming up, the crouched NPC's head was drawn {moved} studs back along its facing, not behind it`
	end

	switch(false)

	return true, nil
end
