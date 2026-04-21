# Platformer

A 2D tile-based platformer built in Lua with the [LÖVE 2D](https://love2d.org) game engine. Supports single-player and LAN multiplayer for up to 8 players.

## Features

- 8 levels across 2 worlds with distinct visual themes
- Smooth platforming: coyote time, jump buffering, variable jump height
- Stomp-based combat (PvP and enemies)
- Coin collection and scoring
- Particle effects for death and coin pickups
- LAN multiplayer with host-authoritative networking (up to 8 players)
- Procedurally drawn graphics — no external assets required

## Requirements

- [LÖVE 11.4](https://love2d.org) — ENet (multiplayer) is bundled with this version

## Running

```bash
love /path/to/platformer
# or from within the project directory:
love .
```

## Controls

### Menu

| Key | Action |
|-----|--------|
| `S` | Solo play |
| `H` | Host multiplayer (LAN, port 6789) |
| `J` | Join game (enter host IP) |
| `ESC` | Quit |

### In-Game

| Key | Action |
|-----|--------|
| `Left` / `A` | Move left |
| `Right` / `D` | Move right |
| `Space` / `Up` / `W` | Jump |
| `Left Shift` | Run |
| `R` | Restart |
| `ESC` | Return to menu |

## Multiplayer

The host runs the full simulation. Clients send inputs each frame; the host broadcasts game state at 20 Hz. LAN discovery uses UDP on port 6790.

## Project Structure

| File | Purpose |
|------|---------|
| `main.lua` | Game loop, state management, menu/lobby UI |
| `player.lua` | Physics, input, collision, animation |
| `world.lua` | Tile grid and AABB collision detection |
| `levels.lua` | All 8 level definitions |
| `enemy.lua` | Patrol AI and stomp detection |
| `camera.lua` | Smooth camera following active players |
| `network.lua` | ENet host/client networking |
| `particles.lua` | Particle system for visual effects |
| `conf.lua` | LÖVE window configuration |

## Levels

| World | Level | Name |
|-------|-------|------|
| 1 | 1 | Green Hills |
| 1 | 2 | Step Up |
| 1 | 3 | Mind the Gap |
| 1 | 4 | Spike Run |
| 2 | 1 | Sky Land |
| 2 | 2 | Storm Clouds |
| 2 | 3 | Spike Gauntlet |
| 2 | 4 | Final Chaos |
