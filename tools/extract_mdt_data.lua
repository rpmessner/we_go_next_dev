-- Extract MDT dungeon data to JSON for conversion to Elixir data structures
-- Usage: lua extract_mdt_data.lua > dungeons.json

local MDT_ADDON_PATH = "/mnt/e/World of Warcraft/_retail_/Interface/AddOns/MythicDungeonTools"

-- Stub out the MDT global and localization so the dungeon files can load
MDT = {
  dungeonList = {},
  mapInfo = {},
  zoneIdToDungeonIdx = {},
  dungeonMaps = {},
  dungeonSubLevels = {},
  dungeonTotalCount = {},
  mapPOIs = {},
  dungeonEnemies = {},
}

-- Localization stub - just returns the key as-is
local L = setmetatable({}, { __index = function(_, k) return k end })
MDT.L = L

-- The dungeon files use `local addonName = ...` (vararg from WoW loader)
-- We need to make each file think it's loaded by WoW
local dungeonFiles = {
  "AlgetharAcademy",
  "MagistersTerrace",
  "MaisaraCaverns",
  "NexusPointXenas",
  "PitOfSaron",
  "SeatoftheTriumvirate",
  "Skyreach",
  "WindrunnerSpire",
}

for _, name in ipairs(dungeonFiles) do
  local path = MDT_ADDON_PATH .. "/Midnight/" .. name .. ".lua"
  local chunk, err = loadfile(path)
  if chunk then
    -- Pass addonName as the vararg
    chunk("MythicDungeonTools")
  else
    io.stderr:write("Failed to load " .. path .. ": " .. tostring(err) .. "\n")
  end
end

-- Now extract the data into a JSON-friendly structure
-- Simple JSON encoder (no dependencies needed)
local function json_encode(val, indent, depth)
  indent = indent or "  "
  depth = depth or 0
  local pad = string.rep(indent, depth)
  local pad1 = string.rep(indent, depth + 1)

  if val == nil then
    return "null"
  elseif type(val) == "boolean" then
    return val and "true" or "false"
  elseif type(val) == "number" then
    if val ~= val then return "null" end -- NaN
    if val == math.huge or val == -math.huge then return "null" end
    return string.format("%.6f", val):gsub("%.?0+$", "")
  elseif type(val) == "string" then
    return '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
  elseif type(val) == "table" then
    -- Check if it's an array (sequential integer keys starting at 1)
    local is_array = true
    local max_idx = 0
    local count = 0
    for k, _ in pairs(val) do
      count = count + 1
      if type(k) == "number" and k == math.floor(k) and k > 0 then
        if k > max_idx then max_idx = k end
      else
        is_array = false
        break
      end
    end
    if is_array and max_idx == count and count > 0 then
      local parts = {}
      for i = 1, max_idx do
        parts[i] = pad1 .. json_encode(val[i], indent, depth + 1)
      end
      return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
    else
      -- Object
      local parts = {}
      -- Sort keys for deterministic output
      local keys = {}
      for k, _ in pairs(val) do
        keys[#keys + 1] = k
      end
      table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
      end)
      for _, k in ipairs(keys) do
        local key_str = type(k) == "number" and ('"' .. tostring(k) .. '"') or json_encode(k)
        parts[#parts + 1] = pad1 .. key_str .. ": " .. json_encode(val[k], indent, depth + 1)
      end
      if #parts == 0 then return "{}" end
      return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
    end
  else
    return '"' .. tostring(val) .. '"'
  end
end

-- Build output
local dungeons = {}

for dungeonIdx, enemies in pairs(MDT.dungeonEnemies) do
  local info = MDT.mapInfo[dungeonIdx]
  if info then
    local dungeon = {
      index = dungeonIdx,
      name = info.englishName,
      short_name = info.shortName,
      map_id = info.mapID,
      teleport_id = info.teleportId,
      total_count = MDT.dungeonTotalCount[dungeonIdx] and MDT.dungeonTotalCount[dungeonIdx].normal or 0,
      sub_levels = {},
      pois = {},
      enemies = {},
    }

    -- Sub levels (floors)
    local subs = MDT.dungeonSubLevels[dungeonIdx]
    if subs then
      for i, name in pairs(subs) do
        dungeon.sub_levels[#dungeon.sub_levels + 1] = { index = i, name = name }
      end
    end

    -- Map texture info (for stitching reference)
    local maps = MDT.dungeonMaps[dungeonIdx]
    dungeon.floors = {}
    if maps then
      for floorIdx, mapData in pairs(maps) do
        if floorIdx > 0 then
          if type(mapData) == "table" and mapData.customTextures then
            dungeon.floors[#dungeon.floors + 1] = {
              index = floorIdx,
              texture_path = mapData.customTextures,
              tile_format = "custom_15x10",
            }
          elseif type(mapData) == "string" then
            dungeon.floors[#dungeon.floors + 1] = {
              index = floorIdx,
              texture_name = mapData,
              tile_format = "blizzard",
            }
          end
        end
      end
    end

    -- POIs
    local pois = MDT.mapPOIs[dungeonIdx]
    if pois then
      for floorIdx, floorPois in pairs(pois) do
        for _, poi in pairs(floorPois) do
          dungeon.pois[#dungeon.pois + 1] = {
            floor = floorIdx,
            type = poi.type,
            x = poi.x,
            y = poi.y,
            target = poi.target,
            direction = poi.direction,
          }
        end
      end
    end

    -- Enemies
    for enemyIdx, enemy in pairs(enemies) do
      local e = {
        index = enemyIdx,
        name = enemy.name,
        id = enemy.id,
        count = enemy.count,
        health = enemy.health,
        scale = enemy.scale,
        creature_type = enemy.creatureType,
        level = enemy.level,
        is_boss = enemy.isBoss or false,
        encounter_id = enemy.encounterID,
        instance_id = enemy.instanceID,
        spells = {},
        clones = {},
      }

      -- Spells
      if enemy.spells then
        for spellId, spellData in pairs(enemy.spells) do
          e.spells[#e.spells + 1] = {
            spell_id = spellId,
            interruptible = spellData.interruptible or false,
            magic = spellData.magic or false,
          }
        end
        -- Sort by spell_id for deterministic output
        table.sort(e.spells, function(a, b) return a.spell_id < b.spell_id end)
      end

      -- Clones (mob positions)
      if enemy.clones then
        for cloneIdx, clone in pairs(enemy.clones) do
          e.clones[#e.clones + 1] = {
            index = cloneIdx,
            x = clone.x,
            y = clone.y,
            sublevel = clone.sublevel,
            group = clone.g,
          }
        end
        table.sort(e.clones, function(a, b) return a.index < b.index end)
      end

      dungeon.enemies[#dungeon.enemies + 1] = e
    end

    -- Sort enemies by index
    table.sort(dungeon.enemies, function(a, b) return a.index < b.index end)

    dungeons[#dungeons + 1] = dungeon
  end
end

-- Sort dungeons by name
table.sort(dungeons, function(a, b) return a.name < b.name end)

io.write(json_encode(dungeons))
io.write("\n")
