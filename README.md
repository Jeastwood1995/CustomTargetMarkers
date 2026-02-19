# CustomTargetMarkers

A World of Warcraft Classic addon that displays a raid target icon picker
directly above an enemy's nameplate the moment you target them — no need to open
any menus.

---

## Features

- **Instant popup on target** — As soon as you target a hostile enemy, a compact
  icon bar appears above their nameplate.
- **All 8 raid markers** — Star, Circle, Diamond, Triangle, Moon, Square, Cross,
  and Skull are all available in a single click.
- **Smart positioning** — The popup anchors itself above the enemy's nameplate
  and tracks it as they move. If the nameplate is off-screen, it falls back to
  above the default TargetFrame.
- **Active marker highlight** — Whichever marker is already set on the target is
  visually highlighted so you always know the current state at a glance.
- **Clear button** — A dedicated button lets you remove an existing marker from
  the target instantly.
- **Hostile-only display** — The popup only appears for enemies, keeping your UI
  clean when targeting friendly NPCs or players.
- **Toggle command** — Use `/ctm` in chat to enable or disable the addon at any
  time without reloading.

---

## Compatibility

| Version                        | Interface |
| ------------------------------ | --------- |
| Classic Era                    | 1.15.x    |
| Burning Crusade Classic        | 2.5.x     |
| Wrath of the Lich King Classic | 3.4.x     |
| Cataclysm Classic              | 4.4.x     |

---

## Installation

1. Download or clone this repository.
2. Copy the `CustomTargetMarkers/` folder into your addons directory:
   ```
   World of Warcraft/_classic_/Interface/AddOns/
   ```
3. Launch the game and enable **CustomTargetMarkers** on the character select
   screen.

---

## Usage

| Action                 | Result                                      |
| ---------------------- | ------------------------------------------- |
| Target a hostile enemy | Icon picker appears above their nameplate   |
| Click an icon          | Applies that raid marker to the target      |
| Click the clear button | Removes any existing marker from the target |
| `/ctm`                 | Toggles the addon on or off                 |

---

## How It Works

The addon listens to the `PLAYER_TARGET_CHANGED` event and checks whether the
new target is a hostile unit. If so, it anchors a custom frame above the unit's
nameplate using `C_NamePlate.GetNamePlateForUnit`. A lightweight `OnUpdate` tick
keeps the frame tracking the nameplate as it moves across the screen. The
`RAID_TARGET_UPDATE` event keeps the active-marker highlight in sync in real
time.
```

