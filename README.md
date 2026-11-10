# Tread

Tread is Whiteoak Studios' custom character controller for Roblox. It replaces the default Roblox character with server-authoritative movement, client prediction and reconciliation, kinematic collision, replication to other players with per-viewer relevancy and anti-ESP, a lag-compensation history, and client-built rigs with first person. It is built for 150-player servers and beyond.

A game hooks into Tread and keeps its own lifecycle logic, such as spawn, death, respawn, downed and sleepers. Everything game-specific is configuration the game supplies. Frontier Zero is the first game built on it.

Tread is a public Wally package, `fadeluc-123/tread`, under the Apache-2.0 license.

## Status

Tread is not released yet. Its code is built through the third step of its build plan: the shared step and collision, prediction and reconciliation, replication with anti-ESP, NPCs, sleepers and bodies, spectate, moving platforms, the teleport, the recording taps and clip playback. The benchmark gates and the runs on a live server are still to come, and no version is tagged or on the Wally index.

The API this README documents is the shape the first release is built to. It may still change before that release.

## Installing

### Wally

Add Tread and Volt to the game's `wally.toml`:

```toml
[dependencies]
Tread = "fadeluc-123/tread@1.0.0"
Volt = "fadeluc-123/volt@0.1.0"
```

1.0.0 is the version Tread's manifest names for its first release. The package's realm is `shared`, since the owning client runs the same step as the server, so Wally puts it in `Packages/` and the game mounts that folder at `ReplicatedStorage.Packages`.

### Volt

Tread's generated Volt modules ship inside the package, and each requires the game's own Volt runtime at `ReplicatedStorage.Packages.Volt`. Install Volt under the alias `Volt`, on the same major.minor as the Volt compiler Tread was built with. Tread pins the `volt` 0.1.0 compiler, so the runtime must be a 0.1 release; under Wally's version rules, `0.1.0` means at least 0.1.0 and below 0.2.0.

### Promise

Tread's manifest lists `evaera/promise` 4.0.0, which Wally installs beside it. Tread's schema doesn't set `yield = promise`, so its generated modules never require Promise, and a game needs no Promise at `ReplicatedStorage.Packages.Promise` for Tread's sake. The one place Tread meets a Promise is the optional `prestream` hook, which returns one.

### Place settings

A place that runs Tread has no Roblox character, so it needs these settings:

- `Players.CharacterAutoLoads` off. Tread builds every character itself, and `Player.Character` stays nil.
- An empty `PlayerModule` under `StarterPlayer.StarterPlayerScripts`, a ModuleScript that returns `{}`, so Roblox's default camera and control scripts never run. The game writes its own camera from `client:getEye()`.
- `Workspace.Gravity` equal to the shared table's `step.gravity`, so loose physics objects, client ragdolls among them, fall the way characters do. Tread doesn't check it.
- `Workspace.StreamingIntegrityMode` set to Disabled when streaming is on. Tread sets each player's `ReplicationFocus` itself, to a focus part it keeps under a server-only Camera, so the game shouldn't set it.
- `Workspace.UseFixedSimulation` off (Disabled). With it on, a joint's `Transform` can't be written while a track plays, and Tread's rigs write it. No script can read the setting, and Tread doesn't detect it at start, so check it in the place.
- UI mounted from `StarterPlayerScripts`. Without a character, StarterGui is never copied into PlayerGui.

Rojo 7.7.0's serve never writes `StreamingIntegrityMode` or `UseFixedSimulation`, which its plugin marks not scriptable. A place gets them from `rojo build` or from setting them once by hand in Studio.

## Starting Tread

A game passes three tables: a shared table that both entry points take, the server settings and the client settings. Build the shared table once, in a module both realms require, because the server sends a hash of it in its handshake and a client whose table hashes differently never plays.

### The shared table

```lua
--[[
    The shared table both of Tread's entry points take: the numbers and
    field declarations in Config/Tread, with the game's collision
    functions, water query and movement rules added
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Cast = require(ReplicatedStorage.Shared.Classes.Cast)
local Rules = require(ReplicatedStorage.Shared.Classes.Movement.Rules)
local WaterHeight = require(ReplicatedStorage.Shared.Extensions.WaterHeight)

local CONFIG = require(ReplicatedStorage.Shared.Config.Tread)

local Shared: Tread.Shared = {
	rates = CONFIG.rates,
	ticks = CONFIG.ticks,
	step = CONFIG.step,
	tolerances = CONFIG.tolerances,
	hitShapes = CONFIG.hitShapes,
	fields = CONFIG.fields,

	collision = {
		ray = Cast.ray,
		sweep = Cast.sweep,
		rest = Cast.rest,
		sphere = Cast.sphere,
	},

	water = WaterHeight,
	rules = Rules,
}

return Shared
```

A game on engine casts passes no collision functions and gives `collision = { include = { ... } }`, the instances the casts may hit.

### Starting the server

```lua
--[[
    Starts Tread's server with the game's shared table and server settings,
    and hands every report Tread raises to the game's cheat score
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local CheatScore = require(ServerScriptService.Server.Modules.CheatScore)
local Equip = require(ServerScriptService.Server.Modules.Equip)
local TreadShared = require(ReplicatedStorage.Shared.Classes.TreadShared)

local SETTINGS = require(ServerScriptService.Server.Config.Tread)

local serverSettings: Tread.ServerSettings = {
	rates = SETTINGS.rates,
	catchUp = SETTINGS.catchUp,
	slots = SETTINGS.slots,
	relevancy = SETTINGS.relevancy,
	tiers = SETTINGS.tiers,
	weights = SETTINGS.weights,
	shotNear = SETTINGS.shotNear,
	budget = SETTINGS.budget,
	antiEsp = SETTINGS.antiEsp,
	footsteps = SETTINGS.footsteps,
	sleepers = SETTINGS.sleepers,
	npcs = SETTINGS.npcs,
	history = SETTINGS.history,
	rewind = SETTINGS.rewind,
	teleport = SETTINGS.teleport,

	-- Runs before each command is simulated, and never in the owner's prediction
	beforeCommand = function (character: Tread.Character, command: Tread.Command)
		Equip.advance(character, command)
	end,
}

local tread: Tread.Server = Tread.startServer(TreadShared, serverSettings)

-- Lives as long as the server. Tread keeps no score, so every report is the game's to weigh
tread:onReport(CheatScore.report)
```

A character's life is the game's to run. A spawn, a death and a leave look like this:

```lua
local character: Tread.Character = tread:create(player, at)
character:setOutfit(outfit)
character:setTeam(team)

-- A death: the body takes a slot of its own, and the character is released
local body: Tread.Body = character:die(push)
character:destroy()

-- A leave: the sleeper takes the character's slot, or nil past the sleeper limit
local sleeper: Tread.Sleeper? = character:sleep()
character:destroy()
```

### Starting the client

```lua
--[[
    Starts Tread's client with the game's shared table and client settings,
    writes the camera from the eye Tread publishes, and plays each culled
    enemy's footstep where it fell
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Attire = require(ReplicatedStorage.Shared.Classes.Attire)
local HeldItem = require(ReplicatedStorage.Shared.Classes.HeldItem)
local Movement = require(ReplicatedStorage.Shared.Classes.Movement)
local Sound = require(ReplicatedStorage.Shared.Classes.Sound)
local TreadShared = require(ReplicatedStorage.Shared.Classes.TreadShared)

local Camera = Workspace.CurrentCamera

-- Boot-time waits: the asset package may not have replicated yet
local Animations = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations") :: Folder
local Rig = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Character") :: Model

local JOINTS: { [string]: string } = require(ReplicatedStorage.Shared.Config.Rig).joints
local SETTINGS = require(ReplicatedStorage.Shared.Config.TreadClient)

local animations: { [string]: Animation } = {}
for _, animation: Instance in Animations:GetChildren() do
	if animation:IsA("Animation") then
		animations[animation.Name] = animation
	end
end

local clientSettings: Tread.ClientSettings = {
	sample = Movement.sample,
	look = Movement.look,
	rig = Rig,
	joints = JOINTS,
	animations = animations,
	dress = Attire.dress,
	undress = Attire.strip,
	hold = HeldItem.attach,
	interpolation = SETTINGS.interpolation,
	bodies = SETTINGS.bodies,
	spectate = SETTINGS.spectate,
	smoothing = SETTINGS.smoothing,
	drawDistance = SETTINGS.drawDistance,
	lod = SETTINGS.lod,
	firstPerson = SETTINGS.firstPerson,
}

local tread: Tread.Client = Tread.startClient(TreadShared, clientSettings)
Camera.CameraType = Enum.CameraType.Scriptable

-- At Camera priority, after Tread's own frame, so the camera reads this frame's eye
RunService:BindToRenderStep("GameCamera", Enum.RenderPriority.Camera.Value, function ()
	local eye: Vector3, look: Vector3 = tread:getEye()
	Camera.CFrame = CFrame.lookAlong(eye, look)
end)

-- Lives for the client session. An enemy culled from this client has no rig, so its steps arrive as points
tread:onFootstep(function (step: Tread.Footstep)
	Sound.playStepAt(step.at, step.kind, step.material)
end)
```

