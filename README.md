# Tread

Tread is Whiteoak Studios' custom character controller for Roblox. It replaces the default Roblox character with server-authoritative movement, client prediction and reconciliation, kinematic collision, replication to other players with per-viewer relevancy and anti-ESP, a lag-compensation history, and client-built rigs with first person. It is built for 150-player servers and beyond.

A game hooks into Tread and keeps its own lifecycle logic, such as spawn, death, respawn, downed and sleepers. Everything game-specific is configuration the game supplies. Frontier Zero is the first game built on it.

Tread is a Wally package, `fadeluc-123/tread`, published publicly under the Apache-2.0 license.

## Status

Design phase. There is no code yet.

## Knowledge base

The design, the plans, the research and the rules live in an Obsidian vault at `KB/` in the project folder, with `KB/Core.md` as the hub. The vault is gitignored, so it stays in the project folder and is not part of this repo.
