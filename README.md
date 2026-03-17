# Infectious

Apocalyptic zombie mod for Luanti. Aggressive zombies roam the night, infect animalia mobs, and spread the horde. Fight back or watch the world fall.

## Features

- **Humanoid zombie** using the player character model with a dark, bloody skin
- **17 zombified animals** — every animalia mob has an infected variant with darkened red-tinted textures and red eyes
- **Infection mechanic** — 30% chance on each hit to zombify the target mob, replacing it with a hostile infected version
- **Zombies attack everything** — players (non-creative) and all non-zombie entities
- **Night/dark spawning only** — zombies spawn naturally where light level is 7 or lower
- **Sunlight immune** — once spawned, they don't burn in daylight
- **Manual HP system** — proper death with blood splatter particles and loot drops
- **Spawn egg** for testing and creative use

## Zombie Stats

| Type | HP | Damage | Speed |
|------|-----|--------|-------|
| Humanoid Zombie | 30 | 6 | 4.5 |
| Infected Animal | 25 | 5 | 5.0 |

## Zombified Animals

Cow, pig, sheep, chicken, wolf, fox, grizzly bear, horse, cat, turkey, reindeer, opossum, rat, bat, frog, owl, song bird.

## Drops

- Dirt (always)
- Steel ingot (1 in 5 chance)
- Diamond (1 in 20 chance)

## Commands

```
/giveme infectious:spawn_egg     -- get a spawn egg
/time 0:00                       -- set midnight for spawning
/set time_speed 0                -- freeze time at night
/clearobjects                    -- remove all entities
```

Creative mode players are ignored by zombies — useful for testing.

## Dependencies

- `default` (Minetest Game)
- `animalia` (animal mobs)
- `creatura` (mob framework)

## License

- Code: MIT
- Textures: CC BY-SA 4.0
