> **Archived (2026-11-10).** Upstream **Transmogify 5.5.1** ships its own fixes for the weapon-catalog and prefab-loading problems described below, so this patch is no longer needed. The code stays here for reference and for anyone still on 5.4.0. The Nexus page for this patch has been taken down.

# Transmogify 鈥?Weapon Catalog Fix + Path Cache (unofficial)

Unofficial local fixes for **Transmogify v5.4.0** (Dragon's Dogma 2, REFramework) that make it survive the
post鈥揇ark Arisen game builds.

This repository contains **only two Lua files** that replace the ones shipped in the mod archive:

```
reframework/autorun/Transmogify.lua
reframework/autorun/_TransmogifyUtils/utils.lua
```

It does **not** include the mod's `YowaveUtils.dll`, fonts, images or any other asset 鈥?install those from the
original mod: <https://www.nexusmods.com/dragonsdogma2/mods/420>

---

## Symptoms this fixes

1. The mod window stays on `Initializing Transmogify...` / `Preparing weapon appearances` forever.
2. It sometimes gets stuck exactly while preparing weapon appearances, and never finishes.

## Root causes found

### 1. `AddWeapons()` builds from an empty weapon catalog (hard error, no retry)

`AddWeapons()` reads `app.EquipmentManager.WeaponCatalog` when the mod initialises. On a fresh launch that
dictionary is **still empty** (the game has not populated item data yet). With an empty catalog:

* `new_count` stays `0` 鈫?`CATEGORY_ITEM_LIST[CAT_WEAPON]` is never created
* the tail of the function calls `table.sort(CATEGORY_ITEM_LIST[CAT_WEAPON])` on `nil`
  鈫?`bad argument #1 to 'sort' (table expected, got nil)`
* the exception kills the `Init` coroutine, and nothing ever retries 鈫?the mod sits on its initial status forever

### 2. No timeout while waiting for weapon prefabs

`utils.PrefabLoader:Step()` waits **forever** for

```lua
entry.controller:get_Ready()                 -- prefab resource
mesh:get_MeshReady() and mesh:get_MaterialReady()   -- weapon mesh + material
```

with up to 64 prefabs in flight and no timeout. A single prefab whose resource never becomes ready stalls the
whole catalog build permanently.

## What this patch changes

| File | Change |
|---|---|
| `Transmogify.lua` | `AddWeapons()` now **waits for the weapon catalog** to be populated (yields the coroutine, status `Waiting for the weapon catalog`, logs every 600 frames) instead of building from an empty table; `CATEGORY_ITEM_LIST` entries are created before sorting so the sort can never receive `nil`. |
| `Transmogify.lua` | **On-disk mesh/material path cache** (`reframework/data/Transmogify/weapon_paths_cache.json`, schema 1) so later launches only prepare **new or changed** prefabs. Cache keys: each prefab's own `ResourcePath`; entries store `{src, kind = ok / no_mesh / failed, mesh, mat}`. Failed prefabs are retried up to 3 times, then skipped until their resource path changes. |
| `Transmogify.lua` | **Sampling re-validation**: 8 cached prefabs are re-read every launch and compared with the cache; 鈮? mismatches discards the cache (catches a changed resource layout that file fingerprints cannot see). |
| `Transmogify.lua` | Cache bootstrap/save are wrapped in `pcall`, so any cache problem degrades to the plain full build instead of breaking initialisation. (REFramework forbids Lua from touching executables/DLLs, so the build fingerprint falls back to `unknown`; validation relies on resource paths + sampling.) |
| `Transmogify.lua` | Fallback driver: if the native frame-host hook does not fire, the startup work is driven from `re.on_application_entry("UpdateBehavior")` instead. |
| `_TransmogifyUtils/utils.lua` | `PrefabLoader:Step()` gives up on a prefab after **20 s** and reports the reason (`prefab-not-ready` / `no-weapon-mesh` / `mesh=鈥?material=鈥). |
| `_TransmogifyUtils/utils.lua` | `utils.Log()` also writes through `print()`, because `log.info` is silent in the current REFramework build. |

## Install

1. Install Transmogify v5.4.0 normally (Fluffy Mod Manager) so `YowaveUtils.dll` and the fonts are present.
2. Copy the two files from this repository over the installed ones:
   * `reframework/autorun/Transmogify.lua`
   * `reframework/autorun/_TransmogifyUtils/utils.lua`
3. Launch the game.

## Expected log lines (`re2_framework_log.txt`)

```
[Transmogify] Building the weapon catalog
[Transmogify] Waiting for the weapon catalog            (until item data is ready)
[Transmogify] Weapon prefabs: 592 prepared, 0 served from the path cache
[Transmogify] Weapon path cache saved for 592 prefabs (build unknown)
[Transmogify] Init complete in 18.2 s: 539 weapon and shield appearances, 1240 clothing appearances
```

Second launch and later:

```
[Transmogify] Weapon path cache hit for 860 prefabs (build unknown)
[Transmogify] Weapon prefabs: 0 prepared, 860 served from the path cache
```

## Known remaining issue

A handful of prefabs never become ready on the current build (verified: `[prefab-not-ready]`, i.e. the prefab
resource itself, not the material/texture):

```
AppSystem/Equipment/wp/wp09/Prefab/wp09_005_00.pfb   (WeaponID 153538110)
AppSystem/Equipment/wp/wp09/Prefab/wp09_009_00.pfb   (WeaponID 2150664227)
AppSystem/Equipment/wp/wp09/Prefab/wp09_010_00.pfb   (WeaponID 377658997)
AppSystem/Equipment/wp/wp09/Prefab/wp09_011_00.pfb   (WeaponID 295253032)
AppSystem/Equipment/wp/wp10/Prefab/wp10_001_00.pfb   (WeaponID 3934524428)
AppSystem/Equipment/wp/wp10/Prefab/wp10_004_00.pfb   (WeaponID 3569206815)
AppSystem/Equipment/wp/wp220/Prefab/wp220005_00_0.pfb (WeaponID 783413235)
AppSystem/Equipment/wp/wp227/Prefab/wp227003_10_0.pfb (WeaponID 3621193221)
```

They are skipped (the mod keeps working); the affected weapons simply do not appear in the transmog list.
Suspected cause: they belong to the Dark Arisen content and the installed REFramework nightly (01422,
2026-09-13) predates the 2026-10-19 game build, so its pak/DLC hooks cannot serve them. Needs verification
against a newer REFramework nightly.

## Credits & disclaimer

* Original mod: **Transmogify** by **Yowave1** 鈥?<https://www.nexusmods.com/dragonsdogma2/mods/420>
* These changes are an unofficial local fix. If the author resumes development, this repository will be
  removed / superseded by the official release.
* No original assets are redistributed here; only the two modified Lua scripts and their diff.