Tread draws each frame in a render step, `TreadFrame`, at `Enum.RenderPriority.Camera.Value - 1`. A camera bound at Camera priority or later, or connected to `RunService.PreRender`, reads that frame's eye, and one bound below Camera priority reads the previous frame's.

### Configuration

Tread holds no game values and ships no default for any setting. Every gameplay number below is the game's own, and every key is required unless its line says optional. Tread's own wire and parity invariants are constants inside the package that no game sets: the codec layouts and `CODEC_VERSION`, the 1/512-stud state quantum, the 0.02-stud skin, the cap of 4 collision bumps, the ±8,192-stud play bound, the 4,096 character slots, the 127 platform ids and the byte bounds on the game's declared fields.

#### The shared table

| Key | What it sets |
|---|---|
| `rates.simulation`, `rates.relay` | The step's rate and the relay's, in Hz. |
| `ticks.standIn` | The ticks a stand-in repeats held inputs for. |
| `ticks.ahead` | How far ahead of the server a command may run before it is dropped. |
| `ticks.queueWait` | The cap on a shot's queue wait in the rewind, in simulation ticks. |
| `ticks.leadMin`, `ticks.leadMax` | The queue, in ticks, the client's clock holds at the server. |
| `ticks.nudge` | The largest share the client's clock is nudged by, 0 to 1. |
| `ticks.resync` | How far the command clock may drift, in ticks, before it snaps. |
| `ticks.debt` | The time debt a frozen client keeps, at least 1 tick. |
| `step.gravity` | Gravity, studs/s². `Workspace.Gravity` should match it. |
| `step.walk`, `step.sprint`, `step.crouch` | The stance speeds, studs/s. |
| `step.swim`, `step.swimSprint`, `step.ladder`, `step.ladderSprint` | The swim and ladder speeds, studs/s. |
| `step.jump` | A jump's upward speed, studs/s. |
| `step.stepHeight` | The tallest step a body walks up, studs. |
| `step.walkable` | The lowest ground normal Y a body walks on. |
| `step.standable` | The lowest ground normal Y a body stands on without gaining height, at most `walkable`. |
| `step.terminal` | The terminal falling speed, studs/s. |
| `step.landing` | The seconds in the air before a landing counts. |
| `step.airEase`, `step.ladderEase`, `step.waterEase` | How fast velocity moves toward its target, per second, in the air, on a ladder and in water. |
| `step.waterEntry` | The share of velocity kept on entering water, 0 to 1. |
| `step.radius` | The hull's half width, studs. |
| `step.standing`, `step.crouched` | The hull's standing and crouched heights, crouched below standing. |
| `step.eyeStanding`, `step.eyeCrouched`, `step.eyeDowned` | The eye heights above the feet, studs. |
| `step.eyeEase` | How fast the eye eases to a new height, per second. |
| `step.clearance` | The eye's distance from walls and ceilings, studs. |
| `step.clearanceStart` | How far below the hull's top the clearance cast starts, above `clearance`. |
| `step.lean` | The lean limit either way, degrees. |
| `step.leanShift` | The eye's shift at full lean, a `Vector3`: sideways, then down. |
| `step.leanRate` | The fastest lean the server accepts, degrees a second. |
| `step.headCone` | The head offset's cone either side of facing, degrees. |
| `step.ladderDrop` | How far below level, in degrees, a climber's look may point before forward input on a ladder loses its up part, and before a body on the ground stops mounting one. Above 0 and below 90. |
| `step.swimEnter`, `step.swimLeave` | The water depths at which a body starts and stops swimming, `swimLeave` below `swimEnter`. |
| `step.floatDepth` | How far an idle swimmer's feet float below the surface. |
| `step.crouchDepth` | The depth past which crouch is refused. |
| `step.mantleHeight` | The mantle's reach above the last ground, studs. |
| `step.mantleReach` | How far, in studs, past the hull's front a ledge's face may stand for a jump press, or `client:getMantle()`, to find a mantle. Above 0, and short enough that one tick's move to the face stays under 512 studs/s. Frontier Zero uses the hull's radius, 1.39 studs. |
| `step.mantleTime` | The mantle's duration in seconds, which must round to 1 to 255 ticks at `rates.simulation`. |
| `step.mantleArc` | How far, in studs, the mantle's path peaks above the point where its feet clear the ledge's top; 0 or more. |
| `step.ladderJump` | The speed of a jump off a ladder, studs/s. |
| `step.headSlide` | How fast a character slides off another's head, studs/s. |
| `step.lyingBox` | The lying box, `{ length, width, height, lift }`, laid along the body's facing with its center `lift` above the ground. |
| `step.slide` | Optional. The crouch slide ([The crouch slide](#the-crouch-slide)), which runs only when the table is given. Every key inside it is required. |
| `step.slide.start` | The horizontal speed, studs/s, a body needs to start a slide. |
| `step.slide.boost` | The studs/s a slide adds at its start, 0 or more. A start never passes the greater of the body's speed and `step.sprint` plus the boost. |
| `step.slide.friction` | The studs/s a slide loses each second, 0 or more. |
| `step.slide.slope` | The share of gravity along the ground, 0 to 1, that speeds a slide downhill and slows it uphill. |
| `step.slide.max` | A slide's top speed, studs/s, at least `start`. |
| `step.slide.stop` | The speed, studs/s, below which a slide ends, below `start`. |
| `step.slide.steer` | How fast a slide's direction turns toward the move input, degrees a second, 0 or more. |
| `step.slide.cooldown` | The seconds from a slide's end to the next start, at most 255 ticks at `rates.simulation`. |
| `tolerances.Ground`, `Air`, `Swim`, `Ladder`, `Rider`, `Mantle` | How far a prediction may drift in each state before the owner replays, in whole quanta of 1/512 stud. A crouch slide takes `Ground`'s. |
| `hitShapes.Stand`, `Crouch`, `Downed` | Each posture's hit shapes: `body`, the broad capsule, `zones`, the zone capsules by name, and `waist`, the height a lean tilts the upper body about. Each capsule is a `Shape` in the character's own space, feet at the origin, facing along -Z. A swimmer is hit through `Crouch`, and a sleeper through `Downed`. |
| `collision.ray`, `sweep`, `rest`, `sphere` | Optional, as a set: the game's four collision functions. Give all four or none. |
| `collision.include` | The instances engine casts may hit, required when no collision function is given. Beside the functions it is optional, and names the parts depenetration's overlap probe tests, which otherwise tests every part with CanCollide on. |
| `water` | Optional. The water-surface query. |
| `rules` | The rules function. |
| `fields.command`, `rules`, `server`, `slot`, `held` | The game's declared fields: the Move command's, the rule-state block's, the server-set fields', the look's and the held item's. |

#### The server settings

| Key | What it sets |
|---|---|
| `rates.move`, `rates.view` | The rate of each endpoint the server hears, `{ perSecond, burst }`, with `burst` at least 1: Move carries the owner's commands, and View the client's render distance. |
| `catchUp` | The most ticks one Heartbeat may run after a stall, at least 1. |
| `slots.reserve` | The slots sleepers may never take, a whole number from 0 to 4,096. |
| `relevancy.enter`, `relevancy.leave` | The relevancy radius on the way in and on the way out, studs, `enter` below `leave`. It is the most any viewer gets. Each viewer's own radius is its client's render distance held to `leave`, and a character enters it inside that distance times `enter / leave`. |
| `tiers.nearEnter`, `tiers.nearLeave` | The near tier's radius on the way in and out, studs. |
| `tiers.nearFloor`, `tiers.nearAim` | The near tier's floor and target send rates, Hz. |
| `tiers.farFloor`, `tiers.farAim` | The far tier's floor and target send rates, Hz. |
| `weights.near`, `far`, `shooter`, `cone` | The send allocator's priority weights. |
| `shotNear.rate`, `shotNear.seconds` | How fast, and for how long, a shooter whose bullet passed near a viewer is sent to that viewer. |
| `budget.soft`, `budget.hard` | The per-viewer downstream across every Volt stream, KB/s. |
| `antiEsp.rays` | The rays per enemy pair, 1 to 5. |
| `antiEsp.lookAheadMin`, `lookAheadMax` | The clamp on anti-ESP's look-ahead, seconds. |
| `antiEsp.slice` | The time anti-ESP may take a Heartbeat, seconds. |
| `antiEsp.hiddenRate`, `visibleRate` | How often a hidden pair and a visible pair are tested again, Hz. |
| `antiEsp.nearRadius`, `antiEsp.nearRate` | A hidden pair whose target's feet stand within `nearRadius` studs of the viewer's eye at its test is tested again at `nearRate` Hz instead of `hiddenRate`. Both are above 0. |
| `antiEsp.hold` | How long a pair a test found visible stays shown while every ray is blocked, seconds. |
| `antiEsp.failOpen` | How long a hidden pair may go without a recheck before it is sent anyway, seconds. |
| `antiEsp.include` | The instances anti-ESP's rays may hit, CanCollide on or off: an occluder folder and `Workspace.Terrain`, say. |
| `footsteps.range.walk`, `sprint`, `jump`, `land` | Each optional: how far, in studs, each kind of a culled enemy's step is heard. A kind with no range is silent. A crouch slide steps as `Sprint`, at the sprint's stride and range, and steps taken crouched, crawling, swimming, climbing, mantling or in a staff mode are never sent. |
| `footsteps.stride.walk`, `footsteps.stride.sprint` | The studs a culled enemy covers per step at each gait, from which the server times its footstep entries. |
| `sleepers.radius` | The sleeper reveal radius, studs. |
| `sleepers.rays` | The rays per sleeper or body pair, 1 to 3. |
| `sleepers.retest` | How far a viewer moves, in studs, before a sleeper pair is tested again. |
| `sleepers.rate`, `sleepers.hold` | The sleeper and body recheck rate, Hz, and their visible hold, seconds. |
| `npcs.near`, `npcs.farRate`, `npcs.range` | The NPC relay: every relay tick inside `near`, `farRate` Hz beyond it, and nothing past `range`. |
| `history.seconds` | How long the lag-compensation history holds. |
| `rewind.ceiling` | The furthest a rewind reaches into the past, seconds. |
| `rewind.rttCap` | The cap on the round trip a rewind counts, seconds. |
| `rewind.delayMin`, `rewind.delayMax` | The clamp on the client's interpolation delay a rewind counts, seconds. |
| `rewind.extra` | The relay ticks a rewind's reach adds. |
| `rewind.band`, `rewind.bandSigmas`, `rewind.bandMax` | The render-time band: its width in relay ticks, the jitter's standard deviations on top, and its widest in relay ticks. |
| `rewind.rttSmoothing` | The time constant, in seconds, each connection's round trip and jitter are smoothed over. |
| `teleport.timeout` | The longest a teleport waits on its destination, seconds. |
| `beforeCommand` | The pre-command hook. |
| `prestream` | Optional. The teleport destination hook. |
| `bots.rtt` | Optional. The round trip a bot's connection reports, seconds. A server that creates bots must give it. |

#### The client settings

| Key | What it sets |
|---|---|
| `sample` | The per-tick input sample. |
| `look` | The per-frame look. |
| `rig` | The rig template, a Model. |
| `joints` | Each logical joint's AnimationConstraint name in the rig. |
| `animations` | One Animation per state Tread plays, by the state's name, `slide` among them only when the shared table gives `step.slide`, and any others the game keeps beside them. |
| `dress`, `undress`, `hold` | The hooks that put a look and a held item on a rig and take them off. |
| `interpolation.delay`, `interpolation.delayMax` | The remote interpolation delay the client starts at, and its ceiling, past which it snaps; seconds, `delay` below `delayMax`. |
| `interpolation.scaleMin`, `interpolation.scaleMax` | The range of the interpolation's time scale. |
| `bodies.radius`, `bodies.late` | Which clients ragdoll a dying rig: one whose eye is within `radius` studs of the dying body, reached by the death within `late` seconds of the body's newest record. Any other draws it lying. |
| `bodies.minSeconds`, `maxSeconds`, `check`, `settleSpeed` | When a ragdoll freezes: at the first check, every `check` seconds after `minSeconds`, at which every part moves slower than `settleSpeed` studs/s, or at `maxSeconds`. |
| `bodies.pushSpeed`, `bodies.pushUpBias` | The torso's push along the death's attack direction, studs/s, raised by the up bias. |
| `bodies.jointLimits` | Each logical joint's ragdoll limits in degrees, `{ tilt, twistLower, twistUpper }`, a BallSocketConstraint's own three, for every joint but `Root`. |
| `spectate.outline` | The outline a spectating moderator's client draws every other player with, through walls: `{ fill: Color3, fillTransparency: number, outline: Color3, outlineTransparency: number }`, transparencies 0 to 1. |
| `smoothing.decay`, `smoothing.snap` | How fast the visual error offset after a correction shrinks, per second, and the correction size, in studs, that snaps. |
| `drawDistance.desktop`, `console`, `phone`, `tablet` | The character draw distance per device class, studs. Tread reads the class once at start: console on a ten-foot interface, desktop with no touch or with a keyboard, phone on a small touch display, tablet otherwise. It is also the render distance the client starts with and sends the server, until the game calls `client:setRenderDistance`. |
| `lod.full`, `lod.footIk`, `lod.aim` | The distances, in studs, inside which a rig animates in full, plants its feet, and shows aim pitch. Lean shows wherever a character is drawn. |
| `firstPerson.back` | How far behind the world rig, in studs along its facing, the local player's first-person copy is drawn, 0 or more, so its torso stays behind a camera at the eye. The camera, the eye and everything the server reads stay where they are. Tune it to your rig, field of view and near plane: on Roblox's stock R15 rig at a 70° view, 1 stud kept the walking body clear of a 0.1-stud near plane, and a 0.5-stud near plane needed 1.55 looking straight down. While a rig is the copy, its model is named `FirstPersonCopy`. |

#### How the tables are checked

Each entry point checks its tables before it does anything else, and errors naming the first key missing or wrong, as `<path> expected <what>, and got <what>`.

- It refuses any key Tread doesn't read, a misspelled optional key included, except in the maps whose keys the game names: `hitShapes.*.zones`, `joints`, `bodies.jointLimits` and the extra `animations`.
- It refuses NaN and both infinities for every number. Rates, durations, distances and sizes are above 0, or 0 or more where 0 has a meaning. Tick counts and tolerances are whole numbers, and ratios run from 0 to 1.
- A speed must stay below 512 studs/s once quantized, and an eye height or `step.mantleHeight` at most 7.96875 studs, the limits of the fields OwnerState carries them in. `step.mantleReach` times `rates.simulation` is held to the same speed limit, and so is `step.slide.max`.
- Given a slide, `step.slide.stop` must be below `start` and `max` at least `start`, and `cooldown` must round to at most 255 ticks at `rates.simulation`, the most the cooldown's `u8` counts.
- Each pair is ordered: the second of `ticks.leadMin` and `leadMax`, `step.standable` and `walkable`, `tiers.nearFloor` and `nearAim`, `tiers.farFloor` and `farAim`, `budget.soft` and `hard`, `antiEsp.lookAheadMin` and `lookAheadMax`, `npcs.near` and `range`, `rewind.delayMin` and `delayMax`, `rewind.band` and `bandMax`, `interpolation.scaleMin` and `scaleMax`, and each joint's `twistLower` and `twistUpper` is at least the first. The second of `step.crouched` and `standing`, `step.clearance` and `clearanceStart`, `step.swimLeave` and `swimEnter`, `relevancy.enter` and `leave`, `tiers.nearEnter` and `nearLeave`, `interpolation.delay` and `delayMax`, and `bodies.minSeconds` and `maxSeconds` is above the first.
- The server's start errors naming any endpoint it hears that `rates` gives no rate.
- The client's start errors naming the first state with no Animation, `animations.slide` when the shared table gives `step.slide` and the map has none, the first logical joint the rig has no AnimationConstraint for, and the first joint but `Root` that `bodies.jointLimits` gives no limits for.

#### Type-checking a game's tables

Under luau-lsp's new type checker:

- `collision`'s five keys are read-only in the type, so a game's own module of its four functions fits as a whole.
- A table that names its keys, built in another module, fits no map type. Type each map built outside the start call's literal as the map: `hitShapes.*.zones`, `footsteps.range`, `joints`, `animations` and `bodies.jointLimits`.
- The strings in a field declaration are singletons in `Tread.Field`, so a `fields` table built in its own module needs a cast, `:: Tread.Fields`, or they widen to `string`.
- A whole settings table built in another module and passed as it is gets none of its optional keys, such as `bots`. Build the table in a literal where it is passed, as the examples above do.

## The API

`local Tread = require(ReplicatedStorage.Packages.Tread)`. Every position, direction and size a game passes to Tread or gets back is a `Vector3`. No game function Tread calls may yield, and no member yields. Each `on...` signal returns the closure that disconnects its callback.

### The package root

- `Tread.startServer(shared: Shared, server: ServerSettings): Server` checks both tables, binds Tread's own Volt endpoints at the settings' rates, starts the tick on Heartbeat and returns the server handle. It runs once a server, and only it loads the server's modules.
- `Tread.startClient(shared: Shared, client: ClientSettings): Client` checks both tables, starts the owner's prediction, the remote interpolation and the rig pool, connects Tread's Volt scope, and returns the client handle. It runs once a client, and only it loads the client's modules.
- `Tread.CODEC_VERSION: number` is the version of Tread's wire layouts, which every keyframe carries.
- `Tread.decode(version: number, kind: string, data: buffer): { [string]: any }` decodes one of Tread's layouts, as that `CODEC_VERSION` packed it, into new tables, for clips and tools. `kind` is `"relay"`, `"withheld"`, `"owner"`, `"feed"`, `"keyframe"`, `"record"`, `"command"`, `"tap"` or `"snapshot"`. Every position and direction comes back a `Vector3`, and each block of the game's declared fields as its packed bytes. It errors on a version or kind it has no reader for, and on bytes that aren't that layout.

### The server handle

- `server:create(player: Player | Bot, at: CFrame): Character` builds a character in a free slot, its feet at `at`'s position, facing along its look. A bot is one of Volt's bots, from `Volt.addBot`, and needs `bots.rtt`. It errors, naming the held-back count, when no slot is free.
- `server:createNpc(at: CFrame): Npc` builds an NPC body, awake, in a slot with no player.
- `server:createSleeper(at: CFrame, outfit: Outfit): Sleeper?` builds a sleeper lying at `at` and wearing `outfit`, for the game's rebuild of its sleepers at boot. Past the sleepers' share it builds none, returns nil and reports `sleep`.
- `server:getAll(): { Target }` gives every live character, NPC and sleeper.
- `server:near(at: Vector3, range: number): { string }` gives the names of the players and bots whose characters stand within range of a point, the edge included.
- `server:npcsNear(at: Vector3, range: number): { Npc }` gives the NPCs within range of a point.
- `server:overlaps(cframe: CFrame, size: Vector3): boolean` says whether a box overlaps any live character's or NPC's hull, for the game's placement and door checks.
- `server:sampleAt(target: Target, renderTime: number, commandTime: number?): Sample?` is the history read for a hit test: the target's hit shapes placed as they stood at a render time in relay ticks. It returns nil for a time the history no longer holds, one the target spent in Noclip or Parked, or a target that has ended. `commandTime`, a simulation tick with its fraction, places a platform rider where its platform stood then, and with none the render time does. The sample is the target's own table, which its next read rewrites.
- `server:rewindFor(player: Player | Bot, command: number, renderTime: number): (number, boolean)` gives the render time, in relay ticks, to rewind a shot to, and whether its claimed time was inside the band. `command` is the number of the command the shot rode in, one of the last 8 the character stepped, and `renderTime` is the claimed render time in relay ticks with its fraction, whose whole ticks may be just their low 16 bits. A claim outside the band is reported as `band`.
- `server:addLadder(cframe: CFrame, size: Vector3): () -> ()` registers a ladder, an oriented box, and returns the closure that removes it.
- `server:addPlatform(platform: Platform): () -> ()` registers a moving platform and returns the closure that removes it.
- `server:callPlatform(id: number)` starts a called platform's path from the next tick, and tells every joined player.
- `server:spectate(moderator: Player | Bot, target: Character?)` starts a moderator spectating a target's character, switches it, or with nil ends it. The game makes its own moderator check first, and parks the moderator's own character, which must exist. A target takes at most 31 watchers.
- `server:spectatorsOf(player: Player | Bot): { Player }` gives the moderators spectating a player.
- `server:viewersOf(target: Target): { Player }` gives the players currently sent a target, with the moderators spectating each of them, so a cue attached to it reaches every screen that shows it. Bots are left out.
- `server:reportShotNear(shooter: Player | Bot, viewer: Player | Bot)` tells Tread that a shooter's bullet passed near a viewer, which raises the rate the viewer is sent the shooter at, as `shotNear` sets.
- `server:addStage(name: string, after: string, run: (tick: number) -> ())` adds a game stage to every tick from the next, directly after the named stage. Tread's own stages are `decode`, `simulate`, `npcs`, `history`, `antiEsp` and `relay`. A stage runs under its own `pcall`, and an error is reported as `stage` with its name.
- `server:onReport(callback: (player: (Player | Bot)?, kind: string, measurement: number | string) -> ()): () -> ()` calls back on every report Tread raises ([Reports](#reports-for-a-cheat-score)).
- `server:onLanded(callback: (target: Target, speed: number, material: Enum.Material, apex: number) -> ()): () -> ()` calls back on every landing that counted, a character's or an NPC's, with the speed it met the ground at, the ground's material, `Enum.Material.Water` for a landing in water, and the fall's apex.
- `server:onTeleported(callback: (character: Character) -> ()): () -> ()` calls back once a teleport has set a character down.
- `server:stats(): { [string]: any }` gives Tread's aggregate numbers, with no endpoint and no signal, for the game to read about once a second. It holds no position and no name:
  - `seconds` since the last read, and `stages`, each stage's `last` and `p95` time over 10 s, in seconds;
  - as they stand: `players` (live characters), `npcs` (awake), `bodies`, `historyBytes`, and `trafficLargest` and `trafficP95`, the largest and the p95 of the bytes Volt sent each joined player and bot over the last second;
  - as their change since the last read: `ticks`, `dropped`, `standIns`, `late`, `recordsSent`, `recordsCut`, `bytesOut`, `antiEspTests`, `antiEspHidden`, `antiEspFailOpens`, and `reports` by kind.

The recording taps on the server handle are under [Recording taps and clip playback](#recording-taps-and-clip-playback).

### Characters, NPCs, sleepers and bodies

Every member errors on a handle that has ended, but for the `destroy` that follows a character's `die` or `sleep`, or an NPC's `die`.

- `character.player: Player | Bot` is who the character belongs to.
- `character:getState(): State` gives the state the last tick produced, the same table until the next tick refills it.
- `character:setMode(mode: MoveMode)` sets `"Walk"`, `"Noclip"`, which flies through everything, or `"Parked"`, which holds the body still and sends it to no other player. The game makes its own authority check first. Coming back to Walk runs depenetration, and a body no spot frees is reported as `stuck`.
- `character:teleport(at: CFrame)` is the one teleport function. It returns at once. Once the destination is ready or `teleport.timeout` passes, it sets the feet at `at`'s position, facing along its look, with velocity zeroed, the epoch moved on and queued commands dropped, then raises `onTeleported`. A second teleport replaces the first, and a death, a sleep or a destroy cancels it.
- `character:setDowned(downed: boolean)` puts the character in the Downed posture or takes it out. Out of it, the character crouches, and the step stands it up through its ceiling check.
- `character:setField(name: string, value: number | boolean)` sets one of the game's declared server-set fields, which the rules function reads and the owner's prediction gets. A name with no such declaration, a list or a group, or a value outside its declaration is refused.
- `character:setOutfit(outfit: Outfit)` sets the look, the game's declared slot-table fields. Each viewer gets it with the character's reveal and again on each change while it is sent the character.
- `character:setHeld(held: Held?)` sets the held item, the game's declared held-item fields, sent the way the look is; nil empties the hands.
- `character:setTeam(team: number?)` gives the character a team, nil for none. Two characters on the same team are always sent each other, and anti-ESP hides neither from the other. A new character starts with none.
- `character:setInvisible(invisible: boolean)` sends the character to no other player while on, teammates included.
- `character:sleep(): Sleeper?` turns the character into a sleeper in its slot, lying where it stands, with its slot, generation and look kept. Past the sleepers' share nothing changes: it returns nil and reports `sleep`.
- `character:die(push: Vector3?): Body` ends the character in a death. A body takes a slot of its own where it lies, wearing its look, and the death, with the attack's direction for the ragdoll's push, goes to each player sent the character, its own player and the moderators watching them. Nil gives no push.
- `character:destroy()` releases everything the character still holds. The game calls it on every death, respawn and leave, after `die` or `sleep`. A second call errors.
- `npc:command(command: Command)` issues the command the NPC steps from every tick while awake, and its levels repeat each tick. It reads the move axes, the button levels, the look, the lean, the head offset and `fields`, and derives the presses itself, so `number` and `pressed` go unread.
- `npc:setAwake(awake: boolean)` wakes or idles the NPC. An idle NPC takes no step and keeps its last history sample.
- `npc:getState(): State` gives its state, as a character's does.
- `npc:die(push: Vector3?): Body` and `npc:destroy()` end it, as a character's do.
- `sleeper:wake(player: Player | Bot): Character` wakes the sleeper as a character in the same slot, with its generation kept, so viewers see the same body stand up, through the ceiling check. The player must have no character, and a bot needs `bots.rtt`.
- `sleeper:moveTo(at: CFrame)` moves the sleeper to lie at `at`, keeping its slot and generation, and each viewer sent it draws the move as a fall.
- `sleeper:destroy()` removes the sleeper, as at a kill.
- `body:destroy()` removes the body.

### The client handle

- `client:getEye(): (Vector3, Vector3)` gives the cleared eye and the look, a unit vector, of whatever the client views: a playback, a spectated target, or its own body as drawn this frame. With none, it gives where the eye was last drawn, at first the origin looking along -Z.
- `client:getState(): State?` gives the local character's state as drawn this frame, the same table until the next call, or nil while it has no body.
- `client:getRenderTime(): number` gives the render time remote characters are drawn at, in relay ticks with its fraction, which a game stamps on a shot.
- `client:setRenderDistance(studs: number)` sets how far, in studs, this client draws characters and is sent them, as from a settings menu. It starts at the device class's `drawDistance`. The client sends it to the server over View once its handshake passes and again on each call, and the server holds it to `relevancy.leave`. The server drops the Views that come faster than `rates.view` allows, so a game calls this once the player applies the setting. It errors on anything that isn't a finite number above 0.
- `client:getMantle(): Vector3?` gives where the feet would end if jump were pressed now, or nil when a press would start no mantle, for the game's mantle prompt. It never throws.
- `client:showBody(part: "arms" | "chest" | "copy" | "rig", shown: boolean)` shows or hides part of the local player's own body on their screen: the first-person copy's arms, its chest or the whole copy, or with `"rig"` the world rig other players see, for a camera that leaves the eye. The copy's parts start shown and the rig hidden, and each setting holds from one body to the next. While the client spectates, the target's world rig takes the `"rig"` setting. It errors on any other part, or a `shown` that isn't a boolean.
- `client:addLadder(cframe: CFrame, size: Vector3): () -> ()` registers a ladder for the owner's prediction, as the server registers the same one.
- `client:addPlatform(platform: Platform): () -> ()` registers a moving platform for the owner's prediction and this screen, as the server registers the same one. Tread moves its `model`, if it has one, every frame. It refuses what the server's refuses, and a model part with CanCollide on.
- `client:onCorrected(callback: (size: number, flagged: boolean) -> ()): () -> ()` calls back on every replay of the owner's prediction, with the correction's size in studs and whether grounded, posture, mode or the ridden platform flipped.
- `client:onMarker(callback: (slot: Slot, marker: string, value: string) -> ()): () -> ()` calls back on every animation marker a drawn rig's track reaches, a playback's rigs included.
- `client:onFootstep(callback: (step: Footstep) -> ()): () -> ()` calls back on each step the viewer can hear from an enemy culled from it, which the server sends in place of the enemy's record. A sent enemy's steps come from its animation markers through `onMarker`.
- `client:onSpawned(callback: (slot: Slot, rig: Model) -> ()): () -> ()` calls back when a slot's rig is drawn: a character, sleeper or body revealed, the owner's own body started, a spectated target's first feed, or a dying rig turned into its body.
- `client:onDespawned(callback: (slot: Slot) -> ()): () -> ()` calls back when a slot's rig is put away.

`client:play` is under [Recording taps and clip playback](#recording-taps-and-clip-playback).

### Hooks in the shared table and the settings

These are the functions a game passes in, which Tread calls.

- `collision.ray(origin: Vector3, direction: Vector3): Hit?` casts a ray against the game's world.
- `collision.sweep(center: Vector3, size: Vector3, direction: Vector3): Hit?` sweeps an axis-aligned box.
- `collision.rest(center: Vector3, size: Vector3): number?` gives the height a box rests at, or nil over nothing.
- `collision.sphere(center: Vector3, radius: number, direction: Vector3): Hit?` sweeps a sphere.
- `water(x: number, z: number): number?` gives the water surface's height at a point, or nil for none.
- `rules(step: RuleStep, allow: Allow): number` is the game's movement rules ([The rules function](#the-rules-function)).
- `beforeCommand(character: Character, command: Command)`, on the server, runs before each command is simulated. The owner's prediction never calls it.
- `prestream(player: Player, at: CFrame): any`, on the server, prepares a teleport's destination and returns a Promise that resolves when it is ready, which Tread waits on with `andThen`. Without it, Tread streams the destination in with `RequestStreamAroundAsync`, giving up after `teleport.timeout`. A hook that throws or rejects is warned, and the destination counts as ready.
- `sample(command: Command)`, on the client, fills the command Tread is about to send with this tick's input, once a simulation tick ([Input](#input)).
- `look(): (number, number, number, number)`, on the client, gives this frame's base yaw and pitch in radians and head offset yaw and pitch in degrees, once a frame.
- `dress(rig: Model, outfit: Outfit, copy: boolean)`, on the client, puts a slot's look on a rig from the pool. `copy` is true for the first-person copy.
- `undress(rig: Model)`, on the client, takes the look off before the rig goes back to the pool.
- `hold(rig: Model, held: Held?)`, on the client, attaches the held item the held-item fields name, or clears the hands with nil.

The client runs `dress`, `undress` and `hold` each under its own `xpcall`, so a throwing hook leaves that slot undrawn and the rest drawn.

### Types

The root re-exports every public type under its own name.

- `Shared`, `ServerSettings` and `ClientSettings` are the three tables under [Configuration](#configuration).
- `Server`, `Client` and `Playback` are the handles. `Character`, `Npc`, `Sleeper` and `Body` are the server's handles for each kind of body, and `Target` is `Character | Npc | Sleeper`.
- `Bot` is Volt's bot, `{ Name: string }`.
- `State` is a body's public state: `root: Vector3` (the feet, the hull's bottom center), `facing: number` (radians, along -Z at 0), `velocity: Vector3`, `grounded: boolean`, `groundNormal: Vector3` (zero off the ground), `groundMaterial: Enum.Material`, `mode: Mode`, `posture: Posture`, `moveMode: MoveMode`, `eye: Vector3` (the cleared eye), `look: Vector3`, `hullCenter: Vector3`, `standingBox: Box`, `lyingBox: Box`, `apex: number`, `platform: number` (the ridden platform's id, 0 for none) and `epoch: number`.
- `Box` is `{ cframe: CFrame, size: Vector3 }`. `standingBox` is the hull as it stands, crouched for a crouched, downed or swimming body, and `lyingBox` is `step.lyingBox` along the facing. Both are filled at every posture.
- `Mode` is `"Ground" | "Air" | "Swim" | "Ladder" | "Mantle" | "Slide"`, `Posture` is `"Stand" | "Crouch" | "Downed"`, and `MoveMode` is `"Walk" | "Noclip" | "Parked"`. `"Slide"` is the crouch slide's mode, which only a game that gives `step.slide` ever sees.
- `Command` is `number` (a u16), `forward` and `right` (each -1 to 1), `jump`, `crouch`, `sprint` and `aim` (the button levels), `pressed` (`{ jump, crouch, sprint, aim }`, the presses Tread derives from the levels), `yaw` and `pitch` (the base look, radians), `lean` (degrees), `headYaw` and `headPitch` (the head offset, degrees), and `fields`, the game's declared command fields by name.
- `RuleStep` is `command: Command`, `pressed`, `grounded: boolean`, `mode: Mode`, `posture: Posture`, `airTicks` and `groundTicks` (Tread's timers), `fields` (the server-set fields), `held` (the held-item fields), `block` (the rule-state block, which the rules function may write) and `isNpc: boolean`. `Allow` is `{ jump: boolean, sprint: boolean, crouch: boolean, stand: boolean, slide: boolean }`. `slide` gates only a crouch slide's start, and Tread leaves it false while the shared table gives no `step.slide`.
- `Hit` is `{ distance: number, position: Vector3, normal: Vector3, material: Enum.Material, instance: Instance? }`, where `distance` is the cast's travel to the hit, as `RaycastResult.Distance` gives it.
- `Sample` is `{ epoch: number, position: Vector3, yaw: number, posture: Posture, body: Shape, zones: { [string]: Shape } }`, the posture's hit shapes placed in the world. `Shape` is `{ from: Vector3, to: Vector3, radius: number }`, a capsule.
- `Platform` is `{ id: number, boxes: { { center: Vector3, size: Vector3 } }, path: (tick: number, calledAt: number?) -> Vector3, model: Model? }`. `id` is 1 to 127 and the same on both realms, and each box sits in the platform's own space. `path` is a pure function giving the platform's position at a server simulation tick, counted from the server's start, and for a called platform from the tick of its last call, `calledAt`, nil before any. Platforms translate only. `model` is the client's copy.
- `Field` is `{ name, type, bits, min, max, count, kind, start, fields, optional }`, and `Fields` is `{ command, rules, server, slot, held }`, each a list of `Field` ([Declared fields](#declared-fields)).
- `Outfit` and `Held` are `{ [string]: any }`, the game's slot-table and held-item fields by name.
- `Slot` is `{ id: number, kind: "Player" | "Npc" | "Sleeper" | "Body", player: Player?, withheld: boolean }`, one table per drawn slot from its spawn to its despawn. `player` is set for a live player's slot. `kind` changes in place, as when a player falls asleep. While the client spectates, `withheld` says whether the slot is sent only because anti-ESP withheld it from the target.
- `Footstep` is `{ at: Vector3, kind: "Walk" | "Sprint" | "Jump" | "Land", material: Enum.Material }`, a culled enemy's step at the exact position where it fell, with no player named.
- `Sink` is `(tick: number, records: buffer) -> ()`, a tap's callback.
- `Change` is one change to the state a snapshot holds, tagged by `kind`, each with its `slot`: `"slot"` with `previous` and `current` a slot entry or nil for a free slot; `"look"` and `"held"` with `previous` and `current` the packed bytes, an empty buffer for none; and `"death"` with `previous` nil and `current` a death. A slot entry is `{ generation: number, kind, rig: "A" | "B", look: buffer, held: buffer }` and names no player. A death is `{ character: number, body: number, push: Vector3 }`, each id the slot plus the generation × 4,096. The root doesn't export the slot entry and the death by name.

### Recording taps and clip playback

The taps let a game record moderator clips. With nothing connected, each tap point costs one flag check. A sink is called every relay tick after the relay stage's flush, with the unwrapped relay tick and a frame in a new buffer the sink may keep. Each sink and callback runs under its own `xpcall` and must not yield, and a viewer who leaves has its sinks dropped.

- `server:observe(viewer: Player | Bot, sink: Sink): () -> ()` calls the sink with a frame of every block the relay sent the viewer that tick, each record with its send reason, and the viewer's OwnerState while it owns a character, with its view lag and the looks it stepped since the last frame. A spectating moderator's frames hold the copies of its target's blocks. The reasons are `"Clear"`, `"Hold"`, `"FailOpen"`, `"Teammate"`, `"Npc"`, `"Hidden"` and `"Untested"`.
- `server:observeWithheld(viewer: Player | Bot, sink: Sink): () -> ()` calls the sink with a frame of the withheld blocks the relay sent the moderators spectating the viewer: the players anti-ESP held back from it, never an Invisible or Parked one. While no moderator spectates the viewer, each frame holds no block.
- `server:keyframe(viewer: Player | Bot): buffer` gives everything the viewer is sent now, self-contained, each character with its look and held item, and the latest call of every called platform. A clip starts from one.
- `server:snapshot(): buffer` gives every taken slot with its generation, kind, rig mode, look and held item, the whole state `onReliable` reports changes to.
- `server:onCommand(callback: (character: Character, tick: number, command: Command, isStandIn: boolean, state: State) -> ()): () -> ()` calls back with every command a player's or bot's character steps, stand-ins included, with the simulation tick it ran on, the base look at full precision and the state the step produced. NPCs are left out. The command and the state are valid during the call.
- `server:onReliable(callback: (change: Change) -> ()): () -> ()` calls back with every change to the state a snapshot holds: a slot taken, changed or freed, a look or a held item within a life, and a death.
- `Tread.decode(Tread.CODEC_VERSION, "tap", frame)` reads a sink's frame as `{ tick, blocks, owner }`, each block with its `records`, and `"keyframe"` and `"snapshot"` read the other two.
- `client:play(ticks: { buffer }, withheld: { buffer }?): Playback` plays a clip: its keyframe first, then the observed frames from the keyframe's tick on, oldest first, and optionally the withheld frames over the same ticks.
- `playback:render(time: number)` draws the clip at once as it stood `time` seconds after its keyframe, clamped to the clip. Each render depends on its time alone, so play, pause, single steps, slow motion and seeks are the caller's. Forward play raises the footsteps it passes. It errors on a time that isn't finite, and after `destroy`.
- `playback:destroy()` ends the playback and draws the live characters again. A second call errors.

A clip is the taps' own output. The observed viewer is the clip's target, and its keyframe is taken inside the first sink call, so the keyframe and that tick's frame hold the same view:

```lua
local ticks: { buffer } = {}
local withheld: { buffer } = {}

local stopObserving: () -> () = tread:observe(target, function (_: number, frame: buffer)
	if #ticks == 0 then
		table.insert(ticks, tread:keyframe(target))
	end

	table.insert(ticks, frame)
end)

-- A tick's withheld sink runs after its observe sink, so each keeps the tick an observed frame just kept
local stopWithholding: () -> () = tread:observeWithheld(target, function (_: number, frame: buffer)
	if #withheld < #ticks - 1 then
		table.insert(withheld, frame)
	end
end)
```

On the client, render each frame before the camera reads the eye:

```lua
local playback: Tread.Playback = tread:play(clip.ticks, clip.withheld)
local elapsed: number = 0

RunService:BindToRenderStep("ClipReplay", Enum.RenderPriority.Camera.Value, function (deltaTime: number)
	elapsed += deltaTime
	playback:render(elapsed)

	local eye: Vector3, look: Vector3 = tread:getEye()
	Camera.CFrame = CFrame.lookAlong(eye, look)
end)
```

While a playback runs:

- `play` errors, changing nothing, on a second playback, a first buffer that isn't a keyframe of this `CODEC_VERSION`, field declarations that hash other than the client's, frames out of order or before the keyframe, and a withheld frame with an OwnerState or a reveal, hide or footstep entry.
- Every live rig goes back to the pool. The clip's rigs come from the same pool and raise `onSpawned` and `onDespawned` with slots that name no player, and their markers reach `onMarker`.
- `getEye()` gives the playback's eye and look, while `getState()` and `getRenderTime()` stay live, and prediction and the live characters carry on unseen.
- A death shows as the dying rig's hide and the body's lying reveal, with no ragdoll.
- After `destroy`, a body that a live death laid down before `play` stays undrawn until its own next reveal.

To mark the slots the target's client was never sent, decode the withheld frames:

```lua
local slots: { number } = {}

local frame: { [string]: any } = Tread.decode(Tread.CODEC_VERSION, "tap", clip.withheld[index])
for _, block: { [string]: any } in frame.blocks do
	for _, record: { [string]: any } in block.records do
		table.insert(slots, record.slot)
	end
end
```

## What a game supplies

### The rig

Tread ships no rig. `rig` is the game's template: any R15 Model with AnimationConstraint joints, Roblox's own R15 rig as the Rig Builder makes it included. The template must be Archivable and have a PrimaryPart, its root. Tread never changes the game's model. It clones it once and readies the clone, removing every Humanoid, script, BallSocketConstraint and NoCollisionConstraint, turning off CanCollide, CanQuery and CanTouch on every part, anchoring the root alone, and adding an AnimationController with an Animator.

`joints` names, for each of the 15 logical joints, the AnimationConstraint that is that joint in the rig, found anywhere under it and joining two parts by its attachments: `Root`, `Waist`, `Neck`, `LeftShoulder`, `LeftElbow`, `LeftWrist`, `RightShoulder`, `RightElbow`, `RightWrist`, `LeftHip`, `LeftKnee`, `LeftAnkle`, `RightHip`, `RightKnee` and `RightAnkle`.

The rig has no Humanoid, so Shirt, Pants, BodyColors and `Humanoid:AddAccessory` don't work on it, and the game's `dress` hook welds each piece of a look by hand. The first-person copy is dressed with `copy` true, so the game can leave off what the copy never shows, such as the head. Each client attaches the held item to its own copy of the rig in `hold`.

### Animations

`animations` gives one Animation for each state Tread plays: `idle`, `walk`, `sprint`, `crouchIdle`, `crouchWalk`, `jump`, `fall`, `land`, `swimIdle`, `swim`, `climb`, `mantle`, `downed` and `crawl`, and `slide` too when the shared table gives `step.slide`. A body in the `Slide` mode plays `slide` whatever its speed. Tread owns the Animator, the track played for each state, animation level of detail and the joints' `Transform` writes. A track's markers reach the game through `client:onMarker`.

### Input

`sample(command)` runs once a simulation tick and fills the command Tread is about to send:

- `forward` and `right`, the move axes. Keep their length at most 1, since Tread reports a longer move input as `moveTamper`, so scale a diagonal back.
- `jump`, `crouch`, `sprint` and `aim` as levels, whether each button is held. Tread derives the presses from them, so a lost packet neither adds a press nor swallows one.
- `yaw` and `pitch`, the base look in radians, and `lean` in degrees.
- `headYaw` and `headPitch`, the head offset in degrees. Tread clamps it to `step.headCone`.
- `command.fields`, the game's declared command fields.

Tread reuses the command table, its lists included, so the hook allocates nothing. `look()` runs once a frame and returns the same base yaw and pitch and head offset, so the drawn eye turns with the camera between ticks.

### Collision and water

The shared table carries either the game's four collision functions or none of them and an include list for engine casts. They take and return plain numbers and `Vector3`s only, and a `Hit` carries `distance` beside the position, normal, material and an optional instance, since a box sweep's contact point can't give its travel. Simulation casts should meet only the game's collision geometry. `water(x, z)` gives the water surface's height at a point, or nil, and both realms must get the same answers from every one of these functions.

Ladders and moving platforms register on both realms with `addLadder` and `addPlatform`, so the owner's prediction sees what the server sees. Each returns the closure that removes it.

### The rules function

A game's movement rules run inside the step, on the server and in the owner's prediction. Tread fills `allow` with what its own physics permits, such as a jump only on the ground. The function returns the speed cap, which the stance speed never passes, sets an entry of `allow` false to refuse it, or sets `allow.jump` true for a jump its own rules permit, such as coyote time. It may write its rule-state block, `step.block`, which the owner reconciles with the rest of the state. It allocates nothing, never yields and reads no live game state, though static tables such as item definitions are fine. On the owner's client, the held-item fields are the ones the server last reconciled.

```lua
--[[
    The game's movement rules, run inside Tread's step on the server and in
    the owner's prediction: the jump cooldown, and a downed crawl that
    stops while someone revives the body
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local CRAWL_SPEED: number = require(ReplicatedStorage.Shared.Config.Movement).crawlSpeed
local JUMP_COOLDOWN: number = require(ReplicatedStorage.Shared.Config.Movement).jumpCooldownSeconds
local SIMULATION_RATE: number = require(ReplicatedStorage.Shared.Config.Tread).rates.simulation

local JUMP_COOLDOWN_TICKS: number = math.round(JUMP_COOLDOWN * SIMULATION_RATE)

return function (step: Tread.RuleStep, allow: Tread.Allow): number
	local block: { [string]: number } = step.block

	if block.sinceJump < JUMP_COOLDOWN_TICKS then
		block.sinceJump += 1
	end

	-- A downed body only crawls, and not at all while someone revives it
	if step.posture == "Downed" then
		allow.jump = false
		allow.sprint = false
		allow.crouch = false
		allow.stand = false

		return step.fields.beingRevived and 0 or CRAWL_SPEED
	end

	allow.jump = allow.jump and block.sinceJump >= JUMP_COOLDOWN_TICKS
	if allow.jump and step.pressed.jump then
		block.sinceJump = 0
	end

	return math.huge
end
```

`sinceJump` is a rule-state field and `beingRevived` a server-set field the game declares.

### The crouch slide

A game turns the crouch slide on by giving `step.slide` in the shared table. Without it nothing slides, `allow.slide` stays false, and the step runs exactly as before.

A slide starts on a ground tick when crouch is pressed, or on the first ground tick after the air while crouch is held. The body must be walking, not downed, on walkable ground and outside the cooldown, and it must carry at least `step.slide.start` studs/s across the ground into the tick. The rules function must leave both `allow.slide` and `allow.crouch` true. The slide keeps the body's direction and adds `boost` to its speed. The body stays grounded and crouched throughout, so it takes the crouched hull, eye and hit shapes, and its mode reads `"Slide"` in `RuleStep` and in `State`. Its facing still follows the look, so the player can look around while it slides.

Each tick of a slide runs in this order:

1. A jump press first tries a mantle, as it does on the ground, and otherwise jumps. The body leaves with its horizontal velocity held to `max`.
2. Letting go of crouch or pressing sprint hands the tick to the walk, and the posture follows the usual stand rule.
3. The slope adds `slope` times gravity's share along the ground, so a downhill speeds the slide up and an uphill slows it.
4. Friction takes `friction` studs/s off its speed each second.
5. Its direction turns toward the move input by at most `steer` degrees a second, and its speed stays the same.
6. Its speed is held to `max`. The rules function's speed cap doesn't bound a slide.
7. The body moves through the walk's own collide-and-slide, step-up and ground snap, so a wall stops a slide as it stops a walk.

A slide ends crouched on the ground once its speed falls below `stop`, or on footing too steep to walk. Going down, a move mode change, entering water, mounting a ladder and starting a mantle end it too, and every one of these ends starts the cooldown, `cooldown` seconds counted in whole ticks. Leaving the ground with no jump turns the slide into a fall that starts no cooldown, so a body that lands with crouch held and enough speed slides on. A teleport ends a slide as it ends a mantle, dropping the body into the air.

With Frontier Zero's speeds and the dev place's slide (start 15, boost 0, friction 6, slope 0.5, max 27, stop 6, steer 60 and cooldown 2), only a sprint starts one. On flat ground a slide from a sprint runs from 18 to below 6 studs/s in 41 ticks at 20 Hz and covers about 24 studs. A 10° downhill holds its speed within half a stud a second, and a 25° downhill reaches the top speed. On a 30° downhill the walk's ground snap loses the ground at about 25 studs/s, so the body leaves it before the top speed.

### Declared fields

Each Move command carries Tread's own movement plus the game's declared fields, and Tread packs, repeats and stands in for them without reading them. The declarations sit in the shared table under `fields`, five lists of `Field`:

- `command`: the Move's fields, such as a held hotbar slot or the shots fired.
- `rules`: the rule-state block, which the rules function writes.
- `server`: fields the server sets with `character:setField`, such as being revived.
- `slot`: the look, which `setOutfit` sets and `dress` reads.
- `held`: the held item, which `setHeld` sets and `hold` reads.

A `Field` is `{ name, type, bits, min, max, count, kind, start, fields, optional }`:

- `type` is `"uint"`, `"int"`, `"bool"` or `"group"`. A number needs `bits`, its width from 1 to 32, and `min` and `max` may narrow its range inside that width. A bool or a group takes none of the three.
- `count` makes the field a list of at most that many, its length packed in front. A `"group"` lists its own `fields`.
- `kind` is required on a command field, and only a command field takes one. A `"held"` field is a level a stand-in repeats. A `"carried"` field is a press, one `"bool"` or one `"uint"`, which carries from a command the server discards for arriving late into the next real command, merged by OR or by addition, and never into a stand-in. A `"dropped"` field, such as a shot, never repeats and is lost with a discarded command, which is reported as `lateShot`.
- `start` is a rule-state or server-set field's value when a character is built, on a single number or bool. Without it, a field starts at false, the number nearest 0 its range holds, an empty list, or a group of those.
- `optional = true` packs a slot-table or held-item field behind a presence bit.

Each block has a byte bound, which start checks against the declarations' largest packing: 64 B for a command's fields, 16 B for the server-set fields, 32 B for the rule-state block, 64 B for the look and 16 B for the held item. Tread's decoder checks every declared field's width, range and list count as it reads, and refuses the whole Move, reported as `schema` with the index of the first field that failed, so an out-of-range field never reaches the step or the game. Lean and the head offset are Tread's own command fields, so a game declares neither.

The declarations in the module the shared table reads them from, with the cast that keeps their strings typed:

```lua
fields = {
	command = {
		{ name = "slot", kind = "held", type = "uint", bits = 3, max = 6 },
	},

	rules = {
		{ name = "sinceJump", type = "uint", bits = 4, start = 0 },
	},

	server = {
		{ name = "beingRevived", type = "bool", start = false },
	},

	slot = {
		{ name = "shirt", type = "uint", bits = 16, optional = true },
		{ name = "pants", type = "uint", bits = 16, optional = true },
	},

	held = {
		{ name = "item", type = "uint", bits = 16, optional = true },
	},
} :: Tread.Fields,
```

### The lifecycle

The game decides when a character spawns, dies, goes down, respawns or becomes a sleeper, and Tread carries out each transition it asks for:

- Construction is `server:create(player, at)`, and NPCs are `server:createNpc(at)`.
- A death is `character:die(push)`, and the game removes the body later with `body:destroy()`.
- Downed is `character:setDowned(true)`, and the game's own server-set field tells the rules function when a reviver is at work.
- A sleep is `character:sleep()`. A sleep or a boot rebuild past the sleeper limit returns nil and is reported as `sleep`, and what becomes of that body is the game's to decide.
- Every path that moves a player goes through `character:teleport(at)`, and every change of move mode through `character:setMode`, each after the game's own authority check.
- The game calls `character:destroy()` on leave, and after `die` or `sleep`, which hand the slot to the body or the sleeper. A player who leaves before the game destroys its character stops being sent anything, while the character steps on stand-ins until `destroy`.
- Each character, NPC, sleeper and body takes one of 4,096 slots, and `slots.reserve` holds slots back from sleepers for the rest.

## Networking

Tread handles its own networking under its own Volt scope, `Tread`. The repo compiles its schema, and the generated server and client modules ship inside the package, each required only inside its own realm's start call, so requiring Tread loads no Volt module and a client never runs the server's.

- A game never binds Tread's endpoints, and never puts Tread's namespace in its own Network or in the Network it passes to `Oak.start`. No game service or controller owns it.
- The server hears two endpoints, Move and View, and applies their rates from `rates.move` and `rates.view` through its own generated module.
- View carries a client's render distance in whole studs, rounded up and held to 1 to 65,535. The client sends it once its handshake passes and again on each `client:setRenderDistance`, and it goes out with the client's next flush, which follows its next Move. The server keeps each connection's distance, held to `relevancy.leave`, until the connection leaves, and a connection that never sends one, every bot included, keeps `relevancy.leave`. Each viewer is sent, and anti-ESP tests, only the characters inside its own distance; NPCs and sleepers go no farther than the lesser of it and `npcs.range` or `sleepers.radius`. A spectating moderator gets the target's view, which follows the target's distance.
- Tread handles its own Volt failures, so they never reach the game, and reports each one through `server:onReport`.
- The server sends a hash of the shared table in its handshake. Until the hash matches, the client reads no relay block and no OwnerState. On a mismatch it stops for good, warns with both hashes and kicks the local player with them.
- Volt counts each player's bytes across scopes, so Tread's traffic counts toward any per-player budget the game sets on its own scope. Tread's own `budget` settings cover a viewer's downstream across every Volt stream.

### Reports for a cheat score

Tread keeps no cheat score and punishes nothing. It reports each event through `server:onReport(callback)`, with the player or bot the event is about, nil for an NPC or the server itself, the kind, and a measurement.

| Kind | When | Measurement |
|---|---|---|
| `moveTamper` | A later copy of a command differs from the first copy received, or a move input is longer than 1 beyond rounding. | The command number. |
| `schema` | Tread's decoder refuses a Move on a declared field, or Volt's decode refuses a Move or a View. | The index of the first field that failed, or Volt's detail. |
| `rate` | Volt's rate limit refuses a Move or a View. | Volt's detail. |
| `gap` | A gap in a player's movement stream ends. | Its length in seconds. |
| `late` | A command arrives after its tick ran with a stand-in, and is discarded. | The ticks late. |
| `standIn` | The server steps a stand-in. | The stand-ins in a row. |
| `lateShot` | Dropped-kind presses are lost with a discarded command. | How many were lost. |
| `ahead` | A command more than `ticks.ahead` ahead is dropped. | The ticks ahead. |
| `band` | A shot's claimed render time falls outside the band, and the shot is re-timed. | The claim's offset from the expected render time, in relay ticks. |
| `stuck` | Depenetration finds no clear spot for a body. | The depth in studs. |
| `sleep` | A sleep or a boot rebuild is refused past the sleeper limit. | The sleepers held. |
| `stage` | A stage, a game stage or one body's step errors. | The stage's name. |
| `packet`, `handshake`, `listener`, `handler`, `outgoing`, `queue`, `departed` | Volt's other failures on Tread's scope, under Volt's own kind names. | Volt's detail. |

A create that finds no slot free errors instead, naming the held-back count.

## Working on Tread

The tools are pinned in `rokit.toml`, and Volt is a dev dependency, installed under `DevPackages/`.

```sh
rokit install      # rojo, wally, StyLua, selene, wally-package-types, lune, luau-lsp and the volt compiler
wally install      # Promise, and Volt under DevPackages/
lune run volt      # copies Volt's runtime into .volt/src, where the dev place and the tests read it
lune run tests     # the Lune suite in tests/
lune run format    # StyLua over the repo
```

CI also lints `src` with selene, analyzes it with luau-lsp's new type checker, and runs `volt --check` on `Schemas/Tread.volt` and `dev/Schemas/Dev.volt`, which fails while the committed modules in `src/Network/` and `dev/Network/` differ from what the schemas compile to. Volt writes those folders, so they are never edited by hand.

The dev place, place 77473372042446, runs `dev/`, a small game that starts Tread the way a game does, with the bot harness, test fixtures and an exploit kit for playing as a cheater. Serve it with `rojo serve dev.project.json`, on port 34877. It needs Roblox's R15 rig from the Rig Builder at `ReplicatedStorage.DevRig`, and `StreamingIntegrityMode` and `UseFixedSimulation` set by hand, as under [Place settings](#place-settings).

To run a scenario in a Play session, set the string attribute `Scenario` on `ServerScriptService.Server` to the name of a module in `dev/Server/Scenarios`. The scenario runs inside the dev game's own modules, and the Runner prints `Runner PASS` or `Runner FAIL` with its report.

## License

Tread is licensed under the Apache License 2.0. The full text is in `LICENSE`.
