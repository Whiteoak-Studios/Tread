--[[
    While the client spectates, the target's rig comes out at its first
    feed, dressed in its look and handed to the pool as the watched rig,
    and is drawn between its last two feed states; getEye gives the
    target's cleared eye and its newest feed look, and the spectate's end
    puts the rig away and gives the owner's eye back
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local OWN: number = 9
local TARGET: number = 14
local GENERATION: number = 1
local TICK: number = 60 -- The relay tick the target's view starts at
local END: number = 70
local FEED_TICK: number = 100 -- The simulation tick of the first feed's OwnerState
local OWN_AT: vector = vector.create(0, 50, 0)
local FIRST_AT: vector = vector.create(10, 0, 0)
local SECOND_AT: vector = vector.create(12, 0, 0)
local EYE_HEIGHT: number = 4.15625 -- Studs, on OwnerState's 1/32 grid
local HEAD: number = 7 -- The target's look, a slot-table field the example declares
local CLOSE: number = 1e-4

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	local rigs: any = handle._rigs
	local need: any = rig.globals.require
	local tread: any = rig.tread

	local Constants: any = need(tread.Constants)
	local Feed: any = need(tread.Codec.Feed)
	local Fields: any = need(tread.Codec.Fields)
	local OwnerState: any = need(tread.Codec.OwnerState)
	local Public: any = need(tread.Step.Public)
	local Record: any = need(tread.Codec.Record)

	local shared: any = rig.shared
	local layout: any = Fields.compile(shared.fields)
	local limits: any = { lean = shared.step.lean, headCone = shared.step.headCone }

	-- The pool's stand-in has no watch, so one is added that writes each call down
	local watches: { any } = {}
	rigs.watch = function (_: any, slot: number?)
		table.insert(watches, slot or false)
	end

	-- One feed: the target's OwnerState at a place and tick, then one stepped command's look
	local function feed(at: vector, tick: number, yaw: number, pitch: number)
		local state: any = rig.body(at, 0, tick)
		state.eyeHeight = EYE_HEIGHT
		state.mode = "Ground"
		state.grounded = true

		local owner: buffer = buffer.create(Constants.MAX_OWNER_STATE)
		local length: number = OwnerState.write(state, owner, 0, layout, limits)
		local commands: { any } = { { yaw = yaw, pitch = pitch, headYaw = 0, headPitch = 0 } }

		local scratch: buffer = buffer.create(Constants.MAX_FEED)
		local bytes: number = Feed.write(scratch, owner, 0, length, commands, #commands, limits)
		local data: buffer = buffer.create(bytes)
		buffer.copy(data, 0, scratch, 0, bytes)

		rig.send("Feed", data)
	end

	-- Whether the eye sits at a target's feet plus its eye height, looking along a look, and why not
	local function eyes(feet: vector, look: vector): string?
		local eye: Vector3, direction: Vector3 = handle:getEye()
		local wanted: vector = feet + vector.create(0, EYE_HEIGHT, 0)

		if
			math.abs(eye.X - wanted.x) > CLOSE
			or math.abs(eye.Y - wanted.y) > CLOSE
			or math.abs(eye.Z - wanted.z) > CLOSE
		then
			return `The eye was at {eye}, not {wanted}`
		elseif math.abs(direction.X - look.x) > CLOSE or math.abs(direction.Y - look.y) > CLOSE then
			return `The eye looked along {direction}, not {look}`
		end

		return nil
	end

	-- Whether the eye is the owner's, over its feet as it falls, and why not
	local function owned(): string?
		local eye: Vector3 = handle:getEye()
		if math.abs(eye.X - OWN_AT.x) > CLOSE or math.abs(eye.Z - OWN_AT.z) > CLOSE then
			return `The eye was at {eye}, not the owner's over {OWN_AT}`
		end

		return nil
	end

	rig.handshake()
	rig.own(OWN, GENERATION)
	rig.slots({ { slot = TARGET, generation = GENERATION, rig = "A" } })
	rig.owner(rig.body(OWN_AT, 0, FEED_TICK))
	rig.frames(1)

	rig.send("Spectate", Record.id(TARGET, GENERATION), TICK)

	-- The target's own look entry rides its first block, before any feed
	rig.relay({ tick = TICK, looks = { { slot = TARGET, generation = GENERATION, outfit = { head = HEAD } } } })
	rig.frames(1)

	local early: string? = owned()
	if early then
		return false, `Before the target's first feed: {early}`
	elseif #pool.of("checkout") ~= 1 then
		return false, "The target's rig came out before its first feed"
	end

	-- 1) The first feed draws the target's rig, dressed in its look, at the feed's place, and watched
	local firstLook: vector = Public.look(0.5, 0.2, 0, 0, shared.step.headCone)
	feed(FIRST_AT, FEED_TICK, 0.5, 0.2)
	rig.frames(1)

	local checkout: any = pool.of("checkout")[2]
	local poses: { any } = pool.of("pose")
	local last: any = poses[#poses]
	if checkout == nil or checkout.slot ~= TARGET or checkout.outfit.head ~= HEAD then
		return false, "The target's first feed didn't take its rig out in its look"
	elseif #watches ~= 1 or watches[1] ~= TARGET then
		return false, "The target's rig wasn't handed to the pool as the watched rig"
	elseif last.slot ~= TARGET or last.position ~= FIRST_AT then
		return false, "The target's rig wasn't drawn at its feed's place"
	elseif math.abs(last.pitch - math.asin(firstLook.y)) > CLOSE then
		return false, `The target's rig took an aim pitch of {last.pitch}, not its feed look's`
	end

	local problem: string? = eyes(FIRST_AT, firstLook)
	if problem then
		return false, problem
	end

	-- 2) A second feed draws it between the two over the tick between them, and a straggler changes nothing
	local secondLook: vector = Public.look(-0.4, 0, 0, 0, shared.step.headCone)
	feed(SECOND_AT, FEED_TICK + 1, -0.4, 0)
	problem = eyes(FIRST_AT, secondLook)
	if problem then
		return false, `On the second feed's arrival: {problem}`
	end

	local tickSeconds: number = 1 / shared.rates.simulation
	rig.frames(1, tickSeconds / 2)
	problem = eyes((FIRST_AT + SECOND_AT) / 2, secondLook)
	if problem then
		return false, `Halfway to the second feed: {problem}`
	end

	feed(FIRST_AT, FEED_TICK, 0.5, 0.2)
	rig.frames(1, tickSeconds)
	problem = eyes(SECOND_AT, secondLook)
	if problem then
		return false, `After the straggler: {problem}`
	elseif #pool.of("checkout") ~= 2 then
		return false, "Later feeds took another rig out for the target"
	end

	-- 3) The spectate's end puts the target's rig away and gives the owner's eye back
	rig.send("Spectate", nil, END)
	local released: any = pool.of("release")[1]
	if released == nil or released.slot ~= TARGET then
		return false, "The spectate's end didn't put the target's rig away"
	end

	problem = owned()
	if problem then
		return false, `After the spectate's end: {problem}`
	end

	return true, nil
end
