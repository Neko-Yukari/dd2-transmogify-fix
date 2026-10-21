local modname = "Transmogify"
local version = "v5.4.0"
local settingsVersion = "v4"
local settings_path = "Transmogify/settings_" .. settingsVersion .. ".json"
do
  -- The package ships its YowaveUtils.dll; the API number changes once per release that changes the DLL, in lockstep with this script.
  local REQUIRE_YOWAVEUTILS_API = 3
  local installed_api = YowaveUtils and YowaveUtils.api_version
  if installed_api ~= REQUIRE_YOWAVEUTILS_API then
    local message = "Transmogify needs its YowaveUtils.dll (API " .. REQUIRE_YOWAVEUTILS_API ..
      "). Install Transmogify's reframework/plugins folder and restart the game."
    log.error("[" .. modname .. "] " .. version .. " not started: " .. message .. " Found: " ..
      (installed_api and ("API " .. tostring(installed_api)) or "no YowaveUtils.dll") .. ".")
    re.on_draw_ui(function()
      if imgui.tree_node(modname .. " " .. version) then
        imgui.text_colored(message, 0xFF0000FF)
        imgui.tree_pop()
      end
    end)
    return
  end
end

Transmogify = Transmogify or {}
Transmogify.REQ_EQUIP_WEAPON_METHOD = "reqEquipWeapon(app.ItemWeaponParam, System.Boolean, System.Boolean, " ..
  "app.ItemDefine.EquipmentAbilityParam, app.AttackUserData.ElementType)"

local utils = require("_TransmogifyUtils/utils")

-- ItemEquipCategory
local CAT_WEAPON = 0
local CAT_SHIELD = 1
local CAT_HEAD = 2
local CAT_BODY = 3
local CAT_PANTS = 4
local CAT_CAPE = 5
local CAT_MASK_ACCESSORY = 7
local CAT_BACKPACK = 100
local CAT_UNDERWEAR = 101

local META_CATEGORY_FIELD_NAME_ENUM = {
  [CAT_HEAD] = "_HelmStyle",
  [CAT_BODY] = "_TopsStyle",
  [CAT_PANTS] = "_PantsStyle",
  [CAT_CAPE] = "_MantleStyle",
  [CAT_MASK_ACCESSORY] = "_FacewearStyle",
  [CAT_BACKPACK] = "_BackpackStyle",
  [CAT_UNDERWEAR] = "_UnderwearStyle",
}

local META_CATEGORY_SET_STYLE_FUNCTION_SIG_ENUM = {
  [CAT_HEAD] = "set_HelmStyle(app.HelmStyle)",
  [CAT_BODY] = "set_TopsStyle(app.TopsStyle)",
  [CAT_PANTS] = "set_PantsStyle(app.PantsStyle)",
  [CAT_CAPE] = "set_MantleStyle(app.MantleStyle)",
  [CAT_MASK_ACCESSORY] = "set_FacewearStyle(app.FacewearStyle)",
  [CAT_BACKPACK] = "set_BackpackStyle(app.BackpackStyle)",
  [CAT_UNDERWEAR] = "set_UnderwearStyle(app.UnderwearStyle)",
}

local ITEM_MANAGER_CATEGORY_GET_STYLE_FUNC_ENUM = {
  [CAT_HEAD] = "getHelmStyle(System.Int32)",
  [CAT_BODY] = "getTopsStyle(System.Int32)",
  [CAT_PANTS] = "getPantsStyle(System.Int32)",
  [CAT_CAPE] = "getMantleStyle(System.Int32)",
  [CAT_MASK_ACCESSORY] = "getFaceStyle(System.Int32)",
}

do
  -- Every game method Transmogify hooks, the game-look clear it calls, the StorageData methods it calls through
  -- ValueType:call or YowaveUtils' menu-exit refresh calls, the armor style fields, setters and getters it passes to
  -- YowaveUtils.armor.configure, and every method, field and type YowaveUtils looks up; REFramework skips a nil hook
  -- and returns nil for a missing method, so a game update that removes or changes one stops Transmogify with the
  -- list instead of leaving it partly working. Transmogify_Started and Transmogify_Version are defined only after it,
  -- so the addons see Transmogify as not running.
  local TARGETS = {
    frameHost = {utils.FRAME_HOST_TYPE, utils.FRAME_HOST_METHOD},
    editorSetup = {"app.HumanEditController", "setup"},
    editorRequestApply = {"app.HumanEditController", "requestApply"},
    charaEditStart = {"app.GUICharaEditCtrl", "start"},
    charaEditUiSetup = {"app.ui070406_01", "setup(app.GUICharaEditCtrl)"},
    makeSharedTableSlotNo = {"app.CharacterEditManager.CharacterBuilderBase",
      "makeSharedTableSlotNo(app.CharacterID, via.GameObject)"},
    isRegisteredPreBake = {"app.CharacterEditManager", "isRegisteredPreBake(System.UInt32)"},
    quiverSet = {"app.QuiverController", "set(app.Weapon)"},
    saveGameSaveData = {"app.SaveDataManager", "saveGameSaveData"},
    loadGameSaveData = {"app.SaveDataManager", "loadGameSaveData"},
    checkDraconic = {"app.HumanUtil", "checkDraconic(app.Character, app.EquipData.SlotEnum)"},
    isArisenEquipByCharacter = {"app.ItemManager", "isArisenEquip(app.Character, app.ItemDefine.StorageData)"},
    isArisenEquipById = {"app.ItemManager", "isArisenEquip(app.CharacterID, app.ItemDefine.StorageData)"},
    isArisenAndSkillJob10 = {"app.ItemManager", "isArisenAndSkillJob10_00"},
    setEquip = {"app.ItemManager", "setEquip"},
    removeEquip = {"app.ItemManager", "removeEquip"},
    onChangeArisenEquip = {"app.Job10WeaponManager", "onChangeArisenEquip"},
    generateEffect = {"app.Job10WeaponManager.WeaponAppearanceController", "generateEffect"},
    generateBodyEffect = {"app.Job10WeaponManager", "generateBodyEffect"},
    requestJob10CustomSkill = {"app.HumanActionSelector", "requestJob10CustomSkill"},
    charaEditChangeEquip = {"app.GUICharaEditCtrl", "changeEquip"},
    charaEditInstantiateWeapon = {"app.GUICharaEditCtrl", "onInstantiateWeapon"},
    reqEquipWeapon = {"app.MockupBuilder", Transmogify.REQ_EQUIP_WEAPON_METHOD},
    reqEquipArmor = {"app.MockupBuilder", "reqEquipArmor(app.ItemArmorParam, System.Boolean, System.Boolean)"},
    mockupRemoveEquip = {"app.MockupBuilder", "removeEquip(app.Character.JobEnum, app.EquipData.SlotEnum)"},
    menuFaceSetupEquip = {"app.MockupFace", "setupEquip"},
    setAxisL = {"app.CharacterInput", "set_AxisL"},
    storageIsDraconic = {"app.ItemDefine.StorageData", "get_IsDraconic"},
    storageIsSetAppearance = {"app.ItemDefine.StorageData", "get_IsSetAppearanceItemId"},
    storageAppearanceWeapon = {"app.ItemDefine.StorageData", "get_AppearanceWeaponParam"},
    storageCharaId = {"app.ItemDefine.StorageData", "get_CharaId()"},
    storageItemData = {"app.ItemDefine.StorageData", "get_ItemData()"},
    setEquipAppearance = {"app.ItemManager",
      "setEquipAppearance(app.ItemDefine.StorageData, System.Int32, app.Character, System.Boolean, System.Boolean)"},
  }
  local methods, missing = {}, {}
  for key, target in pairs(TARGETS) do
    local definition = sdk.find_type_definition(target[1])
    methods[key] = definition and definition:get_method(target[2])
    if not methods[key] then missing[#missing + 1] = target[1] .. "." .. target[2] end
  end
  local meta_type, item_manager_type = "app.CharacterEditDefine.MetaData", "app.ItemManager"
  local meta, item_manager = sdk.find_type_definition(meta_type), sdk.find_type_definition(item_manager_type)
  for category, field in pairs(META_CATEGORY_FIELD_NAME_ENUM) do
    local setter = META_CATEGORY_SET_STYLE_FUNCTION_SIG_ENUM[category]
    if not (meta and meta:get_field(field)) then missing[#missing + 1] = meta_type .. "." .. field end
    if not (meta and meta:get_method(setter)) then missing[#missing + 1] = meta_type .. "." .. setter end
  end
  for _, getter in pairs(ITEM_MANAGER_CATEGORY_GET_STYLE_FUNC_ENUM) do
    if not (item_manager and item_manager:get_method(getter)) then
      missing[#missing + 1] = item_manager_type .. "." .. getter
    end
  end
  local listed = {}
  for _, name in ipairs(missing) do listed[name] = true end
  for _, name in ipairs(YowaveUtils.check()) do
    if not listed[name] then missing[#missing + 1] = name end
  end
  if #missing > 0 then
    table.sort(missing)
    local message = "Transmogify does not support this game version: these game methods, fields or types are " ..
      "missing.\n" .. table.concat(missing, "\n") .. "\nCheck for a Transmogify update."
    log.error("[" .. modname .. "] " .. version .. " not started: these game methods, fields or types are missing: " ..
      table.concat(missing, ", ") .. ".")
    re.on_draw_ui(function()
      if imgui.tree_node(modname .. " " .. version) then
        utils.TextColored(message, 0xFF0000FF)
        imgui.tree_pop()
      end
    end)
    return
  end
  Transmogify.HOOKS = setmetatable(methods, {__index = function(_, key) error("Unknown hook target " .. key) end})
end
Transmogify.started = true
Transmogify.version = version

function Transmogify_Started()
  return Transmogify.started
end

function Transmogify_Version()
  return Transmogify.version
end
local sdk = sdk
local re = re
local imgui = imgui
local json = json

utils.Log("[" .. modname .. "] " .. version .. " start")
utils.Log("[" .. modname .. "] YowaveUtils api " .. YowaveUtils.api_version)

local font, fontSize = utils.LoadFont()

local STYLE_NONE = 0
local UNDERSS_NONE = 0

local JOB_WARFARER = 10

local EQUIP_JOB_NPC = -1
local EQUIP_JOB_ALL = 0
local EQUIP_JOB_FIGHTER = 1
local EQUIP_JOB_ARCHER = 2
local EQUIP_JOB_MAGE = 3
local EQUIP_JOB_THIEF = 4
local EQUIP_JOB_WARRIOR = 5
local EQUIP_JOB_SORCERER = 6
local EQUIP_JOB_SPEARHAND = 7
local EQUIP_JOB_MAGIC_ARCHER = 8
local EQUIP_JOB_TRICKSTER = 9

local EQUIP_JOB_ID_NAME_ENUM = {
  [EQUIP_JOB_ALL] = "ALL",
  [EQUIP_JOB_NPC] = "NPC",
  [EQUIP_JOB_FIGHTER] = "Fighter",
  [EQUIP_JOB_ARCHER] = "Archer",
  [EQUIP_JOB_MAGE] = "Mage",
  [EQUIP_JOB_THIEF] = "Thief",
  [EQUIP_JOB_WARRIOR] = "Warrior",
  [EQUIP_JOB_SORCERER] = "Sorcerer",
  [EQUIP_JOB_SPEARHAND] = "Spearhand",
  [EQUIP_JOB_MAGIC_ARCHER] = "Magic Archer",
  [EQUIP_JOB_TRICKSTER] = "Trickster"
}

local EQUIP_NAME_JOB_ENUM = {
  ["ALL"] = EQUIP_JOB_ALL,
  ["NPC"] = EQUIP_JOB_NPC,
  ["Fighter"] = EQUIP_JOB_FIGHTER,
  ["Archer"] = EQUIP_JOB_ARCHER,
  ["Mage"] = EQUIP_JOB_MAGE,
  ["Thief"] = EQUIP_JOB_THIEF,
  ["Warrior"] = EQUIP_JOB_WARRIOR,
  ["Sorcerer"] = EQUIP_JOB_SORCERER,
  ["Spearhand"] = EQUIP_JOB_SPEARHAND,
  ["Magic Archer"] = EQUIP_JOB_MAGIC_ARCHER,
  ["Trickster"] = EQUIP_JOB_TRICKSTER,
}

local job_names = {
  "ALL",
  "NPC",
  "Fighter",
  "Archer",
  "Mage",
  "Thief",
  "Warrior",
  "Sorcerer",
  "Spearhand",
  "Magic Archer",
  "Trickster"
}

local EXTRA_ARMOR_CATEGORIES = {
  [CAT_BACKPACK] = {label = "Backpack", field = "_BackpackStyle", type = "app.BackpackStyle", database = "_BackpackDB"},
  [CAT_UNDERWEAR] = {label = "Underwear", field = "_UnderwearStyle", type = "app.UnderwearStyle", database = "_UnderwearDB"},
}
Transmogify.EMPTY_ARMOR_FIELD = "show_when_unequipped"

local VALID_CATEGORIES = {
  CAT_WEAPON,
  CAT_SHIELD,
  CAT_HEAD,
  CAT_BODY,
  CAT_PANTS,
  CAT_CAPE,
  CAT_MASK_ACCESSORY
}

local ITEM_MANAGER_CATEGORY_GET_ITEM_DATA_FUNC_ENUM = {
  [CAT_HEAD] = "getItemData(app.HelmStyle)",
  [CAT_BODY] = "getItemData(app.TopsStyle)",
  [CAT_PANTS] = "getItemData(app.PantsStyle)",
  [CAT_CAPE] = "getItemData(app.MantleStyle)",
  [CAT_MASK_ACCESSORY] = "getItemData(app.FacewearStyle)",
}

local SLOT_MAIN_HAND = 0
local SLOT_OFF_HAND = 1
local SLOT_HEAD = 2
local SLOT_BODY = 3
local SLOT_PANTS = 4
local SLOT_CAPE = 5
-- local SLOT_RIGHT_RING = 6
-- local SLOT_LEFT_RING = 7
local SLOT_MASK_ACCESSORY = 8

local ARMOR_SLOT_TO_CATEGORY_ENUM = {
  [SLOT_HEAD] = CAT_HEAD,
  [SLOT_BODY] = CAT_BODY,
  [SLOT_PANTS] = CAT_PANTS,
  [SLOT_CAPE] = CAT_CAPE,
  [SLOT_MASK_ACCESSORY] = CAT_MASK_ACCESSORY,
}

local ARMOR_CATEGORY_TO_SLOT_ENUM = {
  [CAT_HEAD] = SLOT_HEAD,
  [CAT_BODY] = SLOT_BODY,
  [CAT_PANTS] = SLOT_PANTS,
  [CAT_CAPE] = SLOT_CAPE,
  [CAT_MASK_ACCESSORY] = SLOT_MASK_ACCESSORY,
}

local CATEGORY_ITEM_LIST = {}
local ITEM_INFO_DIC = {}

local INDEX_NONE = 1
local SET_VALUE_NONE = "NONE"
local SET_VALUE_HIDE = "HIDE"
local SETTINGS_SET_PLAYER = "playerSetName"
local SETTINGS_SET_PAWN = "pawnSetName"
local SETTINGS_SET_PAWN2 = "pawnSetName2"
local SETTINGS_SET_PAWN3 = "pawnSetName3"

local PRESET_SELECTION_PROMPT = "Select preset"
local SET_LIST = {PRESET_SELECTION_PROMPT}
local CURRENT_SET_INDEX = INDEX_NONE
local CURRENT_SET_NAME = ""
Transmogify.preset_editor = {name = "", ui_open = false}
Transmogify.window = {open = false, placed = false}
Transmogify.WINDOW_WIDTH = 600
Transmogify.WINDOW_HEIGHT = 700
Transmogify.DEFAULT_PRESET_SIZE = 100

local transmogSetList = {
  "None",
}

local EQUIPMENT_INFO_ACCESSORY = "Accessory\\Mask"
local EQUIPMENT_INFO_HEAD = "Head"
local EQUIPMENT_INFO_CAPE = "Cape"
local EQUIPMENT_INFO_BODY = "Body"
local EQUIPMENT_INFO_LEG = "Leg"
local EQUIPMENT_INFO_BACKPACK = "Backpack"
local EQUIPMENT_INFO_UNDERWEAR = "Underwear"
local EQUIPMENT_INFO_SHIELD = "Shield"
local EQUIPMENT_INFO_FIGHTER_WEAPON = "Fighter Weapon"
local EQUIPMENT_INFO_ARCHER_WEAPON = "Archer Weapon"
Transmogify.QUIVER_EQUIP_TYPE = "Archer Quiver"
local EQUIPMENT_INFO_MAGE_WEAPON = "Mage Weapon"
local EQUIPMENT_INFO_THIEF_RIGHT_WEAPON = "Thief Right Weapon"
local EQUIPMENT_INFO_THIEF_LEFT_WEAPON = "Thief Left Weapon"
local EQUIPMENT_INFO_WARRIOR_WEAPON = "Warrior Weapon"
local EQUIPMENT_INFO_SORCERER_WEAPON = "Sorcerer Weapon"
local EQUIPMENT_INFO_SPEARHAND_WEAPON = "Spearhand Weapon"
local EQUIPMENT_INFO_MAGIC_ARCHER_WEAPON = "Magic Archer Weapon"
local EQUIPMENT_INFO_TRICKSTER_WEAPON = "Trickster Weapon"

local ARMOR_CATEGORY_TO_EQUIPMENT_INFO_TYPE = {
  [CAT_HEAD] = EQUIPMENT_INFO_HEAD,
  [CAT_BODY] = EQUIPMENT_INFO_BODY,
  [CAT_PANTS] = EQUIPMENT_INFO_LEG,
  [CAT_CAPE] = EQUIPMENT_INFO_CAPE,
  [CAT_MASK_ACCESSORY] = EQUIPMENT_INFO_ACCESSORY,
  [CAT_BACKPACK] = EQUIPMENT_INFO_BACKPACK,
  [CAT_UNDERWEAR] = EQUIPMENT_INFO_UNDERWEAR,
}

local JOB_TO_WEAPON_EQUIP_INFO_TYPE_LIST = {
  [EQUIP_JOB_FIGHTER] = { EQUIPMENT_INFO_FIGHTER_WEAPON, EQUIPMENT_INFO_SHIELD },
  [EQUIP_JOB_ARCHER] = { EQUIPMENT_INFO_ARCHER_WEAPON },
  [EQUIP_JOB_MAGE] = { EQUIPMENT_INFO_MAGE_WEAPON },
  [EQUIP_JOB_THIEF] = { EQUIPMENT_INFO_THIEF_RIGHT_WEAPON, EQUIPMENT_INFO_THIEF_LEFT_WEAPON },
  [EQUIP_JOB_WARRIOR] = { EQUIPMENT_INFO_WARRIOR_WEAPON },
  [EQUIP_JOB_SORCERER] = { EQUIPMENT_INFO_SORCERER_WEAPON },
  [EQUIP_JOB_SPEARHAND] = { EQUIPMENT_INFO_SPEARHAND_WEAPON },
  [EQUIP_JOB_MAGIC_ARCHER] = { EQUIPMENT_INFO_MAGIC_ARCHER_WEAPON },
  [EQUIP_JOB_TRICKSTER] = { EQUIPMENT_INFO_TRICKSTER_WEAPON },
}

local EQUIPMENT_INFO_ORDER = {
  EQUIPMENT_INFO_ACCESSORY,
  EQUIPMENT_INFO_HEAD,
  EQUIPMENT_INFO_CAPE,
  EQUIPMENT_INFO_BODY,
  EQUIPMENT_INFO_LEG,
  EQUIPMENT_INFO_BACKPACK,
  EQUIPMENT_INFO_UNDERWEAR,
  EQUIPMENT_INFO_SHIELD,
  EQUIPMENT_INFO_FIGHTER_WEAPON,
  EQUIPMENT_INFO_ARCHER_WEAPON,
  EQUIPMENT_INFO_MAGE_WEAPON,
  EQUIPMENT_INFO_THIEF_RIGHT_WEAPON,
  EQUIPMENT_INFO_THIEF_LEFT_WEAPON,
  EQUIPMENT_INFO_WARRIOR_WEAPON,
  EQUIPMENT_INFO_SORCERER_WEAPON,
  EQUIPMENT_INFO_SPEARHAND_WEAPON,
  EQUIPMENT_INFO_MAGIC_ARCHER_WEAPON,
  EQUIPMENT_INFO_TRICKSTER_WEAPON,
}

local RIGHT_HAND = 0
local LEFT_HAND = 1

local function GetIndexByVal(list, val)
  local index = INDEX_NONE
  for k, v in pairs(list) do
    if val == v then
      index = k
      break
    end
  end
  return index
end

local EQUIPMENT_INFO = {}
EQUIPMENT_INFO[EQUIPMENT_INFO_ACCESSORY] = {
  category = CAT_MASK_ACCESSORY,
  slot = SLOT_MASK_ACCESSORY,
  job = nil,
  label = EQUIPMENT_INFO_ACCESSORY,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = nil
}
EQUIPMENT_INFO[EQUIPMENT_INFO_HEAD] = {
  category = CAT_HEAD,
  slot = SLOT_HEAD,
  job = nil,
  job_name_index_filter = GetIndexByVal(job_names, EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL]),
  label = EQUIPMENT_INFO_HEAD,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = nil
}
EQUIPMENT_INFO[EQUIPMENT_INFO_CAPE] = {
  category = CAT_CAPE,
  slot = SLOT_CAPE,
  job = nil,
  job_name_index_filter = GetIndexByVal(job_names, EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL]),
  label = EQUIPMENT_INFO_CAPE,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = nil
}
EQUIPMENT_INFO[EQUIPMENT_INFO_BODY] = {
  category = CAT_BODY,
  slot = SLOT_BODY,
  job = nil,
  job_name_index_filter = GetIndexByVal(job_names, EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL]),
  label = EQUIPMENT_INFO_BODY,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = nil
}
EQUIPMENT_INFO[EQUIPMENT_INFO_LEG] = {
  category = CAT_PANTS,
  slot = SLOT_PANTS,
  job = nil,
  job_name_index_filter = GetIndexByVal(job_names, EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL]),
  label = EQUIPMENT_INFO_LEG,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = nil
}
for category, entry in pairs(EXTRA_ARMOR_CATEGORIES) do
  EQUIPMENT_INFO[entry.label] = {category = category, label = entry.label, search = "", list = {}, index = INDEX_NONE}
end
EQUIPMENT_INFO[EQUIPMENT_INFO_SHIELD] = {
  category = CAT_SHIELD,
  slot = SLOT_OFF_HAND,
  hand = LEFT_HAND,
  job = EQUIP_JOB_FIGHTER,
  label = EQUIPMENT_INFO_SHIELD,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = 100,
  sizeBoth = false
}
EQUIPMENT_INFO[EQUIPMENT_INFO_FIGHTER_WEAPON] = {
  category = CAT_WEAPON,
  slot = SLOT_MAIN_HAND,
  hand = RIGHT_HAND,
  job = EQUIP_JOB_FIGHTER,
  job_name_index_filter = GetIndexByVal(job_names, EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL]),
  label = EQUIPMENT_INFO_FIGHTER_WEAPON,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = 100,
  sizeBoth = false
}
EQUIPMENT_INFO[EQUIPMENT_INFO_ARCHER_WEAPON] = {
  category = CAT_WEAPON,
  slot = SLOT_MAIN_HAND,
  hand = LEFT_HAND,
  job = EQUIP_JOB_ARCHER,
  job_name_index_filter = GetIndexByVal(job_names, EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL]),
  label = EQUIPMENT_INFO_ARCHER_WEAPON,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = 100,
  sizeBoth = true
}
EQUIPMENT_INFO[EQUIPMENT_INFO_MAGE_WEAPON] = {
  category = CAT_WEAPON,
  slot = SLOT_MAIN_HAND,
  hand = RIGHT_HAND,
  job = EQUIP_JOB_MAGE,
  job_name_index_filter = GetIndexByVal(job_names, EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL]),
  label = EQUIPMENT_INFO_MAGE_WEAPON,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = 100,
  sizeBoth = false
}
EQUIPMENT_INFO[EQUIPMENT_INFO_THIEF_RIGHT_WEAPON] = {
  category = CAT_WEAPON,
  slot = SLOT_MAIN_HAND,
  hand = RIGHT_HAND,
  job = EQUIP_JOB_THIEF,
  job_name_index_filter = GetIndexByVal(job_names, EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL]),
  label = EQUIPMENT_INFO_THIEF_RIGHT_WEAPON,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = 100,
  sizeBoth = false
}
EQUIPMENT_INFO[EQUIPMENT_INFO_THIEF_LEFT_WEAPON] = {
  category = CAT_WEAPON,
  slot = SLOT_MAIN_HAND,
  hand = LEFT_HAND,
  job = EQUIP_JOB_THIEF,
  job_name_index_filter = GetIndexByVal(job_names, EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL]),
  label = EQUIPMENT_INFO_THIEF_LEFT_WEAPON,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = 100,
  sizeBoth = false
}
EQUIPMENT_INFO[EQUIPMENT_INFO_WARRIOR_WEAPON] = {
  category = CAT_WEAPON,
  slot = SLOT_MAIN_HAND,
  hand = RIGHT_HAND,
  job = EQUIP_JOB_WARRIOR,
  job_name_index_filter = GetIndexByVal(job_names, EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL]),
  label = EQUIPMENT_INFO_WARRIOR_WEAPON,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = 100,
  sizeBoth = false
}
EQUIPMENT_INFO[EQUIPMENT_INFO_SORCERER_WEAPON] = {
  category = CAT_WEAPON,
  slot = SLOT_MAIN_HAND,
  hand = RIGHT_HAND,
  job = EQUIP_JOB_SORCERER,
  job_name_index_filter = GetIndexByVal(job_names, EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL]),
  label = EQUIPMENT_INFO_SORCERER_WEAPON,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = 100,
  sizeBoth = false
}
EQUIPMENT_INFO[EQUIPMENT_INFO_SPEARHAND_WEAPON] = {
  category = CAT_WEAPON,
  slot = SLOT_MAIN_HAND,
  hand = RIGHT_HAND,
  job = EQUIP_JOB_SPEARHAND,
  job_name_index_filter = GetIndexByVal(job_names, EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL]),
  label = EQUIPMENT_INFO_SPEARHAND_WEAPON,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = 100,
  sizeBoth = false
}
EQUIPMENT_INFO[EQUIPMENT_INFO_MAGIC_ARCHER_WEAPON] = {
  category = CAT_WEAPON,
  slot = SLOT_MAIN_HAND,
  hand = LEFT_HAND,
  job = EQUIP_JOB_MAGIC_ARCHER,
  job_name_index_filter = GetIndexByVal(job_names, EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL]),
  label = EQUIPMENT_INFO_MAGIC_ARCHER_WEAPON,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = 100,
  sizeBoth = true
}
EQUIPMENT_INFO[EQUIPMENT_INFO_TRICKSTER_WEAPON] = {
  category = CAT_WEAPON,
  slot = SLOT_MAIN_HAND,
  hand = RIGHT_HAND,
  job = EQUIP_JOB_TRICKSTER,
  job_name_index_filter = GetIndexByVal(job_names, EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL]),
  label = EQUIPMENT_INFO_TRICKSTER_WEAPON,
  search = "",
  list = {},
  index = INDEX_NONE,
  size = 100,
  sizeBoth = false
}

local isPaused = true
Transmogify.BARBER_EDIT_CHARACTER = 0
Transmogify.BARBER_PLACE_DEFAULT = 0
Transmogify.BARBER_TARGETS = { "Arisen", "Main Pawn" }
Transmogify.barber_target_index = 1
Transmogify.barber_open_request = nil
Transmogify.barber_open_message = nil

Transmogify.WEAPON_CHECK = {INTERVAL = 10, SOON = 3}
Transmogify.weapon_check_countdown = 0
Transmogify.DRAW_CHECK = {INTERVAL = 5, AFTER_REARM = 15}
Transmogify.DRAW_STATE = {DRAWN = "drawn", DRAWING = "drawing", SHEATHED = "sheathed"}
Transmogify.HIDE_SHEATHED = {FIELD = "hide_when_sheathed", ALL = "*"}
-- CharacterID -> {character = address, draw_state, sheathe_hidden} for loaded NPCs whose preset uses Hide when sheathed
-- or a different glow intensity when sheathed.
Transmogify.npc_draw_states = {}
Transmogify.draw_check_countdown = Transmogify.DRAW_CHECK.INTERVAL
-- After a save the check waits longer, so the pawn armor the save hook restored is not transmogged again mid-save.
Transmogify.ARMOR_CHECK = {INTERVAL = 5, AFTER_SAVE = 15}
Transmogify.armor_check_countdown = Transmogify.ARMOR_CHECK.INTERVAL
Transmogify.CINEMATIC_CHECK = {INTERVAL = 5}
Transmogify.cinematic_check_countdown = Transmogify.CINEMATIC_CHECK.INTERVAL
Transmogify.LANTERN_CHECK = {INTERVAL = 10}
Transmogify.lantern_check_countdown = Transmogify.LANTERN_CHECK.INTERVAL
Transmogify.HIDE_DRACONIC = {DELAY = 60}
Transmogify.hide_draconic_countdown = 0
Transmogify.BARBER_CHECK = {INTERVAL = 5}
Transmogify.barber_check_countdown = Transmogify.BARBER_CHECK.INTERVAL
Transmogify.party_ids = {}
-- A weapon request also runs the GUI pass outside menus, so menu models the game rebuilds on exit are ready next time.
Transmogify.GUI_CHECK = {INTERVAL = 5}
Transmogify.gui_check_countdown = Transmogify.GUI_CHECK.INTERVAL
Transmogify.gui_check_requested = false
-- The game registers DLC content after startup, once the title screen's content check activates it. The catalog check
-- builds again when one of the game's counts grew past those the last build read; built entries are kept.
Transmogify.CATALOG_CHECK = {INTERVAL = 120, ARMOR = {
  {type = "app.HelmStyle", database = "_HelmDB", category = CAT_HEAD},
  {type = "app.TopsStyle", database = "_TopsDB", category = CAT_BODY},
  {type = "app.PantsStyle", database = "_PantsDB", category = CAT_PANTS},
  {type = "app.MantleStyle", database = "_MantleDB", category = CAT_CAPE},
  {type = "app.FacewearStyle", database = "_FacewearDB", category = CAT_MASK_ACCESSORY},
}}
for category, entry in pairs(EXTRA_ARMOR_CATEGORIES) do
  table.insert(Transmogify.CATALOG_CHECK.ARMOR, {type = entry.type, database = entry.database, category = category})
end
Transmogify.catalog_check_countdown = Transmogify.CATALOG_CHECK.INTERVAL
Transmogify.catalog_counts = nil
-- WeaponID -> {mesh_path, mat_path} of each weapon catalog entry built so far, or false when it has no weapon mesh. An
-- entry is recorded once its appearance is built, so a build that fails partway builds the rest on the next attempt.
Transmogify.catalog_weapons = {}

function Transmogify.RequestGUICheck()
  Transmogify.gui_check_requested = true
end

function Transmogify.RequestWeaponCheck()
  Transmogify.weapon_check_countdown = math.min(Transmogify.weapon_check_countdown, Transmogify.WEAPON_CHECK.SOON)
end

local COLOR_INFO = 0xFF279EE3
local PERF_COLOR_OK = 0xFF00FF00
local PERF_COLOR_HIGH = 0xFF0000FF
local PERF_WINDOW_SECONDS = 1
local PERF_HIGH_MS = 1
local PERF_TOTAL_HIGH_MS = 2
local PERF_SECTION_ORDER = {
  "world_weapons", "weapon_glow", "world_armors", "npc_armors", "npc_looks", "eye_glow",
  "cinematic_shared", "cinematic_armors", "cinematic_npc_armors", "cinematic_weapons",
  "gui_armors", "gui_weapons", "gui_transitions", "barber",
  "lanterns", "weapon_resize", "draconic", "catalog", "shared_setup",
}
local PERF_SECTION_LABEL = {
  world_weapons = "Party weapons",
  weapon_glow = "Weapon glow",
  world_armors = "Party armor",
  npc_armors = "NPC equipment",
  npc_looks = "NPC looks",
  eye_glow = "Eye glow",
  cinematic_shared = "Discovery / shared work",
  cinematic_armors = "Party armor",
  cinematic_npc_armors = "NPC armor",
  cinematic_weapons = "Weapons / shields",
  gui_armors = "GUI armor",
  gui_weapons = "GUI weapons / enchantments",
  gui_transitions = "GUI refresh / transitions",
  barber = "Barber / character editor",
  lanterns = "Lanterns",
  weapon_resize = "Weapon draw/sheathe",
  draconic = "Draconic effects",
  catalog = "Catalog lists",
  shared_setup = "Shared setup",
}
local PERF_SECTION_GROUP = {
  world_weapons = "World", cinematic_shared = "Cinematics", gui_armors = "Previews", lanterns = "Other",
}
local PERF_DATA = {enabled = false, timer = utils.CreateTimer()}
PERF_DATA.clock = PERF_DATA.timer:GetClock()

local function SetPerfEnabled(enabled)
  enabled = enabled == true
  if PERF_DATA.enabled == enabled then return end
  PERF_DATA.enabled = enabled
  PERF_DATA.current, PERF_DATA.snapshot, PERF_DATA.window_started = nil, nil, nil
  YowaveUtils.glow.set_counting(enabled)
  YowaveUtils.glow.reset_stats()
  PERF_DATA.timer:Reset()
end

local function StartTimer(timer_name)
  if not PERF_DATA.current then return end
  PERF_DATA.timer:Start(timer_name)
end

local function EndTimer(timer_name)
  if not PERF_DATA.current then return end
  return PERF_DATA.timer:End(timer_name)
end

local function BeginPerfUpdate(enabled)
  SetPerfEnabled(enabled)
  if not PERF_DATA.enabled then return end
  PERF_DATA.timer:Discard()
  PERF_DATA.current = true
  if not PERF_DATA.window_started then
    PERF_DATA.window_started = PERF_DATA.clock.now()
  end
  StartTimer("shared_setup")
end

local function EndPerfUpdate()
  if not PERF_DATA.current then return end
  EndTimer("shared_setup")
  PERF_DATA.current = nil
  local now = PERF_DATA.clock.now()
  local window_seconds = (now - PERF_DATA.window_started) / PERF_DATA.clock.ticks_per_second
  if window_seconds < PERF_WINDOW_SECONDS then return end
  local results = PERF_DATA.timer:GetResults()
  -- The native weapon glow hook runs between updates; its own time joins the glow row and the window's total, and its
  -- calls count those on published glows.
  local native = YowaveUtils.glow.stats()
  YowaveUtils.glow.reset_stats()
  local glow_us = native.ticks / PERF_DATA.clock.ticks_per_us
  local snapshot = {seconds = window_seconds, updates = results.samples,
    total_ms = (results.total_us + glow_us) / 1000 / results.samples, sections = {},
    glow_calls = native.hits / results.samples}
  for _, name in ipairs(PERF_SECTION_ORDER) do
    snapshot.sections[name] = (results.sections[name] or 0) / 1000 / results.samples
  end
  snapshot.sections.weapon_glow = snapshot.sections.weapon_glow + glow_us / 1000 / results.samples
  PERF_DATA.snapshot = snapshot
  PERF_DATA.timer:Reset()
  PERF_DATA.window_started = now
end

local GuiBase = sdk.create_instance("app.GUIBase"):add_ref()
local GuiManager = sdk.get_managed_singleton("app.GuiManager")
local ItemManager = sdk.get_managed_singleton("app.ItemManager")
local CharacterEditManager = sdk.get_managed_singleton("app.CharacterEditManager")
local _, weapon_enum_value_key = utils.GetEnumDic("app.WeaponID")

local cm = {
  setNextArisenWeapon = sdk.find_type_definition("app.ItemManager"):get_method("setNextArisenWeapon"),
  getEquipData = sdk.find_type_definition("app.ItemManager"):get_method("getEquipData(app.Character)"),
  getCharaID = sdk.find_type_definition("app.Character"):get_method("get_CharaID"),
  getHuman = sdk.find_type_definition("app.Character"):get_method("get_Human"),
  getIsDrawedWeapon = sdk.find_type_definition("app.Character"):get_method("get_IsDrawedWeapon"),
}

local function GetEquipData(character)
  return cm.getEquipData(ItemManager, character).Data;
end

local function GetCharacterHuman(character)
  if not utils.ComponentGameObject(character) then return nil end
  local human = cm.getHuman:call(character)
  if utils.ComponentGameObject(human) then return human end
end

local function GetWeaponEnumKey(weapon_id)
  return weapon_enum_value_key[weapon_id]
end

local function GetArmorStyle(equip_category, equip_style_no)
  if EXTRA_ARMOR_CATEGORIES[equip_category] then
    if equip_style_no == nil then return nil end
    local styles = ITEM_INFO_DIC[equip_style_no]
    local entry = styles and styles[equip_category]
    return assert(entry and entry.style, "Unknown clothing style: " .. tostring(equip_style_no))
  end
  local style_func_name = ITEM_MANAGER_CATEGORY_GET_STYLE_FUNC_ENUM[equip_category]
  return ItemManager:call(style_func_name, equip_style_no)
end

local function GetMockupBuilder(character)
  if not character then return nil end
  local builder = YowaveUtils.menus.builder(character:get_address())
  return builder and sdk.to_managed_object(builder)
end

local function GetMainWeaponItemData(equip_data)
  return utils.GetWeaponParam(equip_data, SLOT_MAIN_HAND)
end

local function GetOffWeaponItemData(equip_data)
  return utils.GetWeaponParam(equip_data, SLOT_OFF_HAND)
end

local function IsWarfarer(character)
  return character and GuiBase:getJob(character) == JOB_WARFARER
end

local function EquipmentIsBow(item_data)
  local is_bow = false
  if item_data then
    local equip_job = item_data:getJob()
    is_bow = equip_job == EQUIP_JOB_ARCHER or equip_job == EQUIP_JOB_MAGIC_ARCHER
  end
  return is_bow
end

-- Whether a character's weapons count as drawn, from the hands' weapon draw flags (nil for a hand without a weapon) and
-- the character's. Character.get_IsDrawedWeapon is updated before the weapon has finished the draw animation.
local function IsDrawFrom(main_weapon_item_data, off_weapon_item_data, right_drawn, left_drawn, character_drawed)
  local main_weapon_drawed, off_weapon_drawed
  if main_weapon_item_data then
    if EquipmentIsBow(main_weapon_item_data) then main_weapon_drawed = left_drawn else main_weapon_drawed = right_drawn end
  end
  if off_weapon_item_data then off_weapon_drawed = left_drawn end

  if character_drawed then
    if main_weapon_drawed ~= nil then character_drawed = character_drawed and main_weapon_drawed end
    if off_weapon_drawed ~= nil then character_drawed = character_drawed and off_weapon_drawed end
  end

  if not character_drawed then
    if main_weapon_drawed ~= nil then character_drawed = character_drawed or main_weapon_drawed end
    if off_weapon_drawed ~= nil then character_drawed = character_drawed or off_weapon_drawed end
  end

  return character_drawed
end

-- NPC weapons come from their WeaponAndItemHolder, not party equipment data.
local function IsDraw(character, npc)
  local main_weapon_item_data, off_weapon_item_data
  if npc then
    main_weapon_item_data, off_weapon_item_data = Transmogify.GetWorldWeaponData(character, true)
  else
    local equip_data = GetEquipData(character)
    main_weapon_item_data, off_weapon_item_data = GetMainWeaponItemData(equip_data), GetOffWeaponItemData(equip_data)
  end
  local right_drawn, left_drawn
  if main_weapon_item_data and not EquipmentIsBow(main_weapon_item_data) then
    local weapon = character:get_RightWeapon()
    if weapon then right_drawn = weapon:get_IsDrawed() end
  end
  if (main_weapon_item_data and EquipmentIsBow(main_weapon_item_data)) or off_weapon_item_data then
    local weapon = character:get_LeftWeapon()
    if weapon then left_drawn = weapon:get_IsDrawed() end
  end
  return IsDrawFrom(main_weapon_item_data, off_weapon_item_data, right_drawn, left_drawn, character:get_IsDrawedWeapon())
end

-- Drawn from the grab until the last weapon lands on the back; drawing from the start of a draw until the grab.
function Transmogify.GetDrawState(character, npc)
  local DRAW_STATE = Transmogify.DRAW_STATE
  if IsDraw(character, npc) then return DRAW_STATE.DRAWN end
  return cm.getIsDrawedWeapon:call(character) and DRAW_STATE.DRAWING or DRAW_STATE.SHEATHED
end

-- GetDrawState from YowaveUtils.weapons.read facts and the item data GetWorldWeaponDataFromFacts makes of them.
function Transmogify.GetDrawStateFromFacts(facts, main_weapon_item_data, off_weapon_item_data)
  local right_drawn = facts.right and facts.right.drawn
  local left_drawn = facts.left and facts.left.drawn
  if IsDrawFrom(main_weapon_item_data, off_weapon_item_data, right_drawn, left_drawn, facts.drawn) then
    return Transmogify.DRAW_STATE.DRAWN
  end
  return facts.drawn and Transmogify.DRAW_STATE.DRAWING or Transmogify.DRAW_STATE.SHEATHED
end

-- The state the draw check last applied, or sheathed while it has not applied one since hiding weapons: other paths
-- follow it, so only the draw check reveals a hidden weapon.
function Transmogify.GetAppliedDrawState(character, npc, char_info)
  local record = char_info
  if npc then
    record = Transmogify.npc_draw_states[tostring(cm.getCharaID:call(character))]
    if record and record.character ~= sdk.to_ptr(character) then record = nil end
  end
  if not record then return nil end
  return record.draw_state or (record.sheathe_hidden and Transmogify.DRAW_STATE.SHEATHED) or nil
end

-- Makes the draw check apply the character's draw state again on its next run; whether it hid weapons is kept.
function Transmogify.ClearAppliedDrawState(character, npc, char_info)
  local record = char_info
  if npc then record = Transmogify.npc_draw_states[tostring(cm.getCharaID:call(character))] end
  if record then record.draw_state = nil end
  Transmogify.RequestWorldGlow(cm.getCharaID:call(character))
end

-- How the draw check applies a change of draw state: "full", "show" or nil to only record it. Without Hide when
-- sheathed on the preset, it applies exactly when drawn/not drawn flips or no state is recorded.
function Transmogify.GetDrawStateApply(previous, state, hidden, set_name)
  local DRAW_STATE = Transmogify.DRAW_STATE
  -- Revealing mid-draw only shows the weapons: the resize refresh would snap them into the hand.
  if state == DRAW_STATE.DRAWING and hidden then return "show" end
  if previous == nil or (state == DRAW_STATE.DRAWN) ~= (previous == DRAW_STATE.DRAWN) then return "full" end
  if state == DRAW_STATE.SHEATHED and Transmogify.PresetHidesSheathed(set_name) then return "full" end
  return nil
end

local function GetTransmogId(id_name)
  local result = nil
  if id_name ~= nil then
    local i = (utils.StringFindRaw(id_name, "[") or 0) + 1
    local j = (utils.StringFindRaw(id_name, "]") or 1) - 1
    result = tonumber(string.sub(id_name, i, j))
  end
  return result
end

local function GetPaddedItemId(item_id, length)
  return utils.PadLeft(item_id, '0', length or 4)
end

local CURRENT_SETTINGS

local function GetSetTransmogValue(set_name, equip_info_type)
  if equip_info_type == Transmogify.QUIVER_EQUIP_TYPE then equip_info_type = EQUIPMENT_INFO_ARCHER_WEAPON end
  local set_info = CURRENT_SETTINGS.sets[set_name]
  if CURRENT_SETTINGS.enabled and set_info and set_info[equip_info_type] then
    return set_info[equip_info_type]
  end

  return SET_VALUE_NONE
end

local SETTINGS_VERSION = 1
CURRENT_SETTINGS = {
  version = SETTINGS_VERSION,
  pawn_shadow_ban_protection = true,
  enabled = false,
  show_lantern = true,
  hide_lantern_when_off = false,
  hide_weapons_in_barber = true,
  cinematic_transmog = false,
  lantern_size = 100,
  performance_monitor = false,
  hideDraconic = false,
  resizeOnSheathe = false,
  sets = {},
  setSize = {},
  setGlow = {},
  setEyes = {},
  setEmpty = {},
  setHideSheathed = {},
  npcSets = {},
  npcAppearances = {},
  window = {width = Transmogify.WINDOW_WIDTH, height = Transmogify.WINDOW_HEIGHT},
  playerSetName = SET_VALUE_NONE,
  pawnSetName = SET_VALUE_NONE,
  pawnSetName2 = SET_VALUE_NONE,
  pawnSetName3 = SET_VALUE_NONE
}

local function RefreshSetList()
  SET_LIST = {PRESET_SELECTION_PROMPT}
  CURRENT_SET_INDEX = INDEX_NONE
  for set_name in utils.PairsByKeys(CURRENT_SETTINGS.sets) do
    table.insert(SET_LIST, set_name)
    if set_name == CURRENT_SET_NAME then
      CURRENT_SET_INDEX = #SET_LIST
    end
  end
end

-- load settings
local mod_settings = json.load_file(settings_path)
if mod_settings == nil then
  json.dump_file(settings_path, CURRENT_SETTINGS)
else
  -- populating settings
  for k, v in pairs(mod_settings) do
    if v ~= nil and CURRENT_SETTINGS[k] ~= nil then
      CURRENT_SETTINGS[k] = v
    end
  end

  RefreshSetList()

  if CURRENT_SETTINGS.version ~= SETTINGS_VERSION then
    CURRENT_SETTINGS.version = SETTINGS_VERSION
  end
end

do
  local counts = {}
  for _, key in ipairs({"sets", "npcSets", "npcAppearances"}) do
    counts[key] = 0
    for _ in pairs(CURRENT_SETTINGS[key]) do counts[key] = counts[key] + 1 end
  end
  utils.Log(string.format("[%s] Settings: transmogs %s; %d equipment presets; NPC assignments: %d equipment, %d looks",
    modname, CURRENT_SETTINGS.enabled and "on" or "off", counts.sets, counts.npcSets, counts.npcAppearances))
end

function Transmogify.GetShowWhenUnequipped(set_name, equip_type, raw)
  if not raw and not CURRENT_SETTINGS.enabled then return false end
  local values = CURRENT_SETTINGS.sets[set_name] and CURRENT_SETTINGS.setEmpty[set_name]
  return values ~= nil and values[equip_type] == true
end

-- The preset-wide option (HIDE_SHEATHED.ALL) covers every weapon type; raw reads one stored value for the editor.
function Transmogify.GetHideWhenSheathed(set_name, equip_type, raw)
  if not raw and not CURRENT_SETTINGS.enabled then return false end
  local values = CURRENT_SETTINGS.sets[set_name] and CURRENT_SETTINGS.setHideSheathed[set_name]
  if not values then return false end
  return values[equip_type] == true or (not raw and values[Transmogify.HIDE_SHEATHED.ALL] == true)
end

function Transmogify.PresetHidesSheathed(set_name)
  if not CURRENT_SETTINGS.enabled then return false end
  local values = CURRENT_SETTINGS.sets[set_name] and CURRENT_SETTINGS.setHideSheathed[set_name]
  for _, hide in pairs(values or {}) do
    if hide then return true end
  end
  return false
end

SetPerfEnabled(CURRENT_SETTINGS.performance_monitor)

do
  local EYES = {
    FIELD = "eyes", NODE = "Eyes", MIN = 0.0, MAX = 100.0, SPEED_RATE = 0.01, SPEED_MIN = 0.001,
    DEFAULT = {enabled = false, intensity = 0.1, r = 13 / 255, g = 1, b = 1},
  }
  Transmogify.EYES = EYES

  function Transmogify.NewEyeSettings(source)
    return {same = not source or source.same ~= false, left = utils.ShallowCopy(source and source.left or EYES.DEFAULT),
      right = utils.ShallowCopy(source and source.right or EYES.DEFAULT)}
  end

  function Transmogify.GetEyeSettings(set_name, raw)
    if not raw and not CURRENT_SETTINGS.enabled then return nil end
    return CURRENT_SETTINGS.sets[set_name] and CURRENT_SETTINGS.setEyes[set_name] or nil
  end
end

local char_info_list = {
  {
    character = utils.GetPlayer,
    settings_set = SETTINGS_SET_PLAYER,
    draw_state = nil
  },
  {
    character = utils.GetMainPawn,
    settings_set = SETTINGS_SET_PAWN,
    draw_state = nil
  },
  {
    character = function() return utils.GetPartyMember(2) end,
    settings_set = SETTINGS_SET_PAWN2,
    draw_state = nil
  },
  {
    character = function() return utils.GetPartyMember(3) end,
    settings_set = SETTINGS_SET_PAWN3,
    draw_state = nil
  },
}

-- The char_info and party member with that CharacterID; party slots 0-3 are char_info_list's entries in order.
local function GetCharInfoById(char_id)
  if not char_id then
    return nil
  end
  local slot, character = YowaveUtils.party.find(char_id)
  if not slot then return nil end
  return char_info_list[slot + 1], sdk.to_managed_object(character)
end

local function GetSetNameByCharInfo(char_info)
  if not char_info then
    return nil
  end

  return CURRENT_SETTINGS[char_info.settings_set]
end

do
  local GLOW = {
    COLOR_EPSILON = 0.001, INTENSITY_EPSILON = 0.001,
    FIELD = "glow", MIN = 0.0, MAX = 100.0, STEP = 0.01,
    DEFAULT = {enabled = false, intensity = 0.50, sheathed_intensity = 0.50, r = 39 / 255, g = 245 / 255, b = 200 / 255},
    reported = {},
  }
  Transmogify.GLOW = GLOW

  -- Settings saved before the sheathed intensity existed start it at their intensity, so their glow looks the same.
  for _, glows in pairs(CURRENT_SETTINGS.setGlow) do
    for _, glow in pairs(glows) do
      if glow.sheathed_intensity == nil then glow.sheathed_intensity = glow.intensity end
    end
  end

  -- sheathed, for world weapons on the back, returns a copy with the intensity when sheathed.
  function Transmogify.GetWeaponGlowSettings(set_name, equip_type, raw, sheathed)
    if equip_type == Transmogify.QUIVER_EQUIP_TYPE then return GLOW.DEFAULT end
    if not raw and not CURRENT_SETTINGS.enabled then return GLOW.DEFAULT end
    local preset = CURRENT_SETTINGS.sets[set_name] and CURRENT_SETTINGS.setGlow[set_name]
    local glow = preset and preset[equip_type] or GLOW.DEFAULT
    if not sheathed or glow.sheathed_intensity == glow.intensity then return glow end
    local copy = utils.ShallowCopy(glow)
    copy.intensity = glow.sheathed_intensity
    return copy
  end

  function Transmogify.PresetUsesSheathedGlow(set_name)
    if not CURRENT_SETTINGS.enabled then return false end
    local glows = CURRENT_SETTINGS.sets[set_name] and CURRENT_SETTINGS.setGlow[set_name]
    for _, glow in pairs(glows or {}) do
      if glow.enabled and glow.sheathed_intensity ~= glow.intensity then return true end
    end
    return false
  end

  -- Whether a world character's weapons show the intensity when sheathed: on the back, including the reach of a draw.
  function Transmogify.IsGlowSheathed(character, npc, char_info, set_name)
    if not Transmogify.PresetUsesSheathedGlow(set_name) then return false end
    local state = Transmogify.GetAppliedDrawState(character, npc, char_info) or Transmogify.GetDrawState(character, npc)
    return state ~= Transmogify.DRAW_STATE.DRAWN
  end

  function Transmogify.GetGlowSignature(glow)
    if not glow.enabled then return "" end
    return table.concat({glow.intensity, glow.sheathed_intensity, glow.r, glow.g, glow.b}, ":")
  end

  function Transmogify.GetWeaponGlowSignature(set_name, job)
    local values = {}
    for _, equip_type in ipairs(JOB_TO_WEAPON_EQUIP_INFO_TYPE_LIST[job] or {}) do
      local glow = Transmogify.GetWeaponGlowSettings(set_name, equip_type)
      if glow.enabled and GetSetTransmogValue(set_name, equip_type) ~= SET_VALUE_HIDE then
        values[#values + 1] = equip_type .. ":" .. Transmogify.GetGlowSignature(glow)
      end
    end
    return table.concat(values, "|")
  end

  local process_glow = YowaveUtils.glow.process
  local GLOW_PROCESS = {variables = utils.WEAPON_GLOW_VARIABLES, intensity_epsilon = GLOW.INTENSITY_EPSILON,
    color_epsilon = GLOW.COLOR_EPSILON}
  YowaveUtils.glow.install(GLOW_PROCESS)

  -- Logs a "mesh|material" resource pair whose mesh has no glow variables for a custom glow, once.
  function Transmogify.ReportMissingGlow(key)
    if GLOW.reported[key] then return end
    GLOW.reported[key] = true
    utils.Log("[" .. modname .. "] Custom glow unavailable for mesh/material: " .. key)
  end

  -- mesh is a via.render.Mesh or its address.
  function Transmogify.ProcessWeaponGlow(mesh, glow, apply)
    if not glow.enabled then return false end
    local changed, found = process_glow(sdk.to_ptr(mesh), GLOW_PROCESS, glow, apply)
    if found == false then
      mesh = sdk.to_managed_object(mesh)
      local resource, material = mesh:getMesh(), mesh:get_Material()
      if resource and material then
        Transmogify.ReportMissingGlow(resource:get_ResourcePath() .. "|" .. material:get_ResourcePath())
      end
    end
    return changed
  end

  function Transmogify.HasWeaponGlow(set_name)
    for equip_type, glow in pairs(CURRENT_SETTINGS.setGlow[set_name] or {}) do
      if equip_type ~= Transmogify.QUIVER_EQUIP_TYPE and glow.enabled then return true end
    end
    return false
  end

  -- The native glow hook's entry for one weapon GameObject, from addresses: the target's enabled glow, kept on the mesh
  -- while it has the target's resources, or none. barber holds the edit controller, editor and part swapper the hook
  -- checks for a barber weapon.
  function Transmogify.NewGlowEntry(object, mesh, target, barber)
    local entry = {object = object, mesh = mesh}
    local glow, resources = target and target.glow, target and target.resources
    if not glow or not glow.enabled or (resources and not (resources.mesh_path and resources.mat_path)) then return entry end
    entry.glow = glow
    if resources then entry.mesh_path, entry.material_path = resources.mesh_path, resources.mat_path end
    if barber then entry.controller, entry.editor, entry.swapper = barber.controller, barber.editor, barber.swapper end
    return entry
  end

  function Transmogify.ProcessWeaponSetGlow(set_name, main_data, off_data, right_mesh, left_mesh, apply, sheathed)
    local job = main_data and main_data:getJob() or (off_data and off_data:getJob())
    local changed = false
    for _, equip_type in ipairs(JOB_TO_WEAPON_EQUIP_INFO_TYPE_LIST[job] or {}) do
      local info = EQUIPMENT_INFO[equip_type]
      local data = off_data
      if info.slot == SLOT_MAIN_HAND then data = main_data end
      local glow = Transmogify.GetWeaponGlowSettings(set_name, equip_type, false, sheathed)
      if data and glow.enabled and GetSetTransmogValue(set_name, equip_type) ~= SET_VALUE_HIDE then
        local mesh = left_mesh
        if info.hand == RIGHT_HAND then mesh = right_mesh end
        local meshes = {mesh}
        if info.sizeBoth then meshes = {right_mesh, left_mesh} end
        for _, mesh in pairs(meshes) do
          if Transmogify.ProcessWeaponGlow(mesh, glow, apply) then
            if not apply then return true end
            changed = true
          end
        end
      end
    end
    return changed
  end
end

local CHAR_INFO_PLAYER_INDEX = 1

local function ResetCharInfoListDraw()
  Transmogify.RequestGlowCheck()
  for i, char_info in pairs(char_info_list) do
    char_info.draw_state = nil
  end
  for _, record in pairs(Transmogify.npc_draw_states) do
    record.draw_state = nil
  end
end

local function CancelWorldWeaponPreparations()
  Transmogify.CleanupWeaponPreparations(Transmogify.WEAPON_CONTEXT.WORLD)
end

local function RefreshEquipmentInfoLists()
  for equip_type, equip_info in pairs(EQUIPMENT_INFO) do
    local tmpItemList = {}
    local equip_category = equip_info.category
    local job_name_filter = job_names[equip_info.job_name_index_filter]
    local job_id_filter = EQUIP_NAME_JOB_ENUM[job_name_filter]
    if job_name_filter and job_id_filter ~= EQUIP_JOB_ALL then
      for i, item_id_name in utils.PairsByKeys(CATEGORY_ITEM_LIST[equip_category]) do
        local item_id = GetTransmogId(item_id_name)
        local job_id = ITEM_INFO_DIC[item_id][equip_category].job
        if job_id == job_id_filter then
          table.insert(tmpItemList, item_id_name)
        end
      end
    else
      tmpItemList = utils.ShallowCopy(CATEGORY_ITEM_LIST[equip_category])
    end

    local list = { SET_VALUE_NONE, SET_VALUE_HIDE }
    local search_term = ""
    if equip_info.search == nil then
      search_term = ""
    else
      search_term = string.lower(equip_info.search)
    end

    if search_term ~= "" then
      list = {}
    end

    for i, item_id_name in pairs(tmpItemList) do
      if search_term == "" or utils.StringFindRaw(string.lower(item_id_name), search_term) then
        table.insert(list, item_id_name)
      end
    end

    if #list == 0 then
      list = { SET_VALUE_NONE, SET_VALUE_HIDE }
    end

    local index = 1
    if CURRENT_SET_NAME ~= "" and CURRENT_SETTINGS.sets[CURRENT_SET_NAME] then
      local selected = CURRENT_SETTINGS.sets[CURRENT_SET_NAME][equip_type] or SET_VALUE_NONE
      index = GetIndexByVal(list, selected)
      if list[index] ~= selected then
        -- A preset stores the label it was saved with; an item whose name reads differently now is found by its ID.
        local selected_id, found = GetTransmogId(selected), false
        for position, label in ipairs(list) do
          if selected_id and GetTransmogId(label) == selected_id then
            index, found = position, true
            break
          end
        end
        if not found then
          table.insert(list, 1, selected)
          index = 1
        end
      end
    end

    EQUIPMENT_INFO[equip_type].index = index
    EQUIPMENT_INFO[equip_type].list = list
  end
end

do
  local native_data = {}
  local data_methods = {getJob = function(data) return data.job end}
  data_methods.__index = data_methods

  function Transmogify.GetNPCCharacter(id)
    local manager = sdk.get_managed_singleton("app.NPCManager")
    local holder = manager and manager:call("getNPCHolder(app.CharacterID)", id)
    if not holder or holder.CharaID ~= id or not holder:isFlagEntity() or not holder:get_entity_complete() then return nil end
    local character = holder:get_chara()
    if utils.GetGameObject(character) and character:get_CharaID() == id then return character end
  end

  -- An NPC's hand weapons as item data from their weapon IDs (ids.right, ids.left); false when the hands hold two
  -- different main weapons.
  local function NpcWeaponData(ids)
    local main, off
    for _, hand in ipairs({"right", "left"}) do
      local id = ids[hand]
      local categories = ITEM_INFO_DIC[id]
      local category = categories and (categories[CAT_SHIELD] and CAT_SHIELD or CAT_WEAPON)
      local metadata = categories and categories[category]
      if metadata and JOB_TO_WEAPON_EQUIP_INFO_TYPE_LIST[metadata.job] then
        local data = native_data[id]
        if not data then
          data = setmetatable({_WeaponId = id, _EquipCategory = category, job = metadata.job}, data_methods)
          native_data[id] = data
        end
        if category == CAT_SHIELD then off = data
        elseif not main then main = data
        elseif main._WeaponId ~= id then return false end
      end
    end
    return main, off
  end

  -- human, when given, is the character's Human that the caller has just checked.
  function Transmogify.GetWorldWeaponData(character, npc, human)
    human = human or GetCharacterHuman(character)
    if not human then return nil, nil, nil, nil, false end
    if not npc then
      local equip_data = GetEquipData(character)
      local main, main_storage = GetMainWeaponItemData(equip_data)
      local off, off_storage = GetOffWeaponItemData(equip_data)
      return main, off, main_storage, off_storage
    end
    local holder = character:get_WeaponAndItemHolder()
    if not holder then return nil, nil, nil, nil, false end
    local ids = {}
    local slots = {right = holder:get_RightWeapon(), left = holder:get_LeftWeapon()}
    for _, hand in ipairs({"right", "left"}) do
      local slot = slots[hand]
      if not slot or slot:get_field("IsStartPrepare") or slot:get_IsLinked() then return nil, nil, nil, nil, false end
      ids[hand] = slot:get_WeaponID()
    end
    local main, off = NpcWeaponData(ids)
    if main == false then return nil, nil, nil, nil, false end
    local quiver = human:get_QuiverController()
    ids.quiver = quiver and quiver.Quiver and quiver.Quiver:get_IDProp() or 0
    return main, off, nil, nil, ids
  end

  -- Item data with the fields and getJob Transmogify uses, from a weapon fact ({id, category, job}); nil without one.
  function Transmogify.GetWeaponDataFromFact(fact)
    return fact and setmetatable({_WeaponId = fact.id, _EquipCategory = fact.category, job = fact.job}, data_methods)
  end

  -- GetWorldWeaponData's results from YowaveUtils.weapons.read facts, without the storage data. A party weapon is item
  -- data with the same fields and getJob as an NPC's.
  function Transmogify.GetWorldWeaponDataFromFacts(facts, npc)
    if not npc then
      return Transmogify.GetWeaponDataFromFact(facts.main), Transmogify.GetWeaponDataFromFact(facts.off)
    end
    if not facts.holder then return nil, nil, nil, nil, false end
    local ids = {right = facts.holder.right, left = facts.holder.left}
    local main, off = NpcWeaponData(ids)
    if main == false then return nil, nil, nil, nil, false end
    ids.quiver = facts.quiver_id
    return main, off, nil, nil, ids
  end
end

-- The engine facts of a party member's menu model (see YowaveUtils.menus.read); builder is its address, or nil to find
-- it; mode is "full" (the default) or "current".
function Transmogify.ReadMenuModel(character, builder, mode)
  return YowaveUtils.menus.read(sdk.to_ptr(character), builder, SLOT_MAIN_HAND, SLOT_OFF_HAND, mode)
end

-- The weapon part facts of a GameObject or its address (see YowaveUtils.weapons.part).
function Transmogify.ReadWeaponPart(object)
  return YowaveUtils.weapons.part(sdk.to_ptr(object))
end

-- The barber's engine facts (see YowaveUtils.barber.read); mode is "full" (the default) or "current".
function Transmogify.ReadBarber(mode)
  return YowaveUtils.barber.read(SLOT_MAIN_HAND, SLOT_OFF_HAND, mode)
end

-- A cutscene's clone records (see YowaveUtils.cinematic.records); work is the WorkTimeline or its address.
function Transmogify.ReadCinematicRecords(work, weapons)
  return YowaveUtils.cinematic.records(sdk.to_ptr(work), weapons)
end

local PREVIEW_SCALE_EPSILON = 0.0001
local native_weapons = YowaveUtils.weapons

-- Applies the preset's size and visibility for the character's draw state and returns true once applied, plus whether
-- Hide when sheathed hid a weapon. show_only switches meshes on without resizing or the drawing refresh.
local function ApplyWeaponDrawState(character, set_name, npc, state, show_only)
  local facts = character and
    native_weapons.read(character:get_address(), npc == true, SLOT_MAIN_HAND, SLOT_OFF_HAND, "draw")
  if not (facts and facts.human) then return false end
  local human = facts.human
  local main_weapon_item_data, off_weapon_item_data, _, _, native_ids = Transmogify.GetWorldWeaponDataFromFacts(facts, npc)
  local hide_sheathed = Transmogify.PresetHidesSheathed(set_name) and
    (state or Transmogify.GetDrawStateFromFacts(facts, main_weapon_item_data, off_weapon_item_data)) ==
    Transmogify.DRAW_STATE.SHEATHED
  local hidden = false
  -- A tracked NPC is sized by the state the draw check applied, so the NPC pass never resizes it mid-draw.
  local sized_drawn = facts.drawn
  if npc and state then sized_drawn = state == Transmogify.DRAW_STATE.DRAWN end
  if character then
    local char_scale = facts.body_scale
    if native_ids == false then return false end

    local job = nil
    if main_weapon_item_data then
      job = main_weapon_item_data:getJob()
    elseif off_weapon_item_data then
      job = off_weapon_item_data:getJob()
    end

    if not job then return true end

    local right_weapon = facts.right and facts.right.weapon
    local left_weapon = facts.left and facts.left.weapon

    local set_info = CURRENT_SETTINGS.sets[set_name]
    local size_info = CURRENT_SETTINGS.setSize[set_name]
    local equip_info_type_list = JOB_TO_WEAPON_EQUIP_INFO_TYPE_LIST[job]

    local changed = false
    for i, equip_info_type in pairs(equip_info_type_list) do
      local equip_info = EQUIPMENT_INFO[equip_info_type]
      local slot = equip_info.slot
      local show = true
      local size = 1

      if CURRENT_SETTINGS.enabled and set_info and set_info[equip_info_type] then
        show = set_info[equip_info_type] ~= SET_VALUE_HIDE
        if size_info and size_info[equip_info_type] then
          size = size_info[equip_info_type] / 100
        end
      end
      if show and hide_sheathed and Transmogify.GetHideWhenSheathed(set_name, equip_info_type) then
        show, hidden = false, true
      end

      if size == 1 then
        size = char_scale
      end
      if CURRENT_SETTINGS.resizeOnSheathe and size > char_scale and not sized_drawn then
        size = char_scale
      end

      if slot == SLOT_MAIN_HAND and main_weapon_item_data then
        if equip_info.hand == RIGHT_HAND then
          changed = native_weapons.set_size(right_weapon, size, show, show_only, PREVIEW_SCALE_EPSILON) or changed
        elseif equip_info.hand == LEFT_HAND then
          changed = native_weapons.set_size(left_weapon, size, show, show_only, PREVIEW_SCALE_EPSILON) or changed
          if job == EQUIP_JOB_ARCHER then
            changed = native_weapons.set_size(right_weapon, size, show, show_only, PREVIEW_SCALE_EPSILON) or changed
            local quiver = facts.quiver and facts.quiver.weapon
            local quiver_size = CURRENT_SETTINGS.enabled and set_info and size_info and
              (size_info[Transmogify.QUIVER_EQUIP_TYPE] or 100) / 100 or 1
            if CURRENT_SETTINGS.resizeOnSheathe and quiver_size > 1 and not sized_drawn then quiver_size = 1 end
            changed = native_weapons.set_size(quiver, quiver_size, show, show_only, PREVIEW_SCALE_EPSILON) or changed
            if quiver_size > 0 and not show_only then
              changed = native_weapons.set_local_scale(quiver, quiver_size, PREVIEW_SCALE_EPSILON) or changed
            end
          elseif job == EQUIP_JOB_MAGIC_ARCHER then
            changed = native_weapons.set_size(right_weapon, size, show, show_only, PREVIEW_SCALE_EPSILON) or changed
          end
        end
      elseif slot == SLOT_OFF_HAND and off_weapon_item_data and left_weapon then
        changed = native_weapons.set_size(left_weapon, size, show, show_only, PREVIEW_SCALE_EPSILON) or changed
      end
    end

    if not show_only and (changed or not npc) then
      native_weapons.force_drawing(human, native_weapons.human_drawn(human))
    end
    -- A weapon shown again may carry glow the game wrote while it was hidden, which the glow hook skips; a known draw
    -- state also sets the intensity for the weapons' place.
    local uses_sheathed_glow = Transmogify.PresetUsesSheathedGlow(set_name)
    if changed or (state and uses_sheathed_glow) then
      local sheathed = false
      if uses_sheathed_glow then
        local draw_state = state
        if not draw_state then
          local current = native_weapons.read(character:get_address(), npc == true, SLOT_MAIN_HAND, SLOT_OFF_HAND, "draw")
          local main, off = Transmogify.GetWorldWeaponDataFromFacts(current, npc)
          draw_state = Transmogify.GetDrawStateFromFacts(current, main, off)
        end
        sheathed = draw_state ~= Transmogify.DRAW_STATE.DRAWN
      end
      local right_mesh = facts.right and facts.right.mesh
      local left_mesh = facts.left and facts.left.mesh
      Transmogify.ProcessWeaponSetGlow(set_name, main_weapon_item_data, off_weapon_item_data,
        right_mesh and sdk.to_managed_object(right_mesh), left_mesh and sdk.to_managed_object(left_mesh), true, sheathed)
    end
  end
  return true, hidden
end

-- part: the weapon's part facts (see Transmogify.ReadWeaponPart); body_scale: the character's, nil without its Human.
local function ResizePreviewWeapon(part, body_scale, set_name, equip_type)
  if not part or not part.weapon_object or not part.mesh or not part.mesh_ready or not part.material_ready then
    return false
  end

  local size = 1
  if equip_type then
    local percent = 100
    local set_info = CURRENT_SETTINGS.sets[set_name]
    local size_info = CURRENT_SETTINGS.setSize[set_name]
    if CURRENT_SETTINGS.enabled and set_info and size_info and
      (equip_type == Transmogify.QUIVER_EQUIP_TYPE or set_info[equip_type]) then
      percent = size_info[equip_type] or 100
    end
    if percent == 100 and equip_type ~= Transmogify.QUIVER_EQUIP_TYPE then
      if not body_scale then return false end
      size = body_scale
    else
      size = math.max(0, percent / 100)
    end
  end

  if math.abs(part.scale - size) > PREVIEW_SCALE_EPSILON then
    native_weapons.set_scale(part.weapon, size)
  end
  local current = part.local_scale
  if math.abs(current.x - size) > PREVIEW_SCALE_EPSILON or
    math.abs(current.y - size) > PREVIEW_SCALE_EPSILON or math.abs(current.z - size) > PREVIEW_SCALE_EPSILON then
    native_weapons.set_object_scale(part.weapon_object, size, size, size)
  end
  return true
end

local function HideObjDraconic(obj, hide)
  local mesh = utils.GetObjectComponent(obj, "via.render.Mesh")
  if not mesh then return end
  local value = hide and 0.0 or 1.0
  for material = 0, mesh:get_MaterialNum() - 1 do
    for variable = 0, mesh:getMaterialVariableNum(material) - 1 do
      if mesh:getMaterialVariableName(material, variable) == "DragonGrade_Enable" and
        mesh:getMaterialVariableType(material, variable) == utils.MATERIAL_FLOAT and
        mesh:getMaterialFloat(material, variable) ~= value then
        mesh:setMaterialFloat(material, variable, value)
      end
    end
  end
end

local function HideWeaponDraconic(character, hide)
  if character then
    local equip_data = GetEquipData(character)

    local rWeapon = character:get_RightWeapon()
    local main_weapon_storage_data = utils.GetSlotStorageData(equip_data, SLOT_MAIN_HAND)
    if rWeapon and main_weapon_storage_data and main_weapon_storage_data:call("get_IsDraconic") then
      HideObjDraconic(rWeapon, hide)
    end

    local lWeapon = character:get_LeftWeapon()
    local off_weapon_storage_data = utils.GetSlotStorageData(equip_data, SLOT_OFF_HAND)
    if lWeapon and off_weapon_storage_data and off_weapon_storage_data:call("get_IsDraconic") then
      HideObjDraconic(lWeapon, hide)
    end
  end
end

-- can also use PartSwapper:getParts(app.CharacterEditDefine.PartsType partsType)
local armor_parts_functions_by_slot = {
  [SLOT_HEAD] = {
    "get_HelmObj()",
    "get_HelmSubObj()",
  },
  [SLOT_BODY] = {
    "get_TopsBdObj()",
    "get_TopsBdSubObj()",
    "get_TopsWbObj()",
    "get_TopsWbSubObj()",
    "get_TopsAmObj()",
    "get_TopsAmSubObj()",
    "get_TopsBtObj()",
    "get_TopsBtSubObj()",
  },
  [SLOT_PANTS] = {
    "get_PantsLgObj()",
    "get_PantsLgSubObj()",
    "get_PantsWlObj()",
    "get_PantsWlSubObj()",
  },
  [SLOT_CAPE] = {
    "get_MantleObj()",
  },
  [SLOT_MASK_ACCESSORY] = {
    "get_FacewearObj()",
  }
}

local function HideArmorDraconic(character, hide)
  if character then
    local partSwapper = character:get_HumanPartSwapper()
    local equip_data = GetEquipData(character)
    for slot, get_obj_parts_funcs in pairs(armor_parts_functions_by_slot) do
      local armor_storage_data = utils.GetSlotStorageData(equip_data, slot)
      if armor_storage_data and armor_storage_data:call("get_IsDraconic") then
        for t, get_obj_func in pairs(get_obj_parts_funcs) do
          local armor_part_obj = partSwapper:call(get_obj_func)
          if armor_part_obj then
            HideObjDraconic(armor_part_obj, hide)
          end
        end
      end
    end
  end
end

-- The lantern check: world lanterns, menu model lanterns and cutscene clone lanterns of party members.
do
  local native_lanterns = YowaveUtils.lanterns

  -- Whether a lantern shows: the Show lantern setting, or with Hide when off its character's lantern state; nil leaves
  -- it to the game.
  local function DesiredLanternEnabled(on)
    local show, hide_when_off = CURRENT_SETTINGS.show_lantern, CURRENT_SETTINGS.hide_lantern_when_off
    if not hide_when_off then return show end
    if show then return on end
  end

  -- party: the update's party members at slots 1-4. A cutscene clone of a party member follows its lantern state.
  function Transmogify.UpdateLanterns(party)
    local characters = {}
    for slot = 1, 4 do characters[slot] = party[slot] and sdk.to_ptr(party[slot]) end
    local work = Transmogify.GetCurrentCinematic()
    if work and not (work:get_IsPlaying() or work:get_IsPaused()) then work = nil end
    local facts = native_lanterns.read(characters, work and sdk.to_ptr(work))
    local size = CURRENT_SETTINGS.lantern_size / 100
    local entries = {}
    local function Add(mesh, on)
      if mesh then entries[#entries + 1] = {mesh = mesh, enabled = DesiredLanternEnabled(on), size = size} end
    end
    for slot = 1, 4 do
      local lantern = facts[slot]
      if lantern then
        Add(lantern.world, lantern.on)
        Add(lantern.menu, lantern.on)
      end
    end
    for _, clone in ipairs(facts.clones) do Add(clone.mesh, facts[clone.slot].on) end
    if #entries > 0 then native_lanterns.apply(entries, PREVIEW_SCALE_EPSILON) end
  end
end

do
  local HAND_BOTH = 2
  local clone_types = utils.GetEnumDic("app.CloneBuilder.WeaponType")
  local arrow_id = utils.GetEnumDic("app.WeaponID").wp11_000_00
  local requests = {}

  Transmogify.WEAPON_CONTEXT = {WORLD = "world", GUI = "gui", CINEMATIC = "cinematic", BARBER = "barber"}
  Transmogify.WEAPON_PARTS = {
    right = {name = "right", clone_type = clone_types.Right, hand = RIGHT_HAND},
    left = {name = "left", clone_type = clone_types.Left, hand = LEFT_HAND},
    quiver = {name = "quiver", clone_type = clone_types.Quiver}
  }
  Transmogify.weapon_preparations = requests

  -- GetWorldWeaponData through one YowaveUtils.weapons.read, with whether each equipped weapon is draconic in place of
  -- the storage data: the Human, item data, draconic flags and native IDs; nil, then false values, without a Human.
  function Transmogify.ReadWorldWeapons(character, npc)
    local facts = native_weapons.read(character:get_address(), npc == true, SLOT_MAIN_HAND, SLOT_OFF_HAND, "equipment")
    if not facts.human then return nil, nil, nil, false, false, false end
    local main, off, _, _, native_ids = Transmogify.GetWorldWeaponDataFromFacts(facts, npc)
    return sdk.to_managed_object(facts.human), main, off, main ~= nil and facts.main ~= nil and facts.main.draconic,
      off ~= nil and facts.off ~= nil and facts.off.draconic, native_ids
  end

  local function SameObject(first, second)
    if not first or not second then return first == second end
    return sdk.to_ptr(first) == sdk.to_ptr(second)
  end

  function Transmogify.GetWeaponPreparationKey(context)
    return context.kind .. ":" .. tostring(sdk.to_ptr(context.owner)) .. ":" .. tostring(context.slot or "")
  end

  local function IsCurrent(request)
    local context = request.context
    local world = context.kind == Transmogify.WEAPON_CONTEXT.WORLD
    if world then
      if not native_weapons.valid(context.owner:get_address()) then return false end
    elseif not native_weapons.valid(sdk.to_ptr(context.owner)) then
      return false
    end
    if context.kind == Transmogify.WEAPON_CONTEXT.CINEMATIC then
      local work = Transmogify.GetCurrentCinematic()
      if not SameObject(work, context.work) or not SameObject(work and work:get_Param(), context.param) then
        return false
      end
      local facts = YowaveUtils.cinematic.current(sdk.to_ptr(context.record), context.prop and sdk.to_ptr(context.prop))
      return facts.ready and facts.source_id == context.source_id and facts.clone == sdk.to_ptr(context.owner) and
        facts.prop_valid
    end
    if world then
      if not native_weapons.valid(context.character:get_address()) then return false end
    elseif not native_weapons.valid(sdk.to_ptr(context.character)) then
      return false
    end
    local character
    if context.npc then character = Transmogify.GetNPCCharacter(context.character:get_CharaID())
    else character = select(2, GetCharInfoById(context.character:get_CharaID())) end
    if not SameObject(character, context.character) then return false end
    if context.kind == Transmogify.WEAPON_CONTEXT.BARBER then
      local facts = Transmogify.ReadBarber("current")
      if facts.controller ~= sdk.to_ptr(context.owner) or not facts.barber or facts.no_equipment or
        not facts.model_valid or facts.model ~= sdk.to_ptr(context.model) then return false end
      local ids = facts.ids
      if not ids then return false end
      for _, part in ipairs(request.parts) do
        if ids[part.spec.barber_slot + 1] ~= part.spec.weapon_id then return false end
      end
      return true
    end
    local human, main, off, _, _, native_ids = Transmogify.ReadWorldWeapons(character, context.npc)
    if native_ids == false then return false end
    if context.native_ids then
      for name, id in pairs(context.native_ids) do
        if native_ids[name] ~= id then return false end
      end
    end
    if (main and main._WeaponId) ~= context.main_id or (off and off._WeaponId) ~= context.off_id then return false end
    if context.kind == Transmogify.WEAPON_CONTEXT.GUI then
      local facts = Transmogify.ReadMenuModel(character, nil, "current")
      if facts.builder ~= sdk.to_ptr(context.owner) then return false end
      return facts.display_main == context.display_main_id and facts.display_off == context.display_off_id
    end
    return SameObject(human, context.owner)
  end

  local function IsInstalled(request, part)
    local context, object = request.context, part.object
    if not object then return false end
    if context.kind == Transmogify.WEAPON_CONTEXT.WORLD then
      if not utils.GetGameObject(context.owner) or not utils.GetGameObject(context.character) then return false end
      return SameObject(native_weapons.installed(context.character:get_address(), context.owner:get_address(),
        part.spec.part.name), object)
    end
    local owner = sdk.to_ptr(context.owner)
    if not native_weapons.object(owner) then return false end
    if context.kind ~= Transmogify.WEAPON_CONTEXT.CINEMATIC and
      not native_weapons.object(sdk.to_ptr(context.character)) then
      return false
    end
    local address = sdk.to_ptr(object)
    if context.kind == Transmogify.WEAPON_CONTEXT.BARBER then
      local objects = YowaveUtils.barber.weapons(owner)
      if not objects then return false end
      for _, installed in ipairs(objects) do
        if installed == address then return true end
      end
      return false
    end
    local entry = native_weapons.attached(owner)[part.spec.part.name]
    if entry.attached == address then return true end
    return context.kind == Transmogify.WEAPON_CONTEXT.GUI and entry.displayed == address
  end

  function Transmogify.CancelWeaponPreparation(key)
    local request = requests[key]
    if not request then return end
    requests[key] = nil
    if request.context.kind == Transmogify.WEAPON_CONTEXT.WORLD then
      Transmogify.RequestWorldGlow(request.context.character_id)
    else
      Transmogify.RequestGlowCheck()
    end
    local failure
    for _, part in ipairs(request.parts) do
      if part.initialized then
        local success, reason = pcall(function()
          local staging = part.staging:get_address()
          if not part.object then
            local prepared = native_weapons.prepared_object(staging)
            part.object = prepared and sdk.to_managed_object(prepared)
          end
          native_weapons.cancel_slot(staging, IsInstalled(request, part))
        end)
        if not success and not failure then failure = reason end
      end
    end
    if failure then error(failure) end
  end

  function Transmogify.CleanupWeaponPreparations(kind, keep)
    local failure
    for key, request in pairs(requests) do
      if (not kind or request.context.kind == kind) and (not keep or not keep[key]) then
        local success, reason = pcall(Transmogify.CancelWeaponPreparation, key)
        if not success and not failure then failure = reason end
      end
    end
    if failure then error(failure) end
  end

  function Transmogify.UpdateWeaponPreparations()
    for key, request in pairs(requests) do
      if not IsCurrent(request) then Transmogify.CancelWeaponPreparation(key) end
    end
  end

  -- Whether a preparation of that kind runs for the owner; Transmogify's glow hook leaves the owner's weapons meanwhile.
  function Transmogify.IsPreparingWeapons(kind, owner)
    local address = sdk.to_ptr(owner)
    for _, request in pairs(requests) do
      if request.context.kind == kind and sdk.to_ptr(request.context.owner) == address then return true end
    end
    return false
  end

  -- main_draconic and off_draconic: whether the equipped weapon's storage is draconic.
  function Transmogify.GetWeaponPartSpecs(main_data, off_data, main_draconic, off_draconic, set_name, native_ids, sheathed)
    local parts = {}
    for _, equipped in ipairs({{data = main_data, draconic = main_draconic}, {data = off_data, draconic = off_draconic}}) do
      local data = equipped.data
      if data then
        local hand, quiver = native_weapons.setting(data._WeaponId)
        if not hand then return nil end
        local draconic = equipped.draconic and not CURRENT_SETTINGS.hideDraconic or false
        if quiver ~= 0 then
          parts.right = {part = Transmogify.WEAPON_PARTS.right, weapon_id = arrow_id, draconic = false}
          parts.quiver = {part = Transmogify.WEAPON_PARTS.quiver, weapon_id = quiver, draconic = false}
        end
        if hand == RIGHT_HAND or hand == HAND_BOTH then
          parts.right = {part = Transmogify.WEAPON_PARTS.right, weapon_id = data._WeaponId, draconic = draconic}
        end
        if hand == LEFT_HAND or hand == HAND_BOTH then
          parts.left = {part = Transmogify.WEAPON_PARTS.left, weapon_id = data._WeaponId, draconic = draconic}
        end
      end
    end
    local job = main_data and main_data:getJob() or (off_data and off_data:getJob())
    for _, equip_type in ipairs(JOB_TO_WEAPON_EQUIP_INFO_TYPE_LIST[job] or {}) do
      local info = EQUIPMENT_INFO[equip_type]
      local data = off_data
      if info.slot == SLOT_MAIN_HAND then data = main_data end
      if data then
        local value = GetSetTransmogValue(set_name, equip_type)
        local appearance_id = GetTransmogId(value) or data._WeaponId
        local appearance = ITEM_INFO_DIC[appearance_id]
        local resources = appearance and appearance[data._EquipCategory]
        local part = parts.left
        if info.hand == RIGHT_HAND then part = parts.right end
        local glow = value ~= SET_VALUE_HIDE and Transmogify.GetWeaponGlowSettings(set_name, equip_type, false, sheathed) or
          Transmogify.GLOW.DEFAULT
        if part then
          part.resources, part.glow, part.equip_type = resources, glow, equip_type
        end
        if parts.right and resources and resources.arrow_mesh_resource then
          parts.right.resources = {mesh_resource = resources.arrow_mesh_resource, mat_resource = resources.arrow_mat_resource,
            mesh_path = resources.arrow_mesh_path, mat_path = resources.arrow_mat_path}
        end
        if parts.quiver and resources and resources.quiver_mesh_resource then
          parts.quiver.resources = {mesh_resource = resources.quiver_mesh_resource, mat_resource = resources.quiver_mat_resource,
            mesh_path = resources.quiver_mesh_path, mat_path = resources.quiver_mat_path}
        end
        if info.sizeBoth then
          if parts.right then parts.right.glow, parts.right.equip_type = glow, equip_type end
          if parts.quiver then
            parts.quiver.equip_type = Transmogify.QUIVER_EQUIP_TYPE
            parts.quiver.glow = Transmogify.GLOW.DEFAULT
          end
        end
      end
    end
    local ordered = {}
    for _, name in ipairs({"right", "left", "quiver"}) do
      local part = parts[name]
      local native_id = native_ids and native_ids[name]
      if native_id and native_id ~= 0 then
        if not part then return nil end
        part.weapon_id = native_id
        local equip_type = part.equip_type or (parts.left and parts.left.equip_type)
        if GetSetTransmogValue(set_name, equip_type) == SET_VALUE_NONE then
          local categories = ITEM_INFO_DIC[native_id]
          part.resources = categories and (categories[CAT_WEAPON] or categories[CAT_SHIELD])
        end
      end
      if part then ordered[#ordered + 1] = part end
    end
    return ordered
  end

  function Transmogify.ApplyWeaponResources(mesh, resources)
    if not resources then return false end
    local mesh_resource, mat_resource = resources.mesh_resource, resources.mat_resource
    return native_weapons.apply_resources(mesh:get_address(), mesh_resource and mesh_resource:get_address(),
      mat_resource and mat_resource:get_address(), resources.mesh_path, resources.mat_path)
  end

  function Transmogify.PrepareWeapons(context, specs)
    local key = Transmogify.GetWeaponPreparationKey(context)
    if not specs or #specs == 0 then
      Transmogify.CancelWeaponPreparation(key)
      return nil
    end
    local request = requests[key]
    if request then
      local matches = SameObject(request.context.owner, context.owner) and
        SameObject(request.context.character, context.character) and #request.parts == #specs
      for i, spec in ipairs(specs) do
        local part = request.parts[i]
        matches = matches and part and part.spec.weapon_id == spec.weapon_id and part.spec.part == spec.part and
          part.spec.barber_slot == spec.barber_slot
      end
      if not matches or not IsCurrent(request) then
        Transmogify.CancelWeaponPreparation(key)
        request = nil
      end
    end
    local success, result = pcall(function()
      if not request then
        request = {key = key, context = context, parts = {}}
        requests[key] = request
        Transmogify.RetractWeaponGlow(context)
        if not IsCurrent(request) then
          Transmogify.CancelWeaponPreparation(key)
          return nil
        end
        for _, spec in ipairs(specs) do
          local part = {spec = spec}
          request.parts[#request.parts + 1] = part
          part.staging = sdk.to_managed_object(native_weapons.create_slot()):add_ref()
          part.initialized = true
          if not native_weapons.prepare_slot(part.staging:get_address(), context.owner:get_address(), spec.weapon_id) then
            Transmogify.CancelWeaponPreparation(key)
            return nil
          end
        end
      end
      if not IsCurrent(request) then
        Transmogify.CancelWeaponPreparation(key)
        return nil
      end
      for i, part in ipairs(request.parts) do
        part.spec = specs[i]
        local object, weapon, mesh = native_weapons.poll(part.staging:get_address(), part.spec.weapon_id)
        if object == false then
          Transmogify.CancelWeaponPreparation(key)
          return nil
        end
        if not object then return nil end
        part.object, part.weapon, part.mesh = sdk.to_managed_object(object), sdk.to_managed_object(weapon),
          sdk.to_managed_object(mesh)
        if not part.original then
          local resource, material, mesh_path, mat_path = native_weapons.mesh_resources(mesh)
          part.original = {mesh_resource = sdk.to_managed_object(resource):add_ref(),
            mat_resource = sdk.to_managed_object(material):add_ref(), mesh_path = mesh_path, mat_path = mat_path}
          part.glow = utils.GetMeshGlow(part.mesh)
        end
      end
      for _, part in ipairs(request.parts) do
        native_weapons.detach(part.object:get_address(), false)
        local resources = part.spec.resources or part.original
        Transmogify.ApplyWeaponResources(part.mesh, resources)
      end
      for _, part in ipairs(request.parts) do
        if not native_weapons.mesh_ready(part.mesh:get_address()) then return nil end
      end
      for _, part in ipairs(request.parts) do
        if part.draconic ~= (part.spec.draconic == true) then
          native_weapons.set_draconic(part.object:get_address(), part.spec.draconic == true)
          part.draconic = part.spec.draconic == true
        end
        utils.SetMeshGlow(part.mesh, part.glow)
        if part.spec.glow then Transmogify.ProcessWeaponGlow(part.mesh, part.spec.glow, true) end
        utils.RefreshWeaponBlood(part.weapon)
      end
      return request
    end)
    if success then return result end
    Transmogify.CancelWeaponPreparation(key)
    error(result)
  end
end

local function UpdateGUIWeaponEnchant(char_info)
  local request = char_info.gui_weapon_enchant
  if not request then
    return
  end
  local character = char_info.character()
  local builder = character and GetMockupBuilder(character)
  if not GuiManager:isPausedGUI() or not character or sdk.to_ptr(character) ~= sdk.to_ptr(request.character) or
    character:get_CharaID() ~= request.chara_id or not builder or sdk.to_ptr(builder) ~= sdk.to_ptr(request.builder) then
    char_info.gui_weapon_enchant = nil
    return
  end
  local equip_data = GetEquipData(character)
  local main_data = GetMainWeaponItemData(equip_data)
  local off_data = GetOffWeaponItemData(equip_data)
  if (request.main_data and (not main_data or main_data._WeaponId ~= request.main_data._WeaponId)) or
    (request.off_data and (not off_data or off_data._WeaponId ~= request.off_data._WeaponId)) then
    char_info.gui_weapon_enchant = nil
    return
  end
  local builder_address = sdk.to_ptr(builder)
  local facts = YowaveUtils.menus.enchant(builder_address)
  if not facts.controller or facts.controller ~= sdk.to_ptr(request.controller) then
    char_info.gui_weapon_enchant = nil
    return
  end
  for _, target in ipairs(request.glow_targets) do
    local current = facts[target.name]
    if not current.weapon or current.object ~= (target.object and sdk.to_ptr(target.object)) or
      current.weapon ~= sdk.to_ptr(target.weapon) or current.id ~= target.weapon_id or
      not current.mesh or current.mesh ~= (target.mesh and sdk.to_ptr(target.mesh)) then
      char_info.gui_weapon_enchant = nil
      return
    end
  end
  local ready = true
  for _, part in ipairs(request.weapons) do
    local current = facts[part.is_left and "left" or "right"]
    if not current.weapon or current.weapon ~= sdk.to_ptr(part.weapon) or current.id ~= part.weapon_id then
      char_info.gui_weapon_enchant = nil
      return
    end
    if not current.info then error("The menu model has no weapon element info for the hand") end
    local replacement = current.container
    local previous = part.previous_container and sdk.to_ptr(part.previous_container)
    local no_effect = not replacement and (not previous or current.element == -1)
    if not no_effect and (not replacement or (previous and replacement == previous) or
      not current.ready_resource or current.before_start or current.finished or current.disposing) then
      ready = false
    end
  end
  if ready then
    YowaveUtils.menus.remove_effect_tag(builder_address)
    Transmogify.ProcessWeaponSetGlow(GetSetNameByCharInfo(char_info), request.main_data, request.off_data,
      request.right_mesh, request.left_mesh, true)
    char_info.gui_weapon_enchant = nil
  end
end

-- facts: the member's menu model facts (see Transmogify.ReadMenuModel); paused: whether a menu pauses the game.
local function TransmogGUIWeapons(character, set_name, facts, paused)
  if facts and facts.builder then
    local char_info = character and GetCharInfoById(character:get_CharaID())
    if not facts.human then return end
    local right, left, quiver = facts.right, facts.left, facts.quiver
    local right_weapon = right and right.weapon
    local right_data = right_weapon and Transmogify.GetWeaponDataFromFact(right.data)
    local right_mesh = right_weapon and right.mesh

    local left_weapon = left and left.weapon
    local left_data = left_weapon and Transmogify.GetWeaponDataFromFact(left.data)
    local left_mesh = left_weapon and left.mesh

    local quiver_mesh = quiver and quiver.weapon and quiver.mesh

    local mock_main_data = nil
    if right_data and right_data._EquipCategory == CAT_WEAPON then
      mock_main_data = right_data
    elseif left_data and left_data._EquipCategory == CAT_WEAPON then
      mock_main_data = left_data
    end

    local mock_off_data = nil
    if left_data and left_data._EquipCategory == CAT_SHIELD then
      mock_off_data = left_data
    end

    local equipped_main = Transmogify.GetWeaponDataFromFact(facts.main)
    local equipped_off = Transmogify.GetWeaponDataFromFact(facts.off)
    local displayed_main, displayed_off = facts.display_main, facts.display_off
    local main_matches = mock_main_data and equipped_main and displayed_main and
      mock_main_data._WeaponId == equipped_main._WeaponId and displayed_main == equipped_main._WeaponId
    local off_matches = mock_off_data and equipped_off and displayed_off and
      mock_off_data._WeaponId == equipped_off._WeaponId and displayed_off == equipped_off._WeaponId
    if not main_matches then
      mock_main_data, right_weapon, right_mesh, quiver_mesh = nil, nil, nil, nil
    elseif not EquipmentIsBow(mock_main_data) then
      quiver_mesh = nil
    end
    if not off_matches then mock_off_data = nil end
    if not off_matches and not (main_matches and left_weapon and left.id == equipped_main._WeaponId) then
      left_weapon, left_mesh = nil, nil
    end
    local mock_builder = sdk.to_managed_object(facts.builder)
    local context = {kind = Transmogify.WEAPON_CONTEXT.GUI, owner = mock_builder, character = character,
      main_id = equipped_main and equipped_main._WeaponId, off_id = equipped_off and equipped_off._WeaponId}
    context.display_main_id = displayed_main
    context.display_off_id = displayed_off
    local key = Transmogify.GetWeaponPreparationKey(context)
    if not mock_main_data and not mock_off_data then
      Transmogify.CancelWeaponPreparation(key)
      if char_info then char_info.gui_weapon_enchant = nil end
      -- After a menu closes the game may still be rebuilding this model's equipped weapons; check again once it settles.
      if not paused and not facts.complete then Transmogify.RequestGUICheck() end
      return
    end
    local job = equipped_main and equipped_main:getJob() or (equipped_off and equipped_off:getJob())
    local signature = Transmogify.GetWeaponGlowSignature(set_name, job)
    local specs = Transmogify.GetWeaponPartSpecs(mock_main_data, mock_off_data,
      mock_main_data ~= nil and facts.main.draconic, mock_off_data ~= nil and facts.off.draconic, set_name)
    if not specs then
      Transmogify.RequestGUICheck()
      return
    end
    local changed = not char_info or char_info.gui_glow_signature ~= signature
    for _, spec in ipairs(specs) do
      local part = facts[spec.part.name]
      if not part or not part.weapon_object or part.id ~= spec.weapon_id or not part.mesh or
        not part.mesh_ready or not part.material_ready then
        changed = true
      elseif spec.resources and (part.mesh_path ~= spec.resources.mesh_path or
        part.material_path ~= spec.resources.mat_path) then
        changed = true
      elseif spec.glow and not (char_info and char_info.gui_weapon_enchant) and
        Transmogify.ProcessWeaponGlow(part.mesh, spec.glow, false) then
        changed = true
      end
    end
    if not changed and not Transmogify.weapon_preparations[key] then
      if paused then
        for _, spec in ipairs(specs) do
          ResizePreviewWeapon(facts[spec.part.name], facts.body_scale, set_name, spec.equip_type)
        end
      end
      return
    end
    local request = Transmogify.PrepareWeapons(context, specs)
    if not request then
      Transmogify.RequestGUICheck()
      return
    end
    local quiver_object = quiver and quiver.object and sdk.to_managed_object(quiver.object)
    right_weapon = right_weapon and sdk.to_managed_object(right_weapon)
    left_weapon = left_weapon and sdk.to_managed_object(left_weapon)
    local quiver_weapon = quiver and quiver.weapon and sdk.to_managed_object(quiver.weapon)
    right_mesh = right_mesh and sdk.to_managed_object(right_mesh)
    left_mesh = left_mesh and sdk.to_managed_object(left_mesh)
    quiver_mesh = quiver_mesh and sdk.to_managed_object(quiver_mesh)
    local builder_address = facts.builder
    local root = native_weapons.object(builder_address)
    local _, root_draw, root_update = native_weapons.flags(root)
    local retained, replacing, previous_attached = {}, {}, {}
    local enchant = YowaveUtils.menus.enchant(builder_address)
    local controller = enchant.controller and sdk.to_managed_object(enchant.controller)
    if controller and not enchant.infos then error("The menu model's weapon element controller has no element infos") end
    local parts = native_weapons.attached(builder_address)
    local weapons = {}
    for _, part in ipairs(request.parts) do
      local descriptor = part.spec.part
      replacing[descriptor] = true
      if descriptor ~= Transmogify.WEAPON_PARTS.quiver and controller then
        local is_left = descriptor == Transmogify.WEAPON_PARTS.left
        local hand = enchant[descriptor.name]
        if hand.info then
          weapons[#weapons + 1] = {weapon = part.weapon, weapon_id = (native_weapons.identity(sdk.to_ptr(part.weapon))),
            is_left = is_left, previous_container = hand.container and sdk.to_managed_object(hand.container)}
        end
      end
      local entry = parts[descriptor.name]
      if entry.attached and entry.attached ~= entry.displayed then
        previous_attached[#previous_attached + 1] = {object = sdk.to_managed_object(entry.attached),
          descriptor = descriptor}
      end
    end
    for _, descriptor in pairs(Transmogify.WEAPON_PARTS) do
      local object = parts[descriptor.name].displayed
      if not replacing[descriptor] and object then
        local valid, draw, update = native_weapons.flags(object)
        if valid then
          retained[#retained + 1] = {object = sdk.to_managed_object(object), draw = draw, update = update}
        end
      end
    end
    local success, failure = pcall(function()
      for _, part in ipairs(request.parts) do
        native_weapons.attach_clone(builder_address, sdk.to_ptr(part.object), part.spec.part.clone_type)
      end
      for _, part in ipairs(request.parts) do
        native_weapons.set_flags(sdk.to_ptr(part.object), true, true)
        if part.spec.part == Transmogify.WEAPON_PARTS.right then
          right_weapon, right_mesh = part.weapon, part.mesh
        elseif part.spec.part == Transmogify.WEAPON_PARTS.left then
          left_weapon, left_mesh = part.weapon, part.mesh
        else
          quiver_object, quiver_weapon, quiver_mesh = part.object, part.weapon, part.mesh
        end
      end
    end)
    if native_weapons.flags(root) then native_weapons.set_flags(root, root_draw, root_update) end
    for _, entry in ipairs(retained) do
      local address = sdk.to_ptr(entry.object)
      if native_weapons.flags(address) then native_weapons.set_flags(address, entry.draw, entry.update) end
    end
    for _, previous in ipairs(previous_attached) do
      local address = sdk.to_ptr(previous.object)
      local current = native_weapons.attached(builder_address)[previous.descriptor.name]
      if native_weapons.flags(address) and current.attached ~= address and current.displayed ~= address then
        native_weapons.destroy_object(address)
      end
    end
    Transmogify.CancelWeaponPreparation(request.key)
    if not success then error(failure) end

    if paused then
      for _, part in ipairs(request.parts) do
        ResizePreviewWeapon(Transmogify.ReadWeaponPart(part.object), facts.body_scale, set_name, part.spec.equip_type)
      end
    end

    if not char_info then
      return
    end
    char_info.gui_weapon_enchant = nil
    char_info.gui_glow_signature = signature
    if not paused then
      return
    end
    local glow_targets = {}
    local displayed = native_weapons.attached(builder_address)
    for _, part in ipairs({{name = "right", weapon = right_weapon}, {name = "left", weapon = left_weapon}}) do
      if part.weapon then
        local object = displayed[part.name].displayed
        local weapon_id, mesh = native_weapons.identity(sdk.to_ptr(part.weapon))
        glow_targets[#glow_targets + 1] = {name = part.name, object = object and sdk.to_managed_object(object),
          weapon = part.weapon, weapon_id = weapon_id, mesh = mesh and sdk.to_managed_object(mesh)}
      end
    end
    if quiver_mesh then
      glow_targets[#glow_targets + 1] = {name = "quiver", object = quiver_object,
        weapon = quiver_weapon, weapon_id = (native_weapons.identity(sdk.to_ptr(quiver_weapon))), mesh = quiver_mesh}
    end
    if #weapons > 0 then
      char_info.gui_weapon_enchant = {
        character = character, chara_id = character:get_CharaID(), builder = mock_builder,
        controller = controller, weapons = weapons, glow_targets = glow_targets, main_data = mock_main_data, off_data = mock_off_data,
        right_mesh = right_mesh, left_mesh = left_mesh
      }
    end
  end
end

-- Make sure the model having the proper weapons on GUI exit
local function RefreshGUIWeaponsOnExit(character)
  if not character then return end
  YowaveUtils.menus.refresh_weapons(sdk.to_ptr(character), SLOT_MAIN_HAND, SLOT_OFF_HAND)
end

function Transmogify.PrepareWorldWeapons(character, set_name, npc)
  local human, main_data, off_data, main_draconic, off_draconic, native_ids = Transmogify.ReadWorldWeapons(character, npc)
  if not human then return nil end
  if native_ids == false then return nil end
  local context = {kind = Transmogify.WEAPON_CONTEXT.WORLD, owner = human, character = character, npc = npc,
    character_id = cm.getCharaID:call(character), main_id = main_data and main_data._WeaponId,
    off_id = off_data and off_data._WeaponId, native_ids = native_ids}
  local char_info = not npc and Transmogify.PresetUsesSheathedGlow(set_name) and
    GetCharInfoById(cm.getCharaID:call(character)) or nil
  local specs = Transmogify.GetWeaponPartSpecs(main_data, off_data, main_draconic, off_draconic, set_name, native_ids,
    Transmogify.IsGlowSheathed(character, npc, char_info, set_name))
  return Transmogify.PrepareWeapons(context, specs), main_data, off_data
end

function Transmogify.HasWorldWeaponPreparation(character)
  local human = GetCharacterHuman(character)
  if not human then return false end
  local key = Transmogify.GetWeaponPreparationKey({kind = Transmogify.WEAPON_CONTEXT.WORLD, owner = human})
  return Transmogify.weapon_preparations[key] ~= nil
end

local function RequestWeaponTransmog(char_info, character)
  Transmogify.RequestWeaponCheck()
  Transmogify.PrepareWorldWeapons(character, GetSetNameByCharInfo(char_info))
end

local function DestroyCharWeapons(character)
  if character then native_weapons.destroy(character:get_address()) end
end

local weapon_drawed_on_rearm = false
local warfarer_rearm_pending = false
local function TransmogWeapons(character, set_name, npc)
  -- The game loads the equipped weapon again after a clear; the next weapon check installs over it.
  if not npc and Transmogify.ClearGameLooks(character, Transmogify.GAME_LOOK.WEAPON_SLOTS) then
    ResetCharInfoListDraw()
    return false
  end
  local request, main_weapon_item_data, off_weapon_item_data = Transmogify.PrepareWorldWeapons(character, set_name, npc)
  if not request then return false end
  local human = request.context.owner
  local character_address, human_address = character:get_address(), human:get_address()
  local meshes = {}
  local drawn = native_weapons.human_drawn(human_address)
  local char_info = GetCharInfoById(character:get_CharaID())
  local success, failure = pcall(function()
    DestroyCharWeapons(character)
    for _, part in ipairs(request.parts) do
      local name = part.spec.part.name
      native_weapons.equip(character_address, human_address, name, part.weapon:get_address())
      meshes[name] = part.mesh
    end
    if not npc and IsWarfarer(character) then
      native_weapons.start_appear(character_address, human_address)

      if Transmogify_Warfarer_Started then
        Transmogify_Warfarer_Finished_Transmog(character)
        warfarer_rearm_pending = false
      elseif weapon_drawed_on_rearm then
        character:get_HumanActionSelector():requestDrawWeapon()
        weapon_drawed_on_rearm = false
        warfarer_rearm_pending = false
      else
        warfarer_rearm_pending = false
      end
    end
    local _, hidden = ApplyWeaponDrawState(character, set_name, npc,
      Transmogify.GetAppliedDrawState(character, npc, char_info))
    if char_info then char_info.sheathe_hidden = hidden end
    if npc then native_weapons.force_drawing(human_address, drawn) end
    Transmogify.ProcessWeaponSetGlow(set_name, main_weapon_item_data, off_weapon_item_data,
      meshes.right, meshes.left, true, Transmogify.IsGlowSheathed(character, npc, char_info, set_name))
    if char_info then
      local job = main_weapon_item_data and main_weapon_item_data:getJob() or (off_weapon_item_data and off_weapon_item_data:getJob())
      char_info.weapon_glow_signature = Transmogify.GetWeaponGlowSignature(set_name, job)
      char_info.weapon_glow_character = sdk.to_ptr(character)
    end
  end)
  Transmogify.CancelWeaponPreparation(request.key)
  if not success then error(failure) end
  if char_info then
    char_info.draw_state = nil
    Transmogify.draw_check_countdown = Transmogify.DRAW_CHECK.INTERVAL
  end
  return true
end

function Transmogify.RestoreWeaponsForSave(character)
  local human = character and character:get_Human()
  if not utils.GetGameObject(human) then return end
  local equip_data = GetEquipData(character)
  local main_data, main_storage = GetMainWeaponItemData(equip_data)
  local off_data, off_storage = GetOffWeaponItemData(equip_data)
  local specs = Transmogify.GetWeaponPartSpecs(main_data, off_data,
    main_data ~= nil and main_storage ~= nil and main_storage:call("get_IsDraconic"),
    off_data ~= nil and off_storage ~= nil and off_storage:call("get_IsDraconic"), SET_VALUE_NONE)
  if not specs then return end
  local detached = {}
  -- Save serialization cannot wait for asynchronous weapon creation.
  local success, failure = pcall(function()
    for _, spec in ipairs(specs) do
      local weapon
      if spec.part == Transmogify.WEAPON_PARTS.right then weapon = character:get_RightWeapon()
      elseif spec.part == Transmogify.WEAPON_PARTS.left then weapon = character:get_LeftWeapon()
      else
        local quiver = human:get_QuiverController()
        weapon = quiver and quiver.Quiver
      end
      local object = utils.GetGameObject(weapon)
      local mesh = object and weapon.Mesh
      if mesh and mesh:get_MeshReady() and mesh:get_MaterialReady() and spec.resources then
        local transform, parent = native_weapons.detach(object:get_address(), true)
        detached[#detached + 1] = {transform = transform, parent = parent}
        if Transmogify.ApplyWeaponResources(mesh, spec.resources) then utils.RefreshWeaponBlood(weapon) end
      end
    end
  end)
  for _, entry in ipairs(detached) do
    native_weapons.attach(entry.transform, entry.parent)
  end
  if not success then error(failure) end
  ApplyWeaponDrawState(character, SET_VALUE_NONE)
end

do
  local PARTY_CLOTHING_DEFAULTS = {
    [CAT_BACKPACK] = STYLE_NONE,
    [CAT_UNDERWEAR] = utils.GetEnumDic("app.UnderwearStyle").Underwear_000,
  }
  local unavailable_styles = {}
  local native_armor = YowaveUtils.armor
  local ARMOR_CONFIG = {}
  for category, field in pairs(META_CATEGORY_FIELD_NAME_ENUM) do
    ARMOR_CONFIG[#ARMOR_CONFIG + 1] = {category = category, field = field,
      setter = META_CATEGORY_SET_STYLE_FUNCTION_SIG_ENUM[category], style = ITEM_MANAGER_CATEGORY_GET_STYLE_FUNC_ENUM[category],
      slot = ARMOR_CATEGORY_TO_SLOT_ENUM[category]}
  end
  native_armor.configure(ARMOR_CONFIG)

  -- The facts Transmogify's armor decisions use (see YowaveUtils.armor.read): mode "world" takes the character,
  -- "builder" a MockupBuilder, "equipment" a PartSwapper and the character whose equipment it shows, "swapper" a
  -- PartSwapper alone; each may be its address. targets maps equipment categories to preset style numbers to resolve.
  function Transmogify.ReadArmor(mode, owner, character, targets)
    return native_armor.read(mode, owner and sdk.to_ptr(owner), character and sdk.to_ptr(character), targets)
  end

  -- (swapper address, desired styles): writes the styles that differ, then requests a swap when any did; returns
  -- whether any did.
  Transmogify.ApplyArmor = native_armor.apply

  -- The preset's style numbers for the equipment categories, for ReadArmor to resolve.
  function Transmogify.GetArmorTargets(set_name)
    local targets = {}
    for category in pairs(ITEM_MANAGER_CATEGORY_GET_STYLE_FUNC_ENUM) do
      local style_no = GetTransmogId(GetSetTransmogValue(set_name, ARMOR_CATEGORY_TO_EQUIPMENT_INFO_TYPE[category]))
      if style_no then targets[category] = style_no end
    end
    return targets
  end

  -- A preset style number's style: equipment categories resolved by ReadArmor, the others from the catalog.
  function Transmogify.GetTargetArmorStyle(facts, category, style_no)
    if EXTRA_ARMOR_CATEGORIES[category] then return GetArmorStyle(category, style_no) end
    return assert(facts.resolved[category], "Armor style was not resolved: " .. tostring(category))
  end

  function Transmogify.IsClothingStyleAvailable(category, style_no, gender)
    local by_category = ITEM_INFO_DIC[style_no]
    local entry = by_category and by_category[category]
    assert(entry, "Unknown clothing style: " .. tostring(style_no))
    if entry.genders[gender] == true then return true end
    local warning = tostring(category) .. ":" .. style_no .. ":" .. tostring(gender)
    if not unavailable_styles[warning] then
      unavailable_styles[warning] = true
      utils.Log("Clothing style is unavailable for this form: " .. entry.id_name)
    end
    return false
  end

  -- facts from ReadArmor with the equipment read; nil without meta or equipment data.
  function Transmogify.GetDesiredArmorStyles(facts, set_name)
    if not facts.meta or not facts.items then return nil end
    local desired = {}
    for _, category in pairs(ARMOR_SLOT_TO_CATEGORY_ENUM) do
      local item = facts.items[category]
      local matching_display = not facts.display or facts.display[category] == (item and item.id)
      if matching_display then
        local equip_type = ARMOR_CATEGORY_TO_EQUIPMENT_INFO_TYPE[category]
        local value = GetSetTransmogValue(set_name, equip_type)
        local allow_empty = Transmogify.GetShowWhenUnequipped(set_name, equip_type)
        local style_no = GetTransmogId(value)
        local style = item and item.style or STYLE_NONE
        if item or allow_empty then
          if value == SET_VALUE_HIDE then style = STYLE_NONE
          elseif style_no then style = Transmogify.GetTargetArmorStyle(facts, category, style_no) end
        end
        desired[category] = style
      end
    end
    for category, extra in pairs(EXTRA_ARMOR_CATEGORIES) do
      local value = GetSetTransmogValue(set_name, extra.label)
      local style_no = GetTransmogId(value)
      local style = PARTY_CLOTHING_DEFAULTS[category]
      if value == SET_VALUE_HIDE then
        style = STYLE_NONE
      elseif style_no and Transmogify.IsClothingStyleAvailable(category, style_no, facts.gender) then
        style = GetArmorStyle(category, style_no)
      end
      desired[category] = style
    end
    return desired
  end

  -- Reads the owner's armor (see ReadArmor) and applies the preset's styles, requesting a swap when any changed.
  function Transmogify.ApplyArmorStyles(mode, owner, character, set_name)
    local facts = Transmogify.ReadArmor(mode, owner, character, Transmogify.GetArmorTargets(set_name))
    local desired = Transmogify.GetDesiredArmorStyles(facts, set_name)
    if not desired then return false end
    return Transmogify.ApplyArmor(facts.swapper, desired)
  end

  function Transmogify.RestoreClothingForSave(character)
    local world = character and character:get_HumanPartSwapper()
    if not world or not utils.GetGameObject(world) then return end
    local facts = Transmogify.ReadArmor("world", nil, character)
    if not facts.meta or not facts.items then return end
    local desired = utils.ShallowCopy(PARTY_CLOTHING_DEFAULTS)
    for _, category in pairs(ARMOR_SLOT_TO_CATEGORY_ENUM) do
      if not facts.items[category] then desired[category] = STYLE_NONE end
    end
    Transmogify.ApplyArmor(facts.swapper, desired)
  end
end

-- The game's layered equipment (game version 4.0.0.0) gives one inventory item another item's look. Transmogify owns
-- the equipment look while it is installed, so its writes remove such looks with the call the game's own service
-- makes when the original look is chosen.
Transmogify.GAME_LOOK = {WEAPON_SLOTS = {SLOT_MAIN_HAND, SLOT_OFF_HAND}, ARMOR_SLOTS = {}, ORIGINAL = 0}
for slot in pairs(ARMOR_SLOT_TO_CATEGORY_ENUM) do table.insert(Transmogify.GAME_LOOK.ARMOR_SLOTS, slot) end

-- Removes the game's look from the character's items in slots; returns whether any had one. The game copies the item's
-- inventory entry back into the passed storage, so a look still set there was not removed.
function Transmogify.ClearGameLooks(character, slots)
  local equip_data = GetEquipData(character)
  local cleared = false
  for _, slot in ipairs(slots) do
    local storage = utils.GetSlotStorageData(equip_data, slot)
    if storage and storage:call("get_IsSetAppearanceItemId") then
      local name = utils.ExpandMessageTags(storage._ItemData:get_Name()) or storage._ItemData:get_Name()
      Transmogify.HOOKS.setEquipAppearance:call(ItemManager, storage, Transmogify.GAME_LOOK.ORIGINAL, character, true,
        false)
      if storage:call("get_IsSetAppearanceItemId") then
        error("The game's layered equipment look stayed on " .. name)
      end
      utils.Log("[" .. modname .. "] Removed the game's layered equipment look from " .. name)
      cleared = true
    end
  end
  return cleared
end

local function TransmogArmors(character, set_name)
  if not character then return end
  Transmogify.ClearGameLooks(character, Transmogify.GAME_LOOK.ARMOR_SLOTS)
  Transmogify.ApplyArmorStyles("world", nil, character, set_name)
end

-- Editor equipment events restart the countdown so the check waits a full interval after the last event.
local function RefreshBarberTransmog()
  Transmogify.barber_check_countdown = Transmogify.BARBER_CHECK.INTERVAL
end

local function UpdateBarberTransmog()
  if Transmogify.IsAppearanceBusy() then return end
  local facts = Transmogify.ReadBarber()
  if not facts.controller or not facts.barber or facts.no_equipment or not facts.slot then return end
  local char_info, character = char_info_list[facts.slot + 1], sdk.to_managed_object(facts.character)
  if not facts.model or not facts.model_valid then
    return
  end
  if facts.apply_flag ~= 0 or not facts.swapper or facts.swapping then return end
  local set_name = GetSetNameByCharInfo(char_info)
  local state = char_info.barber_glow
  local controller_address, model_address = facts.controller, facts.model
  -- Glow the hook wrote before this state existed belongs to an earlier barber model.
  local hook_applied = YowaveUtils.glow.applied()
  if not state or state.controller ~= controller_address or state.model ~= model_address then
    state = {controller = controller_address, model = model_address, needs_native_restore = true, applied = {}}
    char_info.barber_glow = state
  else
    for _, object in ipairs(hook_applied or {}) do state.applied[object] = true end
  end

  local main_data = Transmogify.GetWeaponDataFromFact(facts.main)
  local off_data = Transmogify.GetWeaponDataFromFact(facts.off)
  local equip_types = main_data and JOB_TO_WEAPON_EQUIP_INFO_TYPE_LIST[main_data:getJob()]
  local bow_type
  local weapon_ids = facts.ids
  if main_data and EquipmentIsBow(main_data) and facts.weared_job ~= 0 then
    if weapon_ids and weapon_ids[2] == main_data._WeaponId then
      for _, equip_type in ipairs(equip_types or {}) do
        if EQUIPMENT_INFO[equip_type].slot == SLOT_MAIN_HAND then bow_type = equip_type; break end
      end
    end
  end
  local targets, applied = {}, {}
  local object_values = facts.objects or {}
  local object_count = #object_values
  local restore, weapons_ready = false, object_count > 0
  for i = 1, object_count do
    local part = object_values[i]
    if not part or not part.valid then
      weapons_ready = false
    else
      local address = part.object
      applied[address] = state.applied[address]
      local hide = CURRENT_SETTINGS.hide_weapons_in_barber
      local weapon = part.weapon
      local equip_type, resources, size_type
      if weapon and main_data and part.id == main_data._WeaponId then
        local hand = part.left and LEFT_HAND or RIGHT_HAND
        for _, candidate in ipairs(equip_types or {}) do
          local equip_info = EQUIPMENT_INFO[candidate]
          if equip_info.slot == SLOT_MAIN_HAND and equip_info.hand == hand then
            equip_type = candidate
            local value = GetSetTransmogValue(set_name, equip_type)
            hide = hide or value == SET_VALUE_HIDE
            local weapon_id = GetTransmogId(value) or main_data._WeaponId
            local item_info = ITEM_INFO_DIC[weapon_id]
            resources = item_info and item_info[main_data._EquipCategory]
            break
          end
        end
      elseif weapon and off_data and part.id == off_data._WeaponId and off_data._EquipCategory == CAT_SHIELD then
        equip_type = EQUIPMENT_INFO_SHIELD
      end
      size_type = equip_type
      if not equip_type and weapon and bow_type then
        local weapon_id = part.id
        if weapon_id ~= 0 and weapon_id == weapon_ids[4] then
          equip_type, size_type = Transmogify.QUIVER_EQUIP_TYPE, Transmogify.QUIVER_EQUIP_TYPE
          hide = hide or GetSetTransmogValue(set_name, bow_type) == SET_VALUE_HIDE
        elseif weapon_id ~= 0 and weapon_id == weapon_ids[3] then
          equip_type = bow_type
        end
      end
      local show = not hide
      if part.draw ~= show then
        native_weapons.set_flags(part.object, show, nil)
      end
      local mesh = weapon and part.mesh
      local ready = mesh and part.mesh_object and part.mesh_ready and part.material_ready
      if not ready then weapons_ready = false end
      if equip_type then
        local glow = Transmogify.GetWeaponGlowSettings(set_name, equip_type)
        if GetSetTransmogValue(set_name, equip_type) == SET_VALUE_HIDE then glow = Transmogify.GLOW.DEFAULT end
        if not hide and (state.needs_native_restore or (applied[address] and not glow.enabled)) then
          restore = true
        end
        targets[#targets + 1] = {part = part, weapon = weapon, mesh = mesh, address = address, size_type = size_type,
          resources = resources, hide = hide, ready = ready, glow = glow}
      end
    end
  end
  state.applied = applied

  Transmogify.ApplyArmorStyles("equipment", facts.swapper, character, set_name)

  local controller = sdk.to_managed_object(facts.controller)
  local context = {kind = Transmogify.WEAPON_CONTEXT.BARBER, owner = controller, character = character,
    model = sdk.to_managed_object(facts.model)}
  local specs = {}
  local can_restore = weapons_ready and facts.weared_job ~= 0 and facts.wait_count < 0 and
    facts.model_draw and facts.model_update
  if weapon_ids and (not restore or can_restore) then
    for _, target in ipairs(targets) do
      local resources = target.resources
      local differs = target.ready and resources and (target.part.mesh_path ~= resources.mesh_path or
        target.part.material_path ~= resources.mat_path)
      if restore or (not target.hide and differs) then
        target.replacing = true
        local id = target.part.id
        local slot
        if id == weapon_ids[3] then slot = 2
        elseif id == weapon_ids[4] then slot = 3
        elseif target.part.left and id == weapon_ids[2] then slot = 1
        elseif id == weapon_ids[1] then slot = 0
        elseif id == weapon_ids[2] then slot = 1 end
        if slot ~= nil then
          local descriptor = Transmogify.WEAPON_PARTS.right
          if slot == 1 then descriptor = Transmogify.WEAPON_PARTS.left
          elseif slot == 3 then descriptor = Transmogify.WEAPON_PARTS.quiver end
          specs[#specs + 1] = {part = descriptor, weapon_id = id, barber_slot = slot, target = target,
            resources = not target.hide and resources or nil,
            glow = not target.hide and target.glow or Transmogify.GLOW.DEFAULT, draconic = false}
        end
      end
    end
  end
  local request = Transmogify.PrepareWeapons(context, specs)
  if request then
    local success, failure = pcall(function()
      for _, part in ipairs(request.parts) do
        YowaveUtils.barber.install(controller_address, sdk.to_ptr(part.object), part.spec.barber_slot,
          part.spec.weapon_id)
      end
    end)
    local finalized, finalize_error = pcall(function()
      local installed = {}
      for _, object in ipairs(YowaveUtils.barber.weapons(controller_address)) do
        if object then installed[object] = true end
      end
      local all_installed = true
      for _, part in ipairs(request.parts) do
        local object = sdk.to_ptr(part.object)
        if installed[object] then
          local target = part.spec.target
          YowaveUtils.barber.remove(controller_address, target.part.object)
          state.applied[target.address] = nil
          target.weapon, target.mesh = part.weapon, part.mesh
          target.address, target.ready = object, true
          target.replacing = false
          native_weapons.set_flags(object, not target.hide, nil)
          target.part = Transmogify.ReadWeaponPart(part.object)
          state.applied[target.address] = not target.hide and target.glow.enabled or nil
        else
          all_installed = false
        end
      end
      if restore and all_installed then
        state.needs_native_restore = false
        restore = false
      end
    end)
    Transmogify.CancelWeaponPreparation(request.key)
    if not success then error(failure) end
    if not finalized then error(finalize_error) end
  end
  for _, target in ipairs(targets) do
    if target.size_type then ResizePreviewWeapon(target.part, facts.body_scale, set_name, target.size_type) end
    if not restore and not target.replacing and not target.hide and target.ready and
      Transmogify.ProcessWeaponGlow(target.mesh, target.glow, true) then
      state.applied[target.address] = true
    end
  end
end

do
  local STORAGE_NAME = "Transmogify.NativeStorage"
  local STORAGE_COMPONENT = "via.gui.Memo"
  local STORAGE_HOST = "app.GameSystemBehavior"
  local STORAGE_VERSION = 1
  local CINEMATIC_KEY = "cinematic"
  local storage_cache = {}

  -- Each name is a separate resident document; a caller that stores large data uses its own name so other writers
  -- do not re-encode it.
  function Transmogify.GetNativeStorage(name)
    name = name or STORAGE_NAME
    local cached = storage_cache[name]
    if cached and cached.object:get_Valid() and cached.memo:get_Valid() then
      return cached.memo
    end
    storage_cache[name] = nil
    local scene = utils.GetCurrentScene()
    if not scene then
      return nil
    end
    local hosts, host_count = utils.GetLuaArray(scene:call("findComponents(System.Type)", sdk.typeof(STORAGE_HOST)))
    if host_count ~= 1 then
      return nil
    end
    local host = utils.GetGameObject(hosts[1])
    if not host or not host:get_Valid() then
      return nil
    end
    local host_transform = host:get_Transform()
    local object = scene:call("findGameObject(System.String)", name)
    local memo
    if object and object:get_Valid() then
      if sdk.to_ptr(object:get_Transform():get_Parent()) ~= sdk.to_ptr(host_transform) then
        error("Transmogify native storage has an unexpected owner")
      end
      memo = utils.GetObjectComponent(object, STORAGE_COMPONENT)
      if not memo or not memo:get_Valid() then
        error("Transmogify native storage Memo is missing")
      end
    else
      object = sdk.find_type_definition("via.GameObject"):get_method("create(System.String)"):call(nil, name)
      if not object or not object:get_Valid() then
        error("Transmogify native storage creation failed")
      end
      local success, failure = pcall(function()
        memo = object:call("createComponent(System.Type)", sdk.typeof(STORAGE_COMPONENT))
        if not memo or not memo:get_Valid() then
          error("Transmogify native storage Memo creation failed")
        end
        memo:set_Enabled(false)
        local text = json.dump_string({version = STORAGE_VERSION, data = {}}, -1)
        if text == "" then
          error("Transmogify native storage encoding failed")
        end
        memo:set_field("Text", text)
        if memo:get_field("Text") ~= text then
          error("Transmogify native storage initialization did not round-trip")
        end
        local transform = object:get_Transform()
        transform:call("setParent(via.Transform, System.Boolean)", host_transform, false)
        if sdk.to_ptr(transform:get_Parent()) ~= sdk.to_ptr(host_transform) then
          error("Transmogify native storage did not attach to the resident owner")
        end
      end)
      if not success then
        sdk.find_type_definition("via.GameObject"):get_method("destroy(via.GameObject)"):call(nil, object)
        error(failure)
      end
    end
    storage_cache[name] = {object = object:add_ref(), memo = memo:add_ref()}
    return storage_cache[name].memo
  end

  local function ReadNativeStorageDocument(name)
    local memo = Transmogify.GetNativeStorage(name)
    if not memo then
      return nil
    end
    local text = memo:get_field("Text")
    local document = text and json.load_string(text)
    if type(document) ~= "table" or document.version ~= STORAGE_VERSION then
      error("Transmogify native storage JSON/schema is invalid")
    end
    -- REFramework encodes empty tables as JSON null, which decodes to nil.
    if document.data == nil then
      document.data = {}
    elseif type(document.data) ~= "table" then
      error("Transmogify native storage data is invalid")
    end
    return document, memo, text
  end

  function Transmogify.GetNativeData(key, name)
    local document = ReadNativeStorageDocument(name)
    if not document then
      return nil, false
    end
    if key == nil then
      return document.data, true
    end
    return document.data[key], true
  end

  function Transmogify.SetNativeData(key, value, name)
    if type(key) ~= "string" then
      error("Transmogify native storage key must be a string")
    end
    local document, memo, original = ReadNativeStorageDocument(name)
    if not document then
      return false
    end
    document.data[key] = value
    local text = json.dump_string(document, -1)
    if text == "" then
      error("Transmogify native storage encoding failed")
    end
    local success, failure = pcall(function()
      memo:set_field("Text", text)
      if memo:get_field("Text") ~= text then
        error("Transmogify native storage write did not round-trip")
      end
    end)
    if not success then
      memo:set_field("Text", original)
      error(failure)
    end
    return true
  end

  function Transmogify.GetCurrentCinematic()
    local mediator = sdk.get_managed_singleton("app.DemoMediator")
    if not mediator then
      return nil, false
    end
    local work = mediator:get_CurrentExclusivePlayWork()
    if work then
      if work:get_type_definition():get_full_name() == "app.DemoMediator.WorkTimeline" then
        return work, false
      end
      return nil, false
    end
    local finished = not mediator:checkRequestedPlayingCommand() and
      not mediator:get_IsRequestLoadEnvironment() and not mediator:get_field("IsSetRevertEnvironment")
    return nil, finished
  end

  -- record: the clone record's facts (see Transmogify.ReadCinematicRecords).
  local function IsCinematicTransmogEnabled(record)
    return CURRENT_SETTINGS.enabled and (CURRENT_SETTINGS.cinematic_transmog or not record.record_swapper)
  end

  -- facts from Transmogify.ReadArmor in "swapper" mode with the preset's targets; record is the clone record's facts.
  function Transmogify.ShouldTransmogCinematicArmor(facts, set_name, original, record, npc)
    if npc then return Transmogify.ShouldTransmogNPCArmor(facts, set_name, original) end
    local desired = {}
    local changed = false
    local enabled = IsCinematicTransmogEnabled(record)
    for category, field in pairs(META_CATEGORY_FIELD_NAME_ENUM) do
      local current = facts.styles[category]
      local style = original and original.styles[field]
      if style == nil then style = current end
      local equip_type = ARMOR_CATEGORY_TO_EQUIPMENT_INFO_TYPE[category]
      if enabled and (EXTRA_ARMOR_CATEGORIES[category] or style ~= STYLE_NONE or
        Transmogify.GetShowWhenUnequipped(set_name, equip_type)) then
        local value = GetSetTransmogValue(set_name, equip_type)
        local style_no = GetTransmogId(value)
        if value == SET_VALUE_HIDE then
          style = STYLE_NONE
        elseif style_no then
          local extra = EXTRA_ARMOR_CATEGORIES[category]
          if not extra or Transmogify.IsClothingStyleAvailable(category, style_no, facts.gender) then
            style = Transmogify.GetTargetArmorStyle(facts, category, style_no)
          end
        end
      end
      if type(style) ~= "number" then
        error("Cinematic armor style is unavailable")
      end
      desired[category] = style
      changed = changed or current ~= style
    end
    return changed, desired
  end

  local CINEMATIC_WEAPON_HANDS = {
    {field = "RightWeaponObj", attached = "_AttachedRightWeaponObject", part = "right", joint = "r_propa", hand = RIGHT_HAND, kind = "Right", category = CAT_WEAPON},
    {field = "LeftWeaponObj", attached = "_AttachedLeftWeaponObject", part = "left", joint = "l_propa", hand = LEFT_HAND, kind = "Left", category = CAT_WEAPON},
    {field = "LeftWeaponObj", attached = "_AttachedLeftWeaponObject", part = "left", joint = "l_prop_forearma", hand = LEFT_HAND, kind = "Left", category = CAT_SHIELD},
  }
  local CINEMATIC_SCALE_EPSILON = 0.0001

  local cinematic_mesh_catalog, cinematic_weapon_bases

  function Transmogify.ResetCinematicWeaponCatalog()
    cinematic_mesh_catalog, cinematic_weapon_bases = nil, nil
  end

  local function GetCinematicWeaponProfile(weapon_id, category, hand)
    if category ~= hand.category then return nil end
    local by_category = ITEM_INFO_DIC[weapon_id]
    local metadata = by_category and by_category[category]
    if not metadata then
      return nil
    end
    local equip_type
    for _, candidate in ipairs(JOB_TO_WEAPON_EQUIP_INFO_TYPE_LIST[metadata.job] or {}) do
      local info = EQUIPMENT_INFO[candidate]
      if info.category == category and info.hand == hand.hand then
        equip_type = candidate
        break
      end
    end
    if not equip_type then
      return nil
    end
    local bases = cinematic_weapon_bases[category]
    local base = bases and bases[metadata.job]
    if not base then return nil end
    local item = ItemManager:call("getItemData(app.WeaponID)", base.weapon_id)
    local weapon_param = item and item:get_WeaponParam()
    if not weapon_param then return nil end
    return {weapon_id = weapon_id, base_weapon_id = base.weapon_id,
      category = category, equip_type = equip_type, weapon_param = weapon_param}
  end

  local function GetCinematicWeaponTargets(work, originals)
    if not cinematic_mesh_catalog then
      cinematic_mesh_catalog, cinematic_weapon_bases = {}, {}
      for weapon_id, categories in pairs(ITEM_INFO_DIC) do
        for category, metadata in pairs(categories) do
          if (category == CAT_WEAPON or category == CAT_SHIELD) and metadata.mesh_path and
            metadata.job and metadata.job > EQUIP_JOB_ALL then
            local path = metadata.mesh_path:lower():gsub("\\", "/")
            local existing = cinematic_mesh_catalog[path]
            local item_id = metadata.item_id or math.huge
            if not existing then
              cinematic_mesh_catalog[path] = {weapon_id = weapon_id, item_id = item_id,
                job = metadata.job, category = category}
            elseif existing.job ~= metadata.job or existing.category ~= category then
              existing.conflict = true
            elseif item_id < existing.item_id or
              (item_id == existing.item_id and weapon_id < existing.weapon_id) then
              existing.weapon_id, existing.item_id = weapon_id, item_id
            end
            local bases = cinematic_weapon_bases[category] or {}
            cinematic_weapon_bases[category] = bases
            local base = bases[metadata.job]
            if metadata.item_id and (not base or item_id < base.item_id or
              (item_id == base.item_id and weapon_id < base.weapon_id)) then
              local item = ItemManager:call("getItemData(app.WeaponID)", weapon_id)
              local weapon_param = item and item:get_WeaponParam()
              if weapon_param and weapon_param._WeaponId == weapon_id and
                weapon_param._EquipCategory == category and weapon_param:getJob() == metadata.job then
                bases[metadata.job] = {weapon_id = weapon_id, item_id = item_id}
              end
            end
          end
        end
      end
    end
    local records = Transmogify.ReadCinematicRecords(work, true)
    if not records then error("Cinematic clone records are unavailable") end
    local owners, by_index, targets = {}, {}, {}
    local tracked_npcs = {}
    for _, original in pairs(originals) do
      if original.npc then tracked_npcs[original.source_id] = true end
    end
    local has_target = false
    for index, entry in ipairs(records) do
      if entry.actor and entry.timeline_valid and entry.clone and entry.clone_valid then
        local source_id = entry.source_id
        local owner = {entry = entry, clone = entry.clone, root = entry.root, props = {}, source_id = source_id,
          event_name = entry.event_name}
        owners[#owners + 1] = owner
        by_index[index] = owner
        local char_info, character = GetCharInfoById(source_id)
        local npc = not char_info and (Transmogify.GetNPCSetName(source_id) ~= SET_VALUE_NONE or tracked_npcs[source_id])
        if entry.ready and (character or npc) and entry.controller and entry.controller_ready then
          owner.character, owner.char_info, owner.controller, owner.npc = character, char_info, entry.controller, npc
          has_target = true
        end
      end
    end
    if not has_target then return targets end
    -- A prop's owners are record positions, false for an object more than one clone holds, or nil.
    local function owner_at(index)
      if index then return by_index[index] end
      return index
    end
    for _, prop in ipairs(YowaveUtils.cinematic.props(sdk.to_ptr(work))) do
      local linked, referenced, parent_owner = owner_at(prop.linked), owner_at(prop.referenced), owner_at(prop.parent)
      local owner = linked or referenced or parent_owner
      local conflict = linked == false or referenced == false or parent_owner == false or
        (owner and ((linked and linked ~= owner) or (referenced and referenced ~= owner) or
          (parent_owner and parent_owner ~= owner)))
      if owner and not conflict and prop.joint then
        prop.key = tostring(prop.object)
        local props = owner.props[prop.joint] or {}
        props[#props + 1] = prop
        owner.props[prop.joint] = props
      end
    end
    for _, owner in ipairs(owners) do
      if owner.controller then
        for _, hand in ipairs(CINEMATIC_WEAPON_HANDS) do
          local props = owner.props[hand.joint] or {}
          local slot_props = 0
          for _, attachment in ipairs(CINEMATIC_WEAPON_HANDS) do
            if attachment.field == hand.field then
              slot_props = slot_props + #(owner.props[attachment.joint] or {})
            end
          end
          local part = owner.entry[hand.part]
          local weapon = part and part.weapon
          local mesh = weapon and part.mesh
          local profile, prop
          if #props == 1 and slot_props == 1 then
            prop = props[1]
            local match = cinematic_mesh_catalog[prop.path]
            if match and not match.conflict then
              profile = GetCinematicWeaponProfile(match.weapon_id, match.category, hand)
            end
          end
          if profile and (not part or (mesh and part.mesh_valid)) then
            targets[#targets + 1] = {
              owner = owner, clone = owner.clone, controller = owner.controller, character = owner.character,
              char_info = owner.char_info, source_id = owner.source_id, event_name = owner.event_name,
              hand = hand, part = part, object = part and part.object, weapon = weapon, mesh = mesh, prop = prop,
              weapon_id = profile.weapon_id, base_weapon_id = profile.base_weapon_id, weapon_param = profile.weapon_param,
              category = profile.category, equip_type = profile.equip_type,
              key = tostring(owner.clone) .. ":" .. tostring(owner.event_name) .. ":" .. hand.field ..
                ":prop:" .. prop.key,
            }
          end
        end
      end
    end
    return targets
  end

  -- target: one of GetCinematicWeaponTargets' targets, with its weapon part and prop facts.
  function Transmogify.ShouldTransmogCinematicWeapon(target, set_name, original)
    local part, prop = target.part, target.prop
    local mesh = target.mesh
    local enabled = CURRENT_SETTINGS.enabled and (target.owner.npc or IsCinematicTransmogEnabled(target.owner.entry))
    local value = enabled and GetSetTransmogValue(set_name, target.equip_type) or SET_VALUE_NONE
    local size_info = enabled and CURRENT_SETTINGS.setSize[set_name]
    local percent = size_info and size_info[target.equip_type] or 100
    local glow = enabled and value ~= SET_VALUE_HIDE and Transmogify.GetWeaponGlowSettings(set_name, target.equip_type) or Transmogify.GLOW.DEFAULT
    local glow_signature = Transmogify.GetGlowSignature(glow)
    local restore = value == SET_VALUE_NONE and percent == 100 and not glow.enabled
    if restore then
      if not original then return false end
      local prop_visible = original.props and original.props[prop.key]
      if prop_visible == nil then prop_visible = prop.mesh_enabled end
      local changed = prop.mesh_enabled ~= prop_visible or (mesh and part.enabled) or (part and part.draw)
      return changed, {restore = true, prop_visible = prop_visible}
    end
    if mesh and (not part.mesh_ready or not part.material_ready) then
      return false
    end
    local native_scale = original and original.scale or (target.weapon and part.scale or 1)
    local native_local = original and original.local_scale or (part or prop).local_scale
    local scale = percent == 100 and native_scale or percent / 100
    if scale <= 0 then
      scale = native_scale
    end
    local local_scale = {x = scale, y = scale, z = scale}
    if percent == 100 or scale == native_scale then
      local_scale = {x = native_local.x, y = native_local.y, z = native_local.z}
    end
    local visible = value ~= SET_VALUE_HIDE and percent > 0
    local draw = prop.draw
    local weapon_id = GetTransmogId(value) or target.weapon_id
    local item = ITEM_INFO_DIC[weapon_id]
    local resources = item and item[target.category]
    if not resources then
      return false
    end
    local current_scale = part and part.local_scale
    local changed = not part or not target.weapon or part.id ~= target.base_weapon_id or
      part.mesh_path ~= resources.mesh_path or part.material_path ~= resources.mat_path or part.enabled ~= visible or
      math.abs(part.scale - scale) > CINEMATIC_SCALE_EPSILON or
      math.abs(current_scale.x - local_scale.x) > CINEMATIC_SCALE_EPSILON or
      math.abs(current_scale.y - local_scale.y) > CINEMATIC_SCALE_EPSILON or
      math.abs(current_scale.z - local_scale.z) > CINEMATIC_SCALE_EPSILON or
      part.draw ~= draw or not part.update or
      prop.mesh_enabled or (original and original.glow_signature or "") ~= glow_signature or
      (visible and Transmogify.ProcessWeaponGlow(mesh, glow, false))
    return changed, {resources = resources, scale = scale, local_scale = local_scale, visible = visible,
      draw = draw, restore = false, glow = glow, glow_signature = glow_signature,
      signature = table.concat({tostring(weapon_id), tostring(scale), tostring(visible), prop.key, glow_signature}, "|")}
  end

  -- Each cinematic clone's weapons with the glow the native hook keeps on them: a list of {owner = the clone GameObject's
  -- address, entries}, or nil without a playing cinematic and its stored originals. A hand weapon keeps the glow of its
  -- target's desired state while it is the target's base weapon, visible and drawn, its prop mesh is hidden and no
  -- preparation runs for the clone.
  function Transmogify.GetCinematicWeaponGlow()
    local work = Transmogify.GetCurrentCinematic()
    if not work or not (work:get_IsPlaying() or work:get_IsPaused()) then return nil end
    local param = work:get_Param()
    local data = Transmogify.GetNativeData(CINEMATIC_KEY)
    if not param or not data or data.work ~= tostring(sdk.to_ptr(work)) or
      data.param ~= tostring(sdk.to_ptr(param)) or not data.weapons then return nil end
    local clones, by_owner, published = {}, {}, {}
    for _, target in ipairs(GetCinematicWeaponTargets(work, data.weapons)) do
      local address = target.owner.entry.clone_object
      if address and target.weapon and target.mesh and not published[target.object] then
        local clone = by_owner[address]
        if not clone then
          clone = {owner = address, entry = target.owner.entry, entries = {},
            preparing = Transmogify.IsPreparingWeapons(Transmogify.WEAPON_CONTEXT.CINEMATIC, target.clone)}
          by_owner[address] = clone
          clones[#clones + 1] = clone
        end
        local id = target.source_id
        local char_info = GetCharInfoById(id)
        local set_name
        if char_info then set_name = GetSetNameByCharInfo(char_info) else set_name = Transmogify.GetNPCSetName(id) end
        local desired
        if (Transmogify.party_ids[id] or CURRENT_SETTINGS.sets[Transmogify.GetNPCSetName(id)]) and
          CURRENT_SETTINGS.sets[set_name] and Transmogify.HasWeaponGlow(set_name) and not clone.preparing then
          local original = data.weapons[target.key]
          if original and original.source_id == id and original.event_name == target.event_name and
            original.weapon_id == target.weapon_id and target.part.id == target.base_weapon_id then
            local target_set = target.owner.npc and Transmogify.GetNPCSetName(id) or GetSetNameByCharInfo(target.char_info)
            local _, wanted = Transmogify.ShouldTransmogCinematicWeapon(target, target_set, original)
            if wanted and not wanted.restore and wanted.visible and wanted.draw and not target.prop.mesh_enabled then
              desired = wanted
            end
          end
        end
        published[target.object] = true
        clone.entries[#clone.entries + 1] = Transmogify.NewGlowEntry(target.object, target.mesh, desired)
      end
    end
    -- The clone's other attached weapons, such as its quiver, keep no glow.
    for _, clone in ipairs(clones) do
      for _, name in ipairs({"right", "left", "quiver"}) do
        local part = clone.entry[name]
        local mesh = part and part.weapon and part.mesh
        if mesh and not published[part.object] then
          published[part.object] = true
          clone.entries[#clone.entries + 1] = Transmogify.NewGlowEntry(part.object, mesh)
        end
      end
    end
    return clones
  end

  function Transmogify.UpdateCinematicWeapons(work, param, data)
    if data.weapons == nil then
      data.weapons = {}
    elseif type(data.weapons) ~= "table" then
      error("Cinematic weapon originals are invalid")
    end
    StartTimer("cinematic_shared")
    local targets = GetCinematicWeaponTargets(work, data.weapons)
    EndTimer("cinematic_shared")
    local active = {}
    for _, target in ipairs(targets) do
      local clone = sdk.to_managed_object(target.clone)
      local context = {kind = Transmogify.WEAPON_CONTEXT.CINEMATIC, owner = clone, character = target.character,
        work = work, param = param, prop = sdk.to_managed_object(target.prop.object), slot = target.key,
        record = sdk.to_managed_object(target.owner.entry.record), source_id = target.source_id, npc = target.owner.npc}
      local key = Transmogify.GetWeaponPreparationKey(context)
      active[key] = true
      local original = data.weapons[target.key]
      if original and (original.source_id ~= target.source_id or original.weapon_id ~= target.weapon_id or
        original.event_name ~= target.event_name) then
        error("Cinematic weapon original belongs to another clone")
      end
      local set_name = target.owner.npc and Transmogify.GetNPCSetName(target.source_id) or GetSetNameByCharInfo(target.char_info)
      local changed, desired = Transmogify.ShouldTransmogCinematicWeapon(target, set_name, original)
      if not changed then
        Transmogify.CancelWeaponPreparation(key)
      elseif desired.restore then
        Transmogify.CancelWeaponPreparation(key)
        if target.mesh then native_weapons.set_mesh_enabled(target.mesh, false) end
        if target.object then native_weapons.set_flags(target.object, false, nil) end
        native_weapons.set_mesh_enabled(target.prop.mesh, desired.prop_visible)
      else
        local descriptor = target.hand.hand == RIGHT_HAND and Transmogify.WEAPON_PARTS.right or Transmogify.WEAPON_PARTS.left
        local request = Transmogify.PrepareWeapons(context, {{part = descriptor, weapon_id = target.base_weapon_id,
          resources = desired.resources, glow = desired.visible and desired.glow or Transmogify.GLOW.DEFAULT, draconic = false}})
        if request then
          local part = request.parts[1]
          local prepared, weapon, mesh = part.object, part.weapon, part.mesh
          local originals_changed = false
          if not original then
            local scale = (target.part or target.prop).local_scale
            original = {source_id = target.source_id, event_name = target.event_name, weapon_id = target.weapon_id,
              npc = target.owner.npc or nil, scale = target.weapon and target.part.scale or 1, local_scale = {x = scale.x, y = scale.y, z = scale.z},
              enabled = target.mesh and target.part.enabled or false, props = {}}
            data.weapons[target.key] = original
            originals_changed = true
          end
          original.props = original.props or {}
          if original.props[target.prop.key] == nil then
            original.props[target.prop.key] = target.prop.mesh_enabled
            originals_changed = true
          end
          if originals_changed and not Transmogify.SetNativeData(CINEMATIC_KEY, data) then return end
          local root = target.owner.root
          local object = target.object
          local clone_address, prepared_address = sdk.to_ptr(clone), sdk.to_ptr(prepared)
          local root_draw, root_update
          if root then root_draw, root_update = select(2, native_weapons.flags(root)) end
          local sibling_visibility = {}
          local attached_parts = native_weapons.attached(clone_address)
          for _, sibling in pairs(Transmogify.WEAPON_PARTS) do
            local attached = attached_parts[sibling.name].attached
            if attached and attached ~= object then
              local valid, draw, update = native_weapons.flags(attached)
              if valid then
                sibling_visibility[#sibling_visibility + 1] = {object = sdk.to_managed_object(attached), draw = draw,
                  update = update}
              end
            end
          end
          local success, failure = pcall(function()
            if object then native_weapons.destroy_object(object) end
            native_weapons.attach_clone(clone_address, prepared_address, descriptor.clone_type)
            native_weapons.set_flags(prepared_address, desired.draw, true)
            native_weapons.set_scale(sdk.to_ptr(weapon), desired.scale)
            local scale = desired.local_scale
            native_weapons.set_object_scale(prepared_address, scale.x, scale.y, scale.z)
            native_weapons.set_mesh_enabled(sdk.to_ptr(mesh), desired.visible)
            if desired.visible then Transmogify.ProcessWeaponGlow(mesh, desired.glow, true) end
            native_weapons.set_mesh_enabled(target.prop.mesh, false)
            original.glow_signature = desired.glow_signature
            if not Transmogify.SetNativeData(CINEMATIC_KEY, data) then
              error("Cinematic glow settings were not persisted")
            end
          end)
          if root then
            local valid, draw, update = native_weapons.flags(root)
            if valid then
              if draw ~= root_draw then native_weapons.set_flags(root, root_draw, nil) end
              if update ~= root_update then native_weapons.set_flags(root, nil, root_update) end
            end
          end
          for _, sibling in ipairs(sibling_visibility) do
            local address = sdk.to_ptr(sibling.object)
            if native_weapons.flags(address) then native_weapons.set_flags(address, sibling.draw, sibling.update) end
          end
          Transmogify.CancelWeaponPreparation(request.key)
          if not success then error(failure) end
        end
      end
    end
    Transmogify.CleanupWeaponPreparations(Transmogify.WEAPON_CONTEXT.CINEMATIC, active)
  end

  -- Whether the resident document may hold cutscene originals: unknown (nil) until it is read without a cutscene,
  -- false after that read found none or cleared them, true once a cutscene plays. Without a cutscene the document is read
  -- only while this is not false.
  local cinematic_stored = nil

  function Transmogify.UpdateCinematicTransmog()
    local work, finished = Transmogify.GetCurrentCinematic()
    if not work and not (finished and cinematic_stored ~= false) then
      if Transmogify.GetNativeStorage() then Transmogify.CleanupWeaponPreparations(Transmogify.WEAPON_CONTEXT.CINEMATIC) end
      return
    end
    local data, storage_ready = Transmogify.GetNativeData(CINEMATIC_KEY)
    if not storage_ready then
      return
    end
    if not work then
      Transmogify.CleanupWeaponPreparations(Transmogify.WEAPON_CONTEXT.CINEMATIC)
      if data then
        Transmogify.SetNativeData(CINEMATIC_KEY, nil)
      end
      cinematic_stored = false
      return
    end
    cinematic_stored = true
    if not (work:get_IsPlaying() or work:get_IsPaused()) then
      Transmogify.CleanupWeaponPreparations(Transmogify.WEAPON_CONTEXT.CINEMATIC)
      return
    end
    local param = work:get_Param()
    local records = param and Transmogify.ReadCinematicRecords(work, false)
    if not param or not records then
      return
    end
    local work_id = tostring(sdk.to_ptr(work))
    local param_id = tostring(sdk.to_ptr(param))
    local changed = not data or data.work ~= work_id or data.param ~= param_id
    if changed then
      Transmogify.CleanupWeaponPreparations(Transmogify.WEAPON_CONTEXT.CINEMATIC)
      data = {work = work_id, param = param_id, armors = {}}
    end
    if data.armors == nil then
      data.armors = {}
    elseif type(data.armors) ~= "table" then
      error("Cinematic armor originals are invalid")
    end
    local mutations = {}
    for _, record in ipairs(records) do
      if record.actor and record.ready then
        local builder = record.clone
        local swapper = record.swapper
        if swapper and record.meta and record.swapper_object then
          local source_id = record.source_id
          local event_name = record.event_name
          local key = tostring(builder) .. ":" .. tostring(event_name)
          local original = data.armors[key]
          local char_info = GetCharInfoById(source_id)
          local npc_set = Transmogify.GetNPCSetName(source_id)
          local npc = not char_info and (npc_set ~= SET_VALUE_NONE or (original and original.npc))
          if char_info or npc or original then
            if original and (original.source_id ~= source_id or original.event_name ~= event_name) then
              error("Cinematic armor original belongs to another clone")
            end
            local set_name = npc and npc_set or GetSetNameByCharInfo(char_info)
            local perf_section = npc and "cinematic_npc_armors" or "cinematic_armors"
            StartTimer(perf_section)
            local facts = Transmogify.ReadArmor("swapper", swapper, nil, Transmogify.GetArmorTargets(set_name))
            local needs_transmog, desired = Transmogify.ShouldTransmogCinematicArmor(facts, set_name, original, record, npc)
            if needs_transmog then
              if not original then
                local styles = {}
                original = {source_id = source_id, event_name = event_name, styles = styles, npc = npc or nil}
                data.armors[key] = original
              end
              for category, field in pairs(META_CATEGORY_FIELD_NAME_ENUM) do
                if original.styles[field] == nil then
                  original.styles[field] = facts.styles[category]
                  changed = true
                end
              end
              mutations[#mutations + 1] = {swapper = facts.swapper, desired = desired, perf_section = perf_section}
            end
            EndTimer(perf_section)
          end
        end
      end
    end
    if changed and not Transmogify.SetNativeData(CINEMATIC_KEY, data) then
      return
    end
    for _, mutation in ipairs(mutations) do
      StartTimer(mutation.perf_section)
      Transmogify.ApplyArmor(mutation.swapper, mutation.desired)
      EndTimer(mutation.perf_section)
    end
    StartTimer("cinematic_weapons")
    Transmogify.UpdateCinematicWeapons(work, param, data)
    EndTimer("cinematic_weapons")
  end
end

do
  local STORAGE_KEY = "npc_armors"
  local CATALOG_BATCH_SIZE = 64
  local SHOW_ALL, SHOW_CHANGED, SHOW_LOOKS, SHOW_EQUIPMENT = 1, 2, 3, 4
  local SHOW_OPTIONS = {"All", "Changed", "Changed looks", "Changed equipment"}
  local ROW_OVERSCAN = 2
  local cached_memo, cached_records
  Transmogify.npc_assignments = {rows = {}, filtered = {}, search = "", show_index = SHOW_ALL, catalog_state = "waiting",
    built_count = 0}

  -- The NPC pass stores weapons_active before it changes an NPC's weapons; that stored record restores them later, also
  -- after a script reset. Its identity starts with the character's address.
  function Transmogify.IsNPCWeaponOverrideStored(key, character)
    local record = cached_records and cached_records[key]
    local prefix = tostring(sdk.to_ptr(character)) .. "|"
    return record ~= nil and record.weapons_active == true and type(record.identity) == "string" and
      record.identity:sub(1, #prefix) == prefix
  end

  function Transmogify.GetNPCSetName(id)
    local name = CURRENT_SETTINGS.npcSets[tostring(id)]
    if name and CURRENT_SETTINGS.sets[name] then return name end
    return SET_VALUE_NONE
  end

  function Transmogify.GetNPCAppearanceName(id)
    local name = CURRENT_SETTINGS.npcAppearances[tostring(id)]
    if not name then return SET_VALUE_NONE end
    for _, file in ipairs(Transmogify.appearance_presets.files) do
      if file == name then return name end
    end
    return SET_VALUE_NONE
  end

  function Transmogify.IsNPCWeaponTarget(id)
    local original = cached_records and cached_records[tostring(id)]
    return Transmogify.GetNPCSetName(id) ~= SET_VALUE_NONE or (original and original.weapons_active) or false
  end

  function Transmogify.FilterNPCList()
    local state = Transmogify.npc_assignments
    local search = string.lower(state.search)
    local filtered = {}
    for _, row in ipairs(state.rows) do
      local equipment = Transmogify.GetNPCSetName(row.id) ~= SET_VALUE_NONE
      local look = Transmogify.GetNPCAppearanceName(row.id) ~= SET_VALUE_NONE
      local shown = state.show_index == SHOW_ALL or state.show_index == SHOW_CHANGED and (equipment or look) or
        state.show_index == SHOW_LOOKS and look or state.show_index == SHOW_EQUIPMENT and equipment
      if shown and (search == "" or utils.StringFindRaw(row.search, search)) then
        filtered[#filtered + 1] = row
      end
    end
    state.filtered = filtered
  end

  function Transmogify.SetNPCPreset(id, name)
    assert(name == SET_VALUE_NONE or CURRENT_SETTINGS.sets[name], "Unknown NPC armor preset")
    local key = tostring(id)
    if name == SET_VALUE_NONE then name = nil end
    if CURRENT_SETTINGS.npcSets[key] == name then return end
    CURRENT_SETTINGS.npcSets[key] = name
    Transmogify.preset_editor.pending_save = true
    Transmogify.eye_glow.full = true
    Transmogify.FilterNPCList()
  end

  function Transmogify.SetNPCAppearance(id, name)
    local key = tostring(id)
    if name == SET_VALUE_NONE then name = nil end
    if CURRENT_SETTINGS.npcAppearances[key] == name then return end
    CURRENT_SETTINGS.npcAppearances[key] = name
    Transmogify.npc_looks.checked[key] = nil
    Transmogify.preset_editor.pending_save = true
    Transmogify.FilterNPCList()
  end

  -- The game's NPC data shrinks and refills on scene loads, so only growth past the last build's count builds again; rows
  -- merge by ID, so NPCs the game unloaded stay listed.
  function Transmogify.CheckNPCList()
    local state = Transmogify.npc_assignments
    if state.catalog_state ~= "ready" then return end
    local manager = sdk.get_managed_singleton("app.NPCManager")
    local database = manager and manager:get_IsDataSetup() and manager:get_CharacterDataDict()
    if database and database:get_Count() > state.built_count then state.catalog_state = "waiting" end
  end

  function Transmogify.UpdateNPCArmorCatalog()
    local state = Transmogify.npc_assignments
    if state.catalog_state == "ready" or state.catalog_state == "failed" then return end
    local request = state.request
    state.request, state.catalog_state = nil, "failed"
    local manager = sdk.get_managed_singleton("app.NPCManager")
    local database = manager and manager:get_IsDataSetup() and manager:get_CharacterDataDict()
    if not database or database:get_Count() == 0 then
      state.request, state.catalog_state = nil, "waiting"
      return
    end
    if not request or request.database ~= sdk.to_ptr(database) then
      request = {database = sdk.to_ptr(database), count = database:get_Count(), entries = {}, rows = {}, index = 1,
        started = utils.Seconds()}
      for id, entry in pairs(utils.GetLuaDic(database)) do
        request.entries[#request.entries + 1] = {id = id, entry = entry}
      end
    end
    local last = math.min(#request.entries, request.index + CATALOG_BATCH_SIZE - 1)
    for index = request.index, last do
      local entry = request.entries[index]
      local identity = utils.GetNpcCatalogIdentity(entry.id, entry.entry)
      if identity and #identity.names > 0 then
        local name = table.concat(identity.names, " / ")
        request.rows[#request.rows + 1] = {id = entry.id, name = name, label = name,
          search = string.lower(name .. " " .. tostring(entry.id))}
      end
    end
    request.index = last + 1
    if last < #request.entries then
      state.request, state.catalog_state = request, "loading"
      return
    end
    local built, previous = {}, #state.rows
    for _, row in ipairs(request.rows) do built[row.id] = true end
    for _, row in ipairs(state.rows) do
      if not built[row.id] then request.rows[#request.rows + 1] = row end
    end
    table.sort(request.rows, function(a, b)
      local left, right = string.lower(a.name), string.lower(b.name)
      if left ~= right then return left < right end
      return a.id < b.id
    end)
    local counts = {}
    for _, row in ipairs(request.rows) do
      local name = string.lower(row.name)
      counts[name] = (counts[name] or 0) + 1
    end
    for _, row in ipairs(request.rows) do
      row.label = counts[string.lower(row.name)] > 1 and row.name .. " [" .. tostring(row.id) .. "]" or row.name
    end
    state.rows, state.built_count, state.catalog_state = request.rows, request.count, "ready"
    if #request.rows ~= previous then
      utils.Log(string.format("[%s] NPC list %s: %d NPCs in %.1f s", modname, previous == 0 and "ready" or "updated",
        #request.rows, utils.Seconds() - request.started))
    end
    Transmogify.FilterNPCList()
  end

  function Transmogify.DrawNPCTab()
    local state = Transmogify.npc_assignments
    local presets = Transmogify.appearance_presets
    local loading = state.catalog_state ~= "ready" and #state.rows == 0
    imgui.begin_disabled(loading)
    imgui.set_next_item_width(220)
    local search_changed, search = imgui.input_text("Search##npc_search", state.search)
    if search_changed then state.search, state.scroll_reset = search, true; Transmogify.FilterNPCList() end
    imgui.same_line()
    imgui.set_next_item_width(180)
    local show_changed, show_index = imgui.combo("Show##npc_show", state.show_index, SHOW_OPTIONS)
    if show_changed then state.show_index, state.scroll_reset = show_index, true; Transmogify.FilterNPCList() end
    imgui.end_disabled()
    if state.catalog_state == "failed" then
      utils.TextColored(#state.rows == 0 and "NPC list could not initialize; check the log." or
        "NPC list could not update; check the log.", 0xFF0000FF)
      if #state.rows == 0 then return end
    elseif loading then
      utils.TextColored("Loading NPC list...", COLOR_INFO)
      return
    end
    if #transmogSetList == 1 then utils.TextColored("Create equipment presets in Presets.", COLOR_INFO) end
    if #presets.files == 0 then utils.TextColored("Create appearances in Character > Appearance preset.", COLOR_INFO) end
    local rows = state.filtered
    if #rows == 0 then
      utils.TextColored("No matching NPCs.", COLOR_INFO)
      return
    end
    local appearance_list = {SET_VALUE_NONE}
    for _, name in ipairs(presets.files) do appearance_list[#appearance_list + 1] = name end
    local change
    if imgui.begin_table("npc_assignments", 3, imgui.TableFlags.ScrollY + imgui.TableFlags.SizingStretchSame +
      imgui.TableFlags.NoPadOuterX, Vector2f.new(0, 0), 0) then
      imgui.table_setup_scroll_freeze(0, 1)
      imgui.table_setup_column("NPC")
      imgui.table_setup_column("Equipment")
      imgui.table_setup_column("Appearance")
      imgui.table_headers_row()
      if state.scroll_reset then imgui.set_scroll_y(0); state.scroll_reset = nil end
      local pitch = state.row_pitch or fontSize + 10
      local scroll = imgui.get_scroll_y()
      local first = math.min(#rows, math.max(1, math.floor(scroll / pitch) + 1 - ROW_OVERSCAN))
      local last = math.min(#rows, math.ceil((scroll + imgui.get_window_size().y) / pitch) + ROW_OVERSCAN)
      if first > 1 then imgui.table_next_row(0, (first - 1) * pitch) end
      local previous_y
      for index = first, last do
        local row = rows[index]
        imgui.table_next_row()
        imgui.table_set_column_index(0)
        local y = imgui.get_cursor_pos().y
        if previous_y then state.row_pitch = y - previous_y end
        previous_y = y
        imgui.text(row.label)
        imgui.table_set_column_index(1)
        imgui.set_next_item_width(-1)
        local equipment_index = GetIndexByVal(transmogSetList, Transmogify.GetNPCSetName(row.id))
        local equipment_changed, equipment = imgui.combo("##npc_equipment_" .. row.id, equipment_index, transmogSetList)
        if equipment_changed then change = {Transmogify.SetNPCPreset, row.id, transmogSetList[equipment]} end
        imgui.table_set_column_index(2)
        imgui.set_next_item_width(-1)
        local look_index = GetIndexByVal(appearance_list, Transmogify.GetNPCAppearanceName(row.id))
        local look_changed, look = imgui.combo("##npc_appearance_" .. row.id, look_index, appearance_list)
        if look_changed then change = {Transmogify.SetNPCAppearance, row.id, appearance_list[look]} end
      end
      if last < #rows then imgui.table_next_row(0, (#rows - last) * pitch) end
      imgui.end_table()
    end
    if change then change[1](change[2], change[3]) end
  end

  -- facts from Transmogify.ReadArmor in "swapper" mode with the preset's targets.
  function Transmogify.ShouldTransmogNPCArmor(facts, set_name, original)
    local desired, changed, override = {}, false, false
    for category, field in pairs(META_CATEGORY_FIELD_NAME_ENUM) do
      local current = facts.styles[category]
      local baseline = current
      if original then baseline = original.styles[field] end
      assert(type(baseline) == "number", "Original NPC armor style is unavailable: " .. field)
      local style = baseline
      local value = GetSetTransmogValue(set_name, ARMOR_CATEGORY_TO_EQUIPMENT_INFO_TYPE[category])
      local style_no = GetTransmogId(value)
      if value == SET_VALUE_HIDE then
        style = STYLE_NONE
      elseif style_no and Transmogify.IsClothingStyleAvailable(category, style_no, facts.gender) then
        style = Transmogify.GetTargetArmorStyle(facts, category, style_no)
      end
      assert(type(style) == "number", "NPC armor style is unavailable: " .. field)
      desired[category] = style
      changed = changed or current ~= style
      override = override or baseline ~= style
    end
    return changed, desired, override
  end

  function Transmogify.UpdateNPCTransmog(pending_only)
    local candidates = {}
    if pending_only then
      for _, request in pairs(Transmogify.weapon_preparations) do
        local context = request.context
        if context.kind == Transmogify.WEAPON_CONTEXT.WORLD and context.npc then
          candidates[tostring(context.character:get_CharaID())] = true
        end
      end
      if next(candidates) == nil then return end
    end
    local memo = Transmogify.GetNativeStorage()
    if not memo then return end
    if memo ~= cached_memo then
      local records, ready = Transmogify.GetNativeData(STORAGE_KEY)
      if not ready then return end
      if records == nil then records = {} end
      assert(type(records) == "table", "NPC armor originals are invalid")
      cached_memo, cached_records = memo, records
    end
    if not pending_only then
      for id in pairs(CURRENT_SETTINGS.npcSets) do candidates[id] = true end
      for id, record in pairs(cached_records) do
        assert(type(record) == "table", "NPC armor original is invalid")
        if record.active or record.weapons_active then candidates[id] = true end
      end
    end
    if next(candidates) == nil then return end
    local records, mutations, weapons, dirty = utils.ShallowCopy(cached_records), {}, {}, false
    for key in pairs(candidates) do
      local id = assert(tonumber(key), "Invalid NPC assignment ID")
      local character = Transmogify.GetNPCCharacter(id)
      if character then
        local object = utils.GetGameObject(character)
        local swapper = object and character:get_HumanPartSwapper()
        local set_name = Transmogify.GetNPCSetName(id)
        local facts = object and character:get_CharaID() == id and utils.GetGameObject(swapper) and
          Transmogify.ReadArmor("swapper", swapper, nil, Transmogify.GetArmorTargets(set_name))
        if facts and facts.meta and not facts.swapping then
          local identity = table.concat({tostring(sdk.to_ptr(character)), tostring(sdk.to_ptr(swapper)),
            tostring(sdk.to_ptr(facts.meta)), tostring(facts.species), tostring(facts.gender)}, "|")
          local original = records[key]
          if original and original.identity ~= identity then
            original, records[key], dirty = nil, nil, true
          end
          if original then assert(type(original.styles) == "table", "NPC armor original styles are invalid") end
          local changed, desired, override = false, nil, false
          if not pending_only then
            changed, desired, override = Transmogify.ShouldTransmogNPCArmor(facts, set_name, original)
          end
          if changed then
            if not original then
              original = {identity = identity, styles = {}, active = true}
              for category, field in pairs(META_CATEGORY_FIELD_NAME_ENUM) do
                original.styles[field] = facts.styles[category]
              end
              records[key], dirty = original, true
            elseif not original.active then
              original = utils.ShallowCopy(original)
              original.active = true
              records[key], dirty = original, true
            end
            mutations[#mutations + 1] = {swapper = facts.swapper, desired = desired}
          elseif not pending_only and original and original.active and not override then
            original = utils.ShallowCopy(original)
            original.active = false
            records[key], dirty = original, true
          end
          local main, off, _, _, native_ids = Transmogify.GetWorldWeaponData(character, true)
          local job = main and main:getJob() or (off and off:getJob())
          local weapon_override = false
          for _, equip_type in ipairs(JOB_TO_WEAPON_EQUIP_INFO_TYPE_LIST[job] or {}) do
            local info = EQUIPMENT_INFO[equip_type]
            local equipped = info.slot == SLOT_MAIN_HAND and main or (info.slot == SLOT_OFF_HAND and off)
            if equipped and CURRENT_SETTINGS.enabled then
              local sizes = CURRENT_SETTINGS.setSize[set_name]
              weapon_override = weapon_override or GetSetTransmogValue(set_name, equip_type) ~= SET_VALUE_NONE or
                (sizes and (sizes[equip_type] or 100) ~= 100) or Transmogify.GetWeaponGlowSettings(set_name, equip_type).enabled or
                Transmogify.GetHideWhenSheathed(set_name, equip_type)
            end
          end
          if main and job == EQUIP_JOB_ARCHER and CURRENT_SETTINGS.enabled then
            local sizes = CURRENT_SETTINGS.setSize[set_name]
            weapon_override = weapon_override or (sizes and (sizes[Transmogify.QUIVER_EQUIP_TYPE] or 100) ~= 100)
          end
          if native_ids ~= false and (weapon_override or (original and original.weapons_active)) then
            if not original then
              original = {identity = identity, styles = {}, active = false}
              for category, field in pairs(META_CATEGORY_FIELD_NAME_ENUM) do
                original.styles[field] = facts.styles[category]
              end
              records[key], dirty = original, true
            else
              original = utils.ShallowCopy(original)
              records[key] = original
            end
            if not original.weapons_active then original.weapons_active, dirty = true, true end
            weapons[#weapons + 1] = {character = character, set_name = set_name, original = original, override = weapon_override, key = key}
          end
        end
      end
    end
    if dirty then
      if not Transmogify.SetNativeData(STORAGE_KEY, records) then return end
      cached_records = records
    end
    for _, mutation in ipairs(mutations) do
      Transmogify.ApplyArmor(mutation.swapper, mutation.desired)
    end
    local weapons_changed = false
    records = utils.ShallowCopy(records)
    for _, entry in ipairs(weapons) do
      local updated = utils.ShallowCopy(entry.original)
      if Transmogify.UpdateNPCWeapons(entry.character, entry.set_name, updated, entry.override, pending_only) then
        records[entry.key], weapons_changed = updated, true
      end
    end
    if weapons_changed and Transmogify.SetNativeData(STORAGE_KEY, records) then cached_records = records end
  end
end

Transmogify.QueueMenuFaceRefresh = function(char_info)
  if not char_info then
    return
  end

  Transmogify.refresh_gui_face[char_info.character] = char_info
end

Transmogify.IsMenuFaceRefreshRequestCurrent = function(request)
  local menu_face = GuiManager and GuiManager.MenuFace
  if not menu_face or sdk.to_ptr(menu_face) ~= sdk.to_ptr(request.menu_face) then
    return false
  end

  local character = request.char_info.character()
  return character and sdk.to_ptr(character) == sdk.to_ptr(request.character) and
    character:get_CharaID() == request.chara_id
end

Transmogify.UpdateMenuFaceRefresh = function()
  local request = Transmogify.menu_face_refresh_request
  if request then
    if not Transmogify.IsMenuFaceRefreshRequestCurrent(request) then
      request.retry = true
    end

    if GuiManager:isCompleteUpdateMenuFace() then
      if request.retry or request.stage ~= "waiting_for_capture" then
        Transmogify.QueueMenuFaceRefresh(request.char_info)
      end
      Transmogify.menu_face_refresh_request = nil
    end
    return
  end

  if Transmogify.refresh_gui_face_timer > 0 then
    Transmogify.refresh_gui_face_timer = Transmogify.refresh_gui_face_timer - 1
    return
  end
  Transmogify.refresh_gui_face_timer = 5

  local menu_face = GuiManager and GuiManager.MenuFace
  if not menu_face or not menu_face:get_field("IsInit") or not GuiManager:isCompleteUpdateMenuFace() then
    return
  end

  for get_char_func, char_info in pairs(Transmogify.refresh_gui_face) do
    local character = get_char_func()
    if character then
      local target_params = {}
      local equip_data = GetEquipData(character)
      local set_name = GetSetNameByCharInfo(char_info)
      for slot, equip_category in pairs(ARMOR_SLOT_TO_CATEGORY_ENUM) do
        if utils.GetSlotItemData(equip_data, slot) then
          local equip_info_type = ARMOR_CATEGORY_TO_EQUIPMENT_INFO_TYPE[equip_category]
          local transmog_id = GetTransmogId(GetSetTransmogValue(set_name, equip_info_type))
          local transmog_style = transmog_id and GetArmorStyle(equip_category, transmog_id)
          local get_item_data_func = ITEM_MANAGER_CATEGORY_GET_ITEM_DATA_FUNC_ENUM[equip_category]
          local item_data = transmog_style and ItemManager:call(get_item_data_func, transmog_style)
          local armor_param = item_data and item_data:get_ArmorParam()
          if armor_param and armor_param._EquipCategory == equip_category then
            target_params[equip_category] = armor_param
          end
        end
      end

      Transmogify.menu_face_refresh_request = {
        char_info = char_info,
        character = character,
        chara_id = character:get_CharaID(),
        menu_face = menu_face,
        target_params = target_params,
        replaced = {},
        stage = "queued",
        retry = false
      }
      Transmogify.refresh_gui_face[get_char_func] = nil
      GuiManager:call("updateMenuFace(app.CharacterID)", character:get_CharaID())
      return
    end
  end
end

local function RefreshGUITransmogs(size_only)
  for _, char_info in pairs(char_info_list) do
    local character = char_info.character()
    if character and not size_only then
      Transmogify.QueueMenuFaceRefresh(char_info)
    end

    local mock_builder = not size_only and character and GetMockupBuilder(character)
    if mock_builder then
      Transmogify.ApplyArmorStyles("builder", mock_builder, character, GetSetNameByCharInfo(char_info))
    end
  end
end

function Transmogify.ApplyGUIArmor(mock_builder, character, set_name)
  if not Transmogify.init_complete or not mock_builder then return end
  Transmogify.ApplyArmorStyles("builder", mock_builder, character, set_name)
end

local function Refresh()
  RefreshSetList()

  transmogSetList = utils.ShallowCopy(SET_LIST)
  transmogSetList[1] = SET_VALUE_NONE

  RefreshEquipmentInfoLists()
end

local function IsValidArmorOrWeapon(item_data)
  local result = false
  local item_name = item_data:get_Name()
  local item_category = item_data._EquipCategory
  if item_data._EquipCategory ~= nil and item_name ~= "Invalid" then
    for _, equip_category in pairs(VALID_CATEGORIES) do
      if equip_category == item_category then
        result = true
        break
      end
    end

    if item_category == CAT_WEAPON or item_category == CAT_SHIELD then
      result = result and item_data._WeaponId ~= nil
    else
      result = result and item_data._StyleNo ~= nil
    end
  end

  return result
end

local function AddArmorStyle(style_enum_name, style_db_name, equip_category)
  local category_item_list = {}
  local gender_dic = utils.GetEnumDic("app.Gender")
  local all_style_dic = utils.GetEnumDic(style_enum_name)
  local style_db = utils.GetLuaDic(CharacterEditManager:get_field(style_db_name))
  local style_swap_males_dic = utils.GetLuaDic(assert(style_db[gender_dic.Male] ~= utils.NATIVE_NULL and style_db[gender_dic.Male], "Missing male style database"))
  local style_swap_females_dic = utils.GetLuaDic(assert(style_db[gender_dic.Female] ~= utils.NATIVE_NULL and style_db[gender_dic.Female], "Missing female style database"))
  local function_name = "getItemData(" .. style_enum_name .. ")"
  local extra = EXTRA_ARMOR_CATEGORIES[equip_category]

  for style_enum_key, style in pairs(all_style_dic) do
    local item_common_param = not extra and ItemManager:call(function_name, style)
    local item_name = nil
    local style_no_number = tonumber(utils.Explode(style_enum_key, "_")[2])
    local padded_style_no = GetPaddedItemId(style_no_number)
    local item_style_no_name = nil
    local job = nil

    local male_style = style_swap_males_dic[style] ~= utils.NATIVE_NULL and style_swap_males_dic[style]
    local female_style = style_swap_females_dic[style] ~= utils.NATIVE_NULL and style_swap_females_dic[style]
    if item_common_param and IsValidArmorOrWeapon(item_common_param) then
      item_name = utils.ExpandMessageTags(item_common_param:get_Name()) or item_common_param:get_Name()
      item_style_no_name = "[" .. padded_style_no .. "] " .. item_name
      job = item_common_param:getJob()
    elseif extra and style_no_number ~= nil and (male_style or female_style) then
      item_name = extra.label .. " " .. GetPaddedItemId(style_no_number, 3)
      item_style_no_name = "[" .. padded_style_no .. "] " .. item_name
      job = EQUIP_JOB_NPC
    elseif style_no_number == nil then
      padded_style_no = nil
    elseif male_style and female_style then
      item_name = "NPC_BOTH_" .. style_no_number
      item_style_no_name = "[" .. padded_style_no .. "] " .. item_name
      job = EQUIP_JOB_NPC
    elseif male_style and not female_style then
      item_name = "NPC_MAL_" .. style_no_number
      item_style_no_name = "[" .. padded_style_no .. "] " .. item_name
      job = EQUIP_JOB_NPC
    elseif not male_style and female_style then
      item_name = "NPC_FEM_" .. style_no_number
      item_style_no_name = "[" .. padded_style_no .. "] " .. item_name
      job = EQUIP_JOB_NPC
    else
      padded_style_no = nil
    end

    if padded_style_no and style_no_number ~= nil then
      table.insert(category_item_list, item_style_no_name)

      if not ITEM_INFO_DIC[style_no_number] then
        ITEM_INFO_DIC[style_no_number] = {}
      end
      if not ITEM_INFO_DIC[style_no_number][equip_category] then
        ITEM_INFO_DIC[style_no_number][equip_category] = {}
      end

      if padded_style_no then
        ITEM_INFO_DIC[style_no_number][equip_category]["name"] = item_name
        ITEM_INFO_DIC[style_no_number][equip_category]["id_name"] = item_style_no_name
        ITEM_INFO_DIC[style_no_number][equip_category]["equip_category"] = equip_category
        ITEM_INFO_DIC[style_no_number][equip_category]["style_no"] = style_no_number
        ITEM_INFO_DIC[style_no_number][equip_category]["job"] = job
        ITEM_INFO_DIC[style_no_number][equip_category]["style"] = style
        ITEM_INFO_DIC[style_no_number][equip_category]["genders"] = {[gender_dic.Male] = not not male_style, [gender_dic.Female] = not not female_style}
      end
    end
  end
  local listed = {}
  for _, id_name in ipairs(category_item_list) do listed[GetTransmogId(id_name)] = true end
  for _, id_name in ipairs(CATEGORY_ITEM_LIST[equip_category] or {}) do
    if not listed[GetTransmogId(id_name)] then table.insert(category_item_list, id_name) end
  end
  table.sort(category_item_list)
  CATEGORY_ITEM_LIST[equip_category] = category_item_list
end

-- The mesh and material paths of the given weapon catalog prefabs, by WeaponID, read from a live copy of each through
-- utils.NewPrefabLoader. Transmogify.init_prefab_loader holds the loads in progress for cleanup. A prefab still loading
-- after PREFAB_STUCK_SECONDS is logged once and, during the first build, named on the initialization status line.
local function LoadWeaponPrefabPaths(catalog_dic)
  local PREFAB_LOADS, PREFAB_STUCK_SECONDS = 64, 10
  local entries, paths = {}, {}
  for weapon_id, prefab_controller in pairs(catalog_dic) do
    local controller = prefab_controller and prefab_controller ~= utils.NATIVE_NULL and prefab_controller._Item
    local resource_path = controller and controller:get_ResourcePath()
    if resource_path and resource_path ~= "" then
      entries[#entries + 1] = {weapon_id = weapon_id, controller = controller:add_ref(), path = resource_path}
    end
  end
  local loader = utils.NewPrefabLoader(entries, PREFAB_LOADS, function(entry, mesh)
    if not mesh then return end
    paths[entry.weapon_id] = {mesh_path = mesh:getMesh():get_ResourcePath(), mat_path = mesh:get_Material():get_ResourcePath()}
  end)
  Transmogify.init_prefab_loader = loader
  Transmogify.init_weapon_current, Transmogify.init_weapon_total = 0, #entries
  while not loader:Step() do
    Transmogify.init_weapon_current = loader.done
    local now, waiting = utils.Seconds(), nil
    for entry in loader:Active() do
      if now - entry.started > PREFAB_STUCK_SECONDS then
        waiting = entry.path
        if not entry.reported then
          entry.reported = true
          utils.Log(string.format("[%s] Weapon prefab still loading after %d s: %s (WeaponID %s)", modname,
            PREFAB_STUCK_SECONDS, entry.path, tostring(entry.weapon_id)))
        end
      end
    end
    Transmogify.init_waiting_prefab = waiting
    coroutine.yield()
  end
  Transmogify.init_prefab_loader, Transmogify.init_waiting_prefab = nil, nil
  return paths, loader.failed
end

-- Weapon path cache ---------------------------------------------------------------------------------------------
-- Mesh and material paths can only be read by instantiating a prefab and waiting for its mesh and material to be
-- ready, which costs seconds per hundred weapons. The results are cached in
-- reframework/data/Transmogify/weapon_paths_cache.json so later launches only prepare new or changed prefabs.
-- Validation: the game executable size, each prefab's own resource path, and a small sample of cached entries that
-- is re-read on every launch, which catches a resource layout change the fingerprints cannot see.
local weapon_cache_path = "Transmogify/weapon_paths_cache.json"
local WEAPON_CACHE_SCHEMA = 1
local WEAPON_CACHE_SAMPLE = 8
local WEAPON_CACHE_MAX_FAILURES = 3

local function ReadTextFile(path, limit)
  local ok, file = pcall(io.open, path, "rb")
  if not ok or not file then return nil end
  local read_ok, content = pcall(file.read, file, limit or 256)
  file:close()
  if not read_ok then return nil end
  return content
end

local function GetWeaponCacheBuild()
  -- REFramework blocks Lua from touching executables and DLLs ("This API does not allow interacting with executables
  -- or DLLs"), so fingerprint the REFramework revision instead. The per-prefab resource paths plus the sampled
  -- re-reads are what actually catch a changed weapon layout.
  local revision = ReadTextFile("reframework_revision.txt", 128)
  if type(revision) == "string" then
    return (revision:gsub("%s+", "")):sub(1, 24)
  end
  return "unknown"
end

-- The prefab controller's resource path, readable without instantiating anything.
local function GetPrefabResourcePath(prefab_controller)
  local controller = prefab_controller and prefab_controller ~= utils.NATIVE_NULL and prefab_controller._Item
  if not controller then return nil end
  local path = controller:get_ResourcePath()
  if path == nil or path == "" then return nil end
  return path
end

local function LoadWeaponCache(build)
  local ok, data = pcall(json.load_file, weapon_cache_path)
  if not ok or type(data) ~= "table" or data.schema ~= WEAPON_CACHE_SCHEMA or data.build ~= build
    or type(data.entries) ~= "table" then
    return nil
  end
  local count = 0
  for _ in pairs(data.entries) do count = count + 1 end
  utils.Log(string.format("[%s] Weapon path cache hit for %d prefabs (build %s)", modname, count, build))
  return data.entries
end

local function SaveWeaponCache(build, entries)
  local count = 0
  for _ in pairs(entries) do count = count + 1 end
  local ok, saved = pcall(json.dump_file, weapon_cache_path,
    {schema = WEAPON_CACHE_SCHEMA, build = build, entries = entries})
  if not ok or not saved then
    utils.Log("[" .. modname .. "] Could not save the weapon path cache; the next launch prepares everything again")
    return
  end
  utils.Log(string.format("[%s] Weapon path cache saved for %d prefabs (build %s)", modname, count, build))
end

-- Re-reads a few cached prefabs and reports how many no longer match their cached paths.
local function VerifyWeaponCacheSample(cache, catalog)
  local ids = {}
  for weapon_id, entry in pairs(cache) do
    if entry.kind == "ok" and catalog[weapon_id] ~= nil then ids[#ids + 1] = weapon_id end
  end
  if #ids == 0 then return 0 end
  table.sort(ids)
  local sample, sample_dic, seen = {}, {}, {}
  local stride = math.max(1, math.floor(#ids / WEAPON_CACHE_SAMPLE))
  for index = 1, #ids, stride do
    local weapon_id = ids[index]
    if not seen[weapon_id] then
      seen[weapon_id] = true
      sample[#sample + 1] = weapon_id
      sample_dic[weapon_id] = catalog[weapon_id]
    end
    if #sample >= WEAPON_CACHE_SAMPLE then break end
  end
  local verified = LoadWeaponPrefabPaths(sample_dic)
  local mismatches = 0
  for _, weapon_id in ipairs(sample) do
    local fresh, cached = verified[weapon_id], cache[weapon_id]
    if fresh == nil or fresh.mesh_path ~= cached.mesh or fresh.mat_path ~= cached.mat then
      mismatches = mismatches + 1
    end
  end
  if mismatches > 0 then
    utils.Log(string.format("[%s] Weapon path cache: %d of %d sampled prefabs changed", modname, mismatches, #sample))
  end
  return mismatches
end

local function AddWeapons()
  utils.Log("[" .. modname .. "] Building the weapon catalog")
  local wp_to_job = {
    ["wp00"] = EQUIP_JOB_FIGHTER,
    ["wp01"] = EQUIP_JOB_FIGHTER,
    ["wp02"] = EQUIP_JOB_WARRIOR,
    ["wp03"] = EQUIP_JOB_THIEF,
    ["wp04"] = EQUIP_JOB_ARCHER,
    ["wp05"] = EQUIP_JOB_MAGIC_ARCHER,
    ["wp07"] = EQUIP_JOB_MAGE,
    ["wp08"] = EQUIP_JOB_SORCERER,
    ["wp09"] = EQUIP_JOB_SPEARHAND,
    ["wp10"] = EQUIP_JOB_TRICKSTER,
  }

  local function GetJob(weapon_enum_key)
    local weapon_type = utils.Explode(weapon_enum_key, "_")[1]
    return wp_to_job[weapon_type]
  end

  local EquipmentManager = sdk.get_managed_singleton('app.EquipmentManager')
  local catalog = utils.GetLuaDic(EquipmentManager.WeaponCatalog)

  -- The weapon catalog stays empty until the game has loaded its item data. Building from an empty catalog used to
  -- crash on the final table.sort and leave the mod stuck on its initial status forever, so wait for it instead.
  local catalog_wait = 0
  while next(catalog) == nil do
    catalog_wait = catalog_wait + 1
    Transmogify.init_status = "Waiting for the weapon catalog"
    if catalog_wait % 600 == 0 then
      utils.Log("[" .. modname .. "] Still waiting for the weapon catalog to load")
    end
    coroutine.yield()
    catalog = utils.GetLuaDic(EquipmentManager.WeaponCatalog)
  end
  local cache_build, cached_paths = "unknown", {}

  -- The cache is an optimisation only: if anything about it fails, fall back to the plain full build.
  local bootstrap_ok, bootstrap_error = pcall(function()
    cache_build = GetWeaponCacheBuild()
    cached_paths = LoadWeaponCache(cache_build) or {}
    if VerifyWeaponCacheSample(cached_paths, catalog) >= 2 then
      utils.Log("[" .. modname .. "] Weapon path cache looks stale; rebuilding every weapon appearance")
      cached_paths = {}
      Transmogify.catalog_weapons = {}
    end
  end)
  if not bootstrap_ok then
    utils.Log("[" .. modname .. "] Weapon path cache unavailable this run: " .. tostring(bootstrap_error))
    cached_paths = {}
  end

  local prefab_paths = Transmogify.catalog_weapons
  local new_weapons, new_count, reused_count = {}, 0, 0
  for weapon_id, prefab_controller in pairs(catalog) do
    if prefab_paths[weapon_id] ~= nil then
      -- Prepared earlier in this session by UpdateCatalogs.
      reused_count = reused_count + 1
    else
      local resource_path = GetPrefabResourcePath(prefab_controller)
      local cached = cached_paths[weapon_id]
      if cached and cached.src == resource_path and cached.kind == "ok" then
        prefab_paths[weapon_id] = {mesh_path = cached.mesh, mat_path = cached.mat}
        reused_count = reused_count + 1
      elseif cached and cached.src == resource_path and cached.kind == "no_mesh" then
        prefab_paths[weapon_id] = false
        reused_count = reused_count + 1
      elseif cached and cached.src == resource_path and (cached.failures or 0) >= WEAPON_CACHE_MAX_FAILURES then
        prefab_paths[weapon_id] = false
        reused_count = reused_count + 1
      else
        new_weapons[weapon_id], new_count = prefab_controller, new_count + 1
      end
    end
  end
  Transmogify.init_status = "Loading weapon prefabs"
  local loaded, failed = LoadWeaponPrefabPaths(new_weapons)
  failed = failed or {}
  utils.Log(string.format("[%s] Weapon prefabs: %d prepared, %d served from the path cache", modname, new_count,
    reused_count))
  Transmogify.init_status = "Preparing weapon appearances"
  Transmogify.init_weapon_current = 0
  Transmogify.init_weapon_total = new_count
  local function_name = "getItemData(app.WeaponID)"
  local g_arrow_mesh_path = "Character/wp/wp11/000/wp11_000.mesh"
  local g_arrow_mesh_resource = utils.CreateResource("via.render.MeshResource", g_arrow_mesh_path)
  local g_arrow_mat_path = "Character/wp/wp11/000/wp11_000.mdf2"
  local g_arrow_mat_resource = utils.CreateResource("via.render.MeshMaterialResource", g_arrow_mat_path)
  for weapon_id in pairs(new_weapons) do
    Transmogify.init_weapon_current = Transmogify.init_weapon_current + 1
    -- Resource holders are created per appearance; spreading them over updates keeps each frame short.
    if Transmogify.init_weapon_current % 16 == 0 then coroutine.yield() end
    local weapon_enum_key = GetWeaponEnumKey(weapon_id)
    local padded_weapon_id = GetPaddedItemId(weapon_id, 10)
    local weapon_mesh_mat_dic = loaded[weapon_id]
    local weapon_type_key = weapon_enum_key
    if not weapon_enum_key then
      if weapon_mesh_mat_dic then
        weapon_type_key = weapon_mesh_mat_dic.mesh_path
        utils.Log("[" .. modname .. "] Using mesh path for weapon catalog entry without WeaponID enum: " ..
          tostring(weapon_id))
      end
    end
    if weapon_type_key and not string.find(weapon_type_key, "wp06") and not string.find(weapon_type_key, "wp11") then
      if weapon_mesh_mat_dic then
        local mesh_path = weapon_mesh_mat_dic.mesh_path
        local mesh_resource = utils.CreateResource("via.render.MeshResource", mesh_path)
        local mat_path = weapon_mesh_mat_dic.mat_path
        local mat_resource = utils.CreateResource("via.render.MeshMaterialResource", mat_path)

        local quiver_weapon_id = EquipmentManager:getQuiverID(weapon_id)
        local quiver_mesh_path = nil
        local quiver_mesh_resource = nil
        local quiver_mat_path = nil
        local quiver_mat_resource = nil
        local arrow_mesh_path = nil
        local arrow_mesh_resource = nil
        local arrow_mat_path = nil
        local arrow_mat_resource = nil
        if quiver_weapon_id ~= 0 then
          local quiver_mesh_mat_dic = loaded[quiver_weapon_id] or prefab_paths[quiver_weapon_id]
          if quiver_mesh_mat_dic then
            quiver_mesh_path = quiver_mesh_mat_dic.mesh_path
            quiver_mesh_resource = utils.CreateResource("via.render.MeshResource", quiver_mesh_path)
            quiver_mat_path = quiver_mesh_mat_dic.mat_path
            quiver_mat_resource = utils.CreateResource("via.render.MeshMaterialResource", quiver_mat_path)
            arrow_mesh_path = g_arrow_mesh_path
            arrow_mesh_resource = g_arrow_mesh_resource
            arrow_mat_path = g_arrow_mat_path
            arrow_mat_resource = g_arrow_mat_resource
          end
        end

        local item_id = nil
        local item_name = "NPC_WEAPON"
        local item_style_no_name = "[" .. padded_weapon_id .. "] " .. item_name
        local equip_category = CAT_WEAPON
        if string.find(weapon_type_key, "wp01") then
          equip_category = CAT_SHIELD
        end
        local job = weapon_enum_key and GetJob(weapon_enum_key) or EQUIP_JOB_NPC

        -- if it's a recognized item then override information
        local item_common_param = ItemManager:call(function_name, weapon_id)
        if item_common_param then
          item_id = item_common_param._Id
          item_name = utils.ExpandMessageTags(item_common_param:get_Name()) or item_common_param:get_Name()
          item_style_no_name = "[" .. weapon_id .. "] " .. item_name
          equip_category = item_common_param._EquipCategory
          job = item_common_param:getJob()
        end

        -- add to category list
        if not CATEGORY_ITEM_LIST[equip_category] then CATEGORY_ITEM_LIST[equip_category] = {} end
        table.insert(CATEGORY_ITEM_LIST[equip_category], item_style_no_name)

        -- add to item info dic
        if not ITEM_INFO_DIC[weapon_id] then
          ITEM_INFO_DIC[weapon_id] = {}
        end
        if not ITEM_INFO_DIC[weapon_id][equip_category] then
          ITEM_INFO_DIC[weapon_id][equip_category] = {}
        end

        ITEM_INFO_DIC[weapon_id][equip_category].item_id = item_id
        ITEM_INFO_DIC[weapon_id][equip_category].name = item_name
        ITEM_INFO_DIC[weapon_id][equip_category].id_name = item_style_no_name
        ITEM_INFO_DIC[weapon_id][equip_category].equip_category = equip_category
        ITEM_INFO_DIC[weapon_id][equip_category].weapon_enum_key = weapon_enum_key
        ITEM_INFO_DIC[weapon_id][equip_category].job = job
        ITEM_INFO_DIC[weapon_id][equip_category].mesh_path = mesh_path
        ITEM_INFO_DIC[weapon_id][equip_category].mesh_resource = mesh_resource
        ITEM_INFO_DIC[weapon_id][equip_category].mat_path = mat_path
        ITEM_INFO_DIC[weapon_id][equip_category].mat_resource = mat_resource
        ITEM_INFO_DIC[weapon_id][equip_category].quiver_mesh_path = quiver_mesh_path
        ITEM_INFO_DIC[weapon_id][equip_category].quiver_mesh_resource = quiver_mesh_resource
        ITEM_INFO_DIC[weapon_id][equip_category].quiver_mat_path = quiver_mat_path
        ITEM_INFO_DIC[weapon_id][equip_category].quiver_mat_resource = quiver_mat_resource
        ITEM_INFO_DIC[weapon_id][equip_category].arrow_mesh_path = arrow_mesh_path
        ITEM_INFO_DIC[weapon_id][equip_category].arrow_mesh_resource = arrow_mesh_resource
        ITEM_INFO_DIC[weapon_id][equip_category].arrow_mat_path = arrow_mat_path
        ITEM_INFO_DIC[weapon_id][equip_category].arrow_mat_resource = arrow_mat_resource
      end
    end
    prefab_paths[weapon_id] = loaded[weapon_id] or false
  end

  -- Persist what this launch learned: only new or changed prefabs get prepared on the next launch.
  local saved_ok, saved_error = pcall(function()
    local cache_entries = {}
    for weapon_id, prefab_controller in pairs(catalog) do
      local resource_path = GetPrefabResourcePath(prefab_controller)
      local prepared = prefab_paths[weapon_id]
      local previous = cached_paths[weapon_id]
      local previous_failures = 0
      if previous and previous.src == resource_path then previous_failures = previous.failures or 0 end
      if failed[weapon_id] then
        cache_entries[weapon_id] = {src = resource_path, kind = "failed", failures = previous_failures + 1}
      elseif type(prepared) == "table" and prepared.mesh_path then
        cache_entries[weapon_id] = {src = resource_path, kind = "ok", mesh = prepared.mesh_path, mat = prepared.mat_path}
      elseif prepared == false then
        cache_entries[weapon_id] = {src = resource_path, kind = "no_mesh"}
      elseif previous and previous.src == resource_path then
        cache_entries[weapon_id] = previous
      end
    end
    SaveWeaponCache(cache_build, cache_entries)
  end)
  if not saved_ok then
    utils.Log("[" .. modname .. "] Could not update the weapon path cache: " .. tostring(saved_error))
  end

  CATEGORY_ITEM_LIST[CAT_WEAPON] = CATEGORY_ITEM_LIST[CAT_WEAPON] or {}
  CATEGORY_ITEM_LIST[CAT_SHIELD] = CATEGORY_ITEM_LIST[CAT_SHIELD] or {}
  table.sort(CATEGORY_ITEM_LIST[CAT_WEAPON])
  table.sort(CATEGORY_ITEM_LIST[CAT_SHIELD])
end

local Init
do
  local function CountAppearances()
    local weapons, clothing = #CATEGORY_ITEM_LIST[CAT_WEAPON] + #CATEGORY_ITEM_LIST[CAT_SHIELD], 0
    for category, list in pairs(CATEGORY_ITEM_LIST) do
      if category ~= CAT_WEAPON and category ~= CAT_SHIELD then clothing = clothing + #list end
    end
    return weapons, clothing
  end

  local function ReadCatalogCounts()
    local counts = {weapons = sdk.get_managed_singleton("app.EquipmentManager").WeaponCatalog:get_Count(),
      items = ItemManager._ItemDataDict:get_Count()}
    for _, source in ipairs(Transmogify.CATALOG_CHECK.ARMOR) do
      local styles = 0
      for _, gender_styles in pairs(utils.GetLuaDic(CharacterEditManager:get_field(source.database))) do
        if gender_styles ~= utils.NATIVE_NULL then styles = styles + gender_styles:get_Count() end
      end
      counts[source.database] = styles
    end
    return counts
  end

  -- Adds the weapons not read yet and reads every clothing category again, which also names clothing whose item data
  -- arrived after the last build.
  -- Each count is recorded no higher than what the build read: a catalog that shrank during a scene load while the build
  -- ran counts as grown once it refills, so the next check builds again.
  local function BuildCatalogs()
    local counts = ReadCatalogCounts()
    AddWeapons()
    for _, source in ipairs(Transmogify.CATALOG_CHECK.ARMOR) do
      AddArmorStyle(source.type, source.database, source.category)
    end
    for key, count in pairs(ReadCatalogCounts()) do counts[key] = math.min(counts[key], count) end
    Transmogify.catalog_counts = counts
  end

  function Init()
    BuildCatalogs()
    Refresh()
    Transmogify.init_complete = true
    local weapons, clothing = CountAppearances()
    utils.Log(string.format("[%s] Init complete in %.1f s: %d weapon and shield appearances, %d clothing appearances",
      modname, utils.Seconds() - Transmogify.init_started, weapons, clothing))
  end

  local function UpdateCatalogs()
    local started = utils.Seconds()
    local weapons_before, clothing_before = CountAppearances()
    BuildCatalogs()
    Transmogify.ResetCinematicWeaponCatalog()
    RefreshEquipmentInfoLists()
    local weapons, clothing = CountAppearances()
    if weapons == weapons_before and clothing == clothing_before then return end
    utils.Log(string.format("[%s] Added game content registered after startup in %.1f s: %d weapon and shield " ..
      "appearances, %d clothing appearances (now %d and %d)", modname, utils.Seconds() - started,
      weapons - weapons_before, clothing - clothing_before, weapons, clothing))
  end

  function Transmogify.UpdateCatalogCheck()
    if Transmogify.init_coroutine then
      Transmogify.ResumeCatalogBuild()
      return
    end
    Transmogify.catalog_check_countdown = Transmogify.catalog_check_countdown - 1
    if Transmogify.catalog_check_countdown > 0 then return end
    Transmogify.catalog_check_countdown = Transmogify.CATALOG_CHECK.INTERVAL
    Transmogify.CheckNPCList()
    for key, count in pairs(ReadCatalogCounts()) do
      if count > Transmogify.catalog_counts[key] then
        Transmogify.init_coroutine = coroutine.create(UpdateCatalogs)
        return
      end
    end
  end
end

local function ResetEquipmentInfo()
  for equip_type, equip_info in pairs(EQUIPMENT_INFO) do
    EQUIPMENT_INFO[equip_type].index = 1
    EQUIPMENT_INFO[equip_type].search = ""
    if equip_info.job_name_index_filter then
      EQUIPMENT_INFO[equip_type].job_name_index_filter = GetIndexByVal(job_names,
        EQUIP_JOB_ID_NAME_ENUM[EQUIP_JOB_ALL])
    end

    if equip_info.size then
      EQUIPMENT_INFO[equip_type].size = Transmogify.DEFAULT_PRESET_SIZE
      if CURRENT_SETTINGS.setSize[CURRENT_SET_NAME] and CURRENT_SETTINGS.setSize[CURRENT_SET_NAME][equip_type] then
        EQUIPMENT_INFO[equip_type].size = CURRENT_SETTINGS.setSize[CURRENT_SET_NAME][equip_type]
      end
    end
  end
end

local function ResetUI()
  CURRENT_SET_INDEX = INDEX_NONE
  CURRENT_SET_NAME = ""
  Transmogify.preset_editor.operation = nil
  Transmogify.preset_editor.name = ""
  Transmogify.preset_editor.error = nil
  ResetEquipmentInfo()
  RefreshEquipmentInfoLists()
end

local currentEquipName = "";

do
  local ACTION_NEW = "New"
  local ACTION_DUPLICATE = "Duplicate"
  local ACTION_RENAME = "Rename"
  local ACTION_DELETE = "Delete"
  local SIZE_MIN = 25
  local SIZE_MAX = 300
  local SIZE_STEP = 5
  local EDITOR_PADDING = 32
  local EDITOR_SPACING = 8

  function Transmogify.SettingsChanged(appearance)
    local state = Transmogify.preset_editor
    state.pending_save = true
    state.refresh_pending = true
    state.refresh_appearance = state.refresh_appearance or appearance
    Transmogify.eye_glow.full = true
  end

  function Transmogify.FlushPresetSave()
    local state = Transmogify.preset_editor
    if not state.pending_save then return end
    assert(json.dump_file(settings_path, CURRENT_SETTINGS), "Could not save Transmogify settings")
    state.pending_save = false
  end

  function Transmogify.SelectPreset(name)
    Transmogify.FlushPresetSave()
    ResetUI()
    currentEquipName = ""
    if name == "" or not CURRENT_SETTINGS.sets[name] then return end
    CURRENT_SET_NAME = name
    RefreshSetList()
    ResetEquipmentInfo()
    RefreshEquipmentInfoLists()
  end

  function Transmogify.ApplyPresetOperation(action)
    Transmogify.FlushPresetSave()
    local state = Transmogify.preset_editor
    local source = CURRENT_SET_NAME
    local name = utils.Trim(state.name)
    if action ~= ACTION_NEW and not CURRENT_SETTINGS.sets[source] then return end
    if action ~= ACTION_DELETE then
      if name == "" or name:lower() == SET_VALUE_NONE:lower() then
        state.error = "Enter a name other than NONE."
        return
      end
      for existing in pairs(CURRENT_SETTINGS.sets) do
        if existing:lower() == name:lower() and not (action == ACTION_RENAME and existing == source) then
          state.error = "A preset with that name already exists."
          return
        end
      end
    end
    if action == ACTION_NEW then
      CURRENT_SETTINGS.sets[name] = {}
      CURRENT_SETTINGS.setSize[name] = {}
      CURRENT_SETTINGS.setGlow[name] = {}
      CURRENT_SETTINGS.setEyes[name] = Transmogify.NewEyeSettings()
      CURRENT_SETTINGS.setEmpty[name] = {}
      CURRENT_SETTINGS.setHideSheathed[name] = {}
      for equipType, equipInfo in pairs(EQUIPMENT_INFO) do
        CURRENT_SETTINGS.sets[name][equipType] = SET_VALUE_NONE
        if ARMOR_CATEGORY_TO_SLOT_ENUM[equipInfo.category] then CURRENT_SETTINGS.setEmpty[name][equipType] = false end
        if equipInfo.size then
          CURRENT_SETTINGS.setSize[name][equipType] = Transmogify.DEFAULT_PRESET_SIZE
          CURRENT_SETTINGS.setGlow[name][equipType] = utils.ShallowCopy(Transmogify.GLOW.DEFAULT)
        end
      end
      CURRENT_SETTINGS.setSize[name][Transmogify.QUIVER_EQUIP_TYPE] = Transmogify.DEFAULT_PRESET_SIZE
    elseif action == ACTION_DUPLICATE then
      CURRENT_SETTINGS.sets[name] = utils.ShallowCopy(CURRENT_SETTINGS.sets[source])
      CURRENT_SETTINGS.setSize[name] = utils.ShallowCopy(CURRENT_SETTINGS.setSize[source] or {})
      CURRENT_SETTINGS.setEmpty[name] = utils.ShallowCopy(CURRENT_SETTINGS.setEmpty[source] or {})
      CURRENT_SETTINGS.setHideSheathed[name] = utils.ShallowCopy(CURRENT_SETTINGS.setHideSheathed[source] or {})
      CURRENT_SETTINGS.setGlow[name] = {}
      for equipType, glow in pairs(CURRENT_SETTINGS.setGlow[source] or {}) do
        CURRENT_SETTINGS.setGlow[name][equipType] = utils.ShallowCopy(glow)
      end
      local eyes = CURRENT_SETTINGS.setEyes[source]
      CURRENT_SETTINGS.setEyes[name] = eyes and Transmogify.NewEyeSettings(eyes)
    elseif action == ACTION_RENAME then
      if name ~= source then
        CURRENT_SETTINGS.sets[name] = CURRENT_SETTINGS.sets[source]
        CURRENT_SETTINGS.setSize[name] = CURRENT_SETTINGS.setSize[source]
        CURRENT_SETTINGS.setGlow[name] = CURRENT_SETTINGS.setGlow[source]
        CURRENT_SETTINGS.setEyes[name] = CURRENT_SETTINGS.setEyes[source]
        CURRENT_SETTINGS.setEmpty[name] = CURRENT_SETTINGS.setEmpty[source]
        CURRENT_SETTINGS.setHideSheathed[name] = CURRENT_SETTINGS.setHideSheathed[source]
        CURRENT_SETTINGS.sets[source] = nil
        CURRENT_SETTINGS.setSize[source] = nil
        CURRENT_SETTINGS.setGlow[source] = nil
        CURRENT_SETTINGS.setEyes[source] = nil
        CURRENT_SETTINGS.setEmpty[source] = nil
        CURRENT_SETTINGS.setHideSheathed[source] = nil
        for _, charInfo in ipairs(char_info_list) do
          if CURRENT_SETTINGS[charInfo.settings_set] == source then
            CURRENT_SETTINGS[charInfo.settings_set] = name
          end
        end
        for id, preset in pairs(CURRENT_SETTINGS.npcSets) do
          if preset == source then CURRENT_SETTINGS.npcSets[id] = name end
        end
      end
    elseif action == ACTION_DELETE then
      CURRENT_SETTINGS.sets[source] = nil
      CURRENT_SETTINGS.setSize[source] = nil
      CURRENT_SETTINGS.setGlow[source] = nil
      CURRENT_SETTINGS.setEyes[source] = nil
      CURRENT_SETTINGS.setEmpty[source] = nil
      CURRENT_SETTINGS.setHideSheathed[source] = nil
      for _, charInfo in ipairs(char_info_list) do
        if CURRENT_SETTINGS[charInfo.settings_set] == source then
          CURRENT_SETTINGS[charInfo.settings_set] = SET_VALUE_NONE
        end
      end
      for id, preset in pairs(CURRENT_SETTINGS.npcSets) do
        if preset == source then CURRENT_SETTINGS.npcSets[id] = nil end
      end
      name = ""
    else
      error("Unknown preset operation: " .. tostring(action))
    end
    Transmogify.SettingsChanged(true)
    Transmogify.SelectPreset(name)
    Refresh()
    Transmogify.FilterNPCList()
  end

  function Transmogify.EditPresetValue(equipType, value, field)
    local preset = CURRENT_SETTINGS.sets[CURRENT_SET_NAME]
    if not preset then return end
    if field == Transmogify.EMPTY_ARMOR_FIELD then
      assert(ARMOR_CATEGORY_TO_SLOT_ENUM[EQUIPMENT_INFO[equipType].category], "Empty-slot option requires an armor slot")
      assert(type(value) == "boolean", "Empty-slot option must be boolean")
      local values = CURRENT_SETTINGS.setEmpty[CURRENT_SET_NAME]
      if not values then values = {}; CURRENT_SETTINGS.setEmpty[CURRENT_SET_NAME] = values end
      if values[equipType] == value then return end
      values[equipType] = value
    elseif field == Transmogify.HIDE_SHEATHED.FIELD then
      assert(type(value) == "boolean", "Hide when sheathed must be boolean")
      local values = CURRENT_SETTINGS.setHideSheathed[CURRENT_SET_NAME]
      if not values then values = {}; CURRENT_SETTINGS.setHideSheathed[CURRENT_SET_NAME] = values end
      if values[equipType] == value then return end
      values[equipType] = value
      Transmogify.SettingsChanged(false)
      return
    elseif field == Transmogify.EYES.FIELD then
      CURRENT_SETTINGS.setEyes[CURRENT_SET_NAME] = value
      Transmogify.preset_editor.pending_save = true
      Transmogify.eye_glow.countdown, Transmogify.eye_glow.full = 0, true
      return
    elseif field == Transmogify.GLOW.FIELD then
      local glows = CURRENT_SETTINGS.setGlow[CURRENT_SET_NAME]
      if not glows then
        glows = {}
        CURRENT_SETTINGS.setGlow[CURRENT_SET_NAME] = glows
      end
      glows[equipType] = value
    elseif field then
      local sizes = CURRENT_SETTINGS.setSize[CURRENT_SET_NAME]
      if not sizes then
        sizes = {}
        CURRENT_SETTINGS.setSize[CURRENT_SET_NAME] = sizes
      end
      if sizes[equipType] == value then return end
      sizes[equipType] = value
    else
      if preset[equipType] == value then return end
      preset[equipType] = value
    end
    Transmogify.SettingsChanged(field ~= true)
  end

  function Transmogify.UpdatePresetEditor()
    local state = Transmogify.preset_editor
    local open = reframework:is_drawing_ui()
    if state.ui_open and not open then
      Transmogify.FlushWindowSave()
    elseif not state.drawn then
      Transmogify.FlushPresetSave()
    end
    state.ui_open = open
    state.drawn = false
  end

  -- Pickers hold 32-bit floats, so stored colors compare with the double defaults within half a color step.
  local function IsGlowAtDefaults(values, defaults)
    return math.abs(values.intensity - defaults.intensity) < 0.0005 and math.abs(values.r - defaults.r) < 0.5 / 255 and
      math.abs(values.g - defaults.g) < 0.5 / 255 and math.abs(values.b - defaults.b) < 0.5 / 255 and
      (defaults.sheathed_intensity == nil or math.abs(values.sheathed_intensity - defaults.sheathed_intensity) < 0.0005)
  end

  local function DrawWeaponSizeGlow(equipType, selectionWidth)
    local adjusting = false
    local sizes = CURRENT_SETTINGS.setSize[CURRENT_SET_NAME]
    local percent = sizes and sizes[equipType] or Transmogify.DEFAULT_PRESET_SIZE
    imgui.text("Size")
    imgui.set_next_item_width(selectionWidth)
    local sizeChanged, size = imgui.drag_int("%##size", percent, SIZE_STEP, SIZE_MIN, SIZE_MAX)
    adjusting = imgui.is_item_active() or adjusting
    if sizeChanged then
      size = utils.GetSize(size, SIZE_MIN, SIZE_MAX, SIZE_STEP)
      if EQUIPMENT_INFO[equipType] then EQUIPMENT_INFO[equipType].size = size end
      Transmogify.EditPresetValue(equipType, size, true)
    end
    if equipType == Transmogify.QUIVER_EQUIP_TYPE then return adjusting end
    if imgui.tree_node("Glow") then
      local glow = Transmogify.GetWeaponGlowSettings(CURRENT_SET_NAME, equipType, true)
      local enabledChanged, enabled = imgui.checkbox("Enable custom glow", glow.enabled)
      local defaults = Transmogify.GLOW.DEFAULT
      imgui.same_line()
      imgui.begin_disabled(IsGlowAtDefaults(glow, defaults))
      local reset = imgui.button("Reset##glow_reset")
      if imgui.is_item_hovered() then utils.SetTooltip("Reset the color and both intensities to the defaults.") end
      imgui.end_disabled()
      imgui.begin_disabled(not enabled)
      imgui.text("Color")
      imgui.set_next_item_width(-1)
      local colorChanged, color = imgui.color_edit3("##glow_color", Vector3f.new(glow.r, glow.g, glow.b), 0)
      adjusting = imgui.is_item_active() or adjusting
      imgui.text("Intensity")
      imgui.set_next_item_width(-1)
      local intensityChanged, intensity = imgui.drag_float("##glow_intensity", glow.intensity,
        Transmogify.GLOW.STEP, Transmogify.GLOW.MIN, Transmogify.GLOW.MAX, "%.2f")
      adjusting = imgui.is_item_active() or adjusting
      imgui.text("Intensity when sheathed")
      imgui.set_next_item_width(-1)
      local sheathedChanged, sheathedIntensity = imgui.drag_float("##glow_sheathed_intensity", glow.sheathed_intensity,
        Transmogify.GLOW.STEP, Transmogify.GLOW.MIN, Transmogify.GLOW.MAX, "%.2f")
      adjusting = imgui.is_item_active() or adjusting
      if imgui.is_item_hovered() then
        utils.SetTooltip("Used while the weapon is on your back in the world. Menus, the barber and cutscenes use Intensity.")
      end
      imgui.end_disabled()
      if reset then
        color, intensity = {x = defaults.r, y = defaults.g, z = defaults.b}, defaults.intensity
        sheathedIntensity = defaults.sheathed_intensity
      end
      if enabledChanged or colorChanged or intensityChanged or sheathedChanged or reset then
        intensity = math.max(Transmogify.GLOW.MIN, math.min(Transmogify.GLOW.MAX, intensity))
        sheathedIntensity = math.max(Transmogify.GLOW.MIN, math.min(Transmogify.GLOW.MAX, sheathedIntensity))
        Transmogify.EditPresetValue(equipType, {enabled = enabled, intensity = intensity,
          sheathed_intensity = sheathedIntensity, r = color.x, g = color.y, b = color.z}, Transmogify.GLOW.FIELD)
      end
      imgui.tree_pop()
    end
    return adjusting
  end

  local function DrawEyeSettings()
    local EYES = Transmogify.EYES
    local adjusting, changed = false, false
    local eyes = Transmogify.NewEyeSettings(Transmogify.GetEyeSettings(CURRENT_SET_NAME, true))
    local sameChanged, same = imgui.checkbox("Same for both eyes", eyes.same)
    if sameChanged then
      eyes.same, eyes.right, changed = same, utils.ShallowCopy(eyes.left), true
    end
    for _, side in ipairs(eyes.same and {"left"} or {"left", "right"}) do
      local eye = eyes[side]
      imgui.push_id(side)
      if not eyes.same then imgui.text(side == "left" and "Left eye" or "Right eye") end
      local enabledChanged, enabled = imgui.checkbox("Glow", eye.enabled)
      local defaults = EYES.DEFAULT
      imgui.same_line()
      imgui.begin_disabled(IsGlowAtDefaults(eye, defaults))
      local reset = imgui.button("Reset")
      if imgui.is_item_hovered() then utils.SetTooltip("Reset the color and intensity to the defaults.") end
      imgui.end_disabled()
      imgui.begin_disabled(not enabled)
      imgui.text("Color")
      imgui.set_next_item_width(-1)
      local colorChanged, color = imgui.color_edit3("##eye_color", Vector3f.new(eye.r, eye.g, eye.b), 0)
      adjusting = imgui.is_item_active() or adjusting
      imgui.text("Intensity")
      imgui.set_next_item_width(-1)
      local intensityChanged, intensity = imgui.drag_float("##eye_intensity", eye.intensity,
        math.max(EYES.SPEED_MIN, eye.intensity * EYES.SPEED_RATE), EYES.MIN, EYES.MAX, "%.3f")
      adjusting = imgui.is_item_active() or adjusting
      if imgui.is_item_hovered() then
        utils.SetTooltip("Double-click to type a value. 0.015 is subtle, 0.1 a clear glow, 1 blazing; up to 100.")
      end
      imgui.end_disabled()
      imgui.pop_id()
      if reset then color, intensity = {x = defaults.r, y = defaults.g, z = defaults.b}, defaults.intensity end
      if enabledChanged or colorChanged or intensityChanged or reset then
        eyes[side] = {enabled = enabled, intensity = math.max(EYES.MIN, math.min(EYES.MAX, intensity)),
          r = color.x, g = color.y, b = color.z}
        changed = true
      end
    end
    if changed then
      if eyes.same then eyes.right = utils.ShallowCopy(eyes.left) end
      Transmogify.EditPresetValue(nil, eyes, EYES.FIELD)
    end
    return adjusting
  end

  function Transmogify.DrawPresetEditor()
    local state = Transmogify.preset_editor
    local adjusting = false
    imgui.text("Edit preset")
    imgui.begin_disabled(state.operation ~= nil)
    imgui.set_next_item_width(math.min(300, imgui.get_window_size().x - EDITOR_PADDING))
    local changed, index = imgui.combo("##preset", CURRENT_SET_INDEX, SET_LIST)
    if changed then Transmogify.SelectPreset(index > INDEX_NONE and SET_LIST[index] or "") end

    for _, action in ipairs({ACTION_NEW, ACTION_DUPLICATE, ACTION_RENAME, ACTION_DELETE}) do
      if action == ACTION_NEW or CURRENT_SET_NAME ~= "" then
        if action ~= ACTION_NEW then imgui.same_line() end
        if imgui.button(action .. "##preset") then
          Transmogify.FlushPresetSave()
          state.operation = action
          state.name = action == ACTION_NEW and "" or CURRENT_SET_NAME
          if action == ACTION_DUPLICATE then state.name = CURRENT_SET_NAME .. " copy" end
          state.error = nil
        end
      end
    end
    imgui.end_disabled()

    if not state.operation and CURRENT_SET_NAME ~= "" then
      utils.TextColored("Changes save automatically.", COLOR_INFO)
    end
    imgui.separator()
    if state.operation then
      if state.operation == ACTION_DELETE then
        utils.TextColored('Delete preset "' .. CURRENT_SET_NAME .. '"?', COLOR_INFO)
        imgui.text("Characters using it will be set to NONE.")
      else
        imgui.text(state.operation .. " preset")
        imgui.text("Preset name")
        imgui.set_next_item_width(math.min(300, imgui.get_window_size().x - EDITOR_PADDING))
        local nameChanged, name = imgui.input_text("##preset_name", state.name)
        state.name = name
        if nameChanged then state.error = nil end
      end
      local confirm = state.operation == ACTION_NEW and "Create" or state.operation
      if imgui.button(confirm .. "##confirm_preset") then Transmogify.ApplyPresetOperation(state.operation) end
      imgui.same_line()
      if imgui.button("Cancel##preset") then
        state.operation, state.error, state.name = nil, nil, ""
      end
      if state.error then utils.TextColored(state.error, 0xFF0000FF) end
    elseif CURRENT_SET_NAME == "" then
      local message = "Select or create a preset to edit."
      local area = imgui.get_window_size()
      local textSize = imgui.calc_text_size(message)
      local origin = imgui.get_cursor_pos()
      imgui.set_cursor_pos(Vector2f.new(math.max(origin.x, (area.x - textSize.x) / 2),
        math.max(origin.y, (area.y - textSize.y) / 2)))
      utils.TextColored(message, COLOR_INFO)
    else
      local eyesNode = Transmogify.EYES.NODE
      local eyesOpen = currentEquipName == eyesNode
      imgui.set_next_item_open(eyesOpen, eyesOpen)
      if imgui.tree_node(eyesNode) then
        currentEquipName = eyesNode
        imgui.push_id(eyesNode)
        adjusting = DrawEyeSettings() or adjusting
        imgui.pop_id()
        imgui.tree_pop()
      elseif currentEquipName == eyesNode then
        currentEquipName = ""
      end
      local HIDE_SHEATHED = Transmogify.HIDE_SHEATHED
      local hideAll = Transmogify.GetHideWhenSheathed(CURRENT_SET_NAME, HIDE_SHEATHED.ALL, true)
      local weaponsStarted = false
      for _, equipType in ipairs(EQUIPMENT_INFO_ORDER) do
        local equipInfo = EQUIPMENT_INFO[equipType]
        if equipInfo.size and not weaponsStarted then
          weaponsStarted = true
          local hideAllChanged, hideAllValue = imgui.checkbox("Hide all weapons when sheathed", hideAll)
          if imgui.is_item_hovered() then
            utils.SetTooltip("Weapons and shields disappear from the back while sheathed and return as you draw them.")
          end
          if hideAllChanged then Transmogify.EditPresetValue(HIDE_SHEATHED.ALL, hideAllValue, HIDE_SHEATHED.FIELD) end
        end
        local open = currentEquipName == equipType
        imgui.set_next_item_open(open, open)
        if imgui.tree_node(equipType) then
          currentEquipName = equipType
          imgui.push_id(equipType)
          local contentWidth = math.max(160, imgui.get_window_size().x - EDITOR_PADDING)
          local searchWidth = math.min(150, math.floor(contentWidth * 0.35))
          local selectionWidth = contentWidth - searchWidth - EDITOR_SPACING
          if equipInfo.job_name_index_filter then
            imgui.text("Job Filter")
            imgui.set_next_item_width(150)
            local filterChanged, jobIndex = imgui.combo("##job_filter", equipInfo.job_name_index_filter, job_names)
            if filterChanged then
              equipInfo.job_name_index_filter = jobIndex
              RefreshEquipmentInfoLists()
            end
          end

          imgui.text("Search")
          imgui.set_next_item_width(searchWidth)
          local searchChanged, search = imgui.input_text("##search", equipInfo.search)
          if searchChanged then
            equipInfo.search = search
            RefreshEquipmentInfoLists()
          end
          imgui.same_line()
          imgui.set_next_item_width(selectionWidth)
          local itemChanged, itemIndex = imgui.combo("##appearance", equipInfo.index, equipInfo.list)
          if itemChanged then
            equipInfo.index = itemIndex
            Transmogify.EditPresetValue(equipType, equipInfo.list[itemIndex], false)
          end

          imgui.indent(searchWidth + EDITOR_SPACING)
          imgui.begin_disabled(equipInfo.index <= 1)
          if imgui.button("Previous") and equipInfo.index > 1 then
            equipInfo.index = equipInfo.index - 1
            Transmogify.EditPresetValue(equipType, equipInfo.list[equipInfo.index], false)
          end
          imgui.end_disabled()
          imgui.same_line()
          imgui.begin_disabled(equipInfo.index >= #equipInfo.list)
          if imgui.button("Next") and equipInfo.index < #equipInfo.list then
            equipInfo.index = equipInfo.index + 1
            Transmogify.EditPresetValue(equipType, equipInfo.list[equipInfo.index], false)
          end
          imgui.end_disabled()
          imgui.unindent(searchWidth + EDITOR_SPACING)

          if ARMOR_CATEGORY_TO_SLOT_ENUM[equipInfo.category] then
            local empty = Transmogify.GetShowWhenUnequipped(CURRENT_SET_NAME, equipType, true)
            local emptyChanged, showEmpty = imgui.checkbox("Show when unequipped", empty)
            if emptyChanged then Transmogify.EditPresetValue(equipType, showEmpty, Transmogify.EMPTY_ARMOR_FIELD) end
          end

          if equipInfo.size then
            imgui.indent(searchWidth + EDITOR_SPACING)
            imgui.spacing()
            imgui.begin_disabled(hideAll)
            local hideSheathed = hideAll or Transmogify.GetHideWhenSheathed(CURRENT_SET_NAME, equipType, true)
            local hideChanged, hideValue = imgui.checkbox("Hide when sheathed", hideSheathed)
            if imgui.is_item_hovered() then
              utils.SetTooltip("Disappears from the back while sheathed and returns as you draw it. A bow also hides its " ..
                "arrow and quiver.")
            end
            imgui.end_disabled()
            if hideChanged and not hideAll then
              Transmogify.EditPresetValue(equipType, hideValue, HIDE_SHEATHED.FIELD)
            end
            adjusting = DrawWeaponSizeGlow(equipType, selectionWidth) or adjusting
            if equipType == EQUIPMENT_INFO_ARCHER_WEAPON and imgui.tree_node("Quiver") then
              imgui.push_id(Transmogify.QUIVER_EQUIP_TYPE)
              adjusting = DrawWeaponSizeGlow(Transmogify.QUIVER_EQUIP_TYPE, -1) or adjusting
              imgui.pop_id()
              imgui.tree_pop()
            end
            imgui.unindent(searchWidth + EDITOR_SPACING)
          end
          imgui.pop_id()
          imgui.tree_pop()
        elseif currentEquipName == equipType then
          currentEquipName = ""
        end
      end
    end
    return adjusting
  end
end

local function DrawPerfStatsUI()
  local snapshot = PERF_DATA.snapshot
  if not snapshot then
    utils.TextColored("Performance: collecting a one-second window...", PERF_COLOR_OK)
    return
  end
  imgui.text(string.format("Last %.2f seconds | %d updates", snapshot.seconds, snapshot.updates))
  imgui.text("Average cost per update (ms)")
  local total_color = PERF_COLOR_OK
  if snapshot.total_ms >= PERF_TOTAL_HIGH_MS then
    total_color = PERF_COLOR_HIGH
  elseif snapshot.total_ms >= PERF_HIGH_MS then
    total_color = COLOR_INFO
  end
  utils.TextColored(string.format("Total: %.4f", snapshot.total_ms), total_color)
  for _, name in ipairs(PERF_SECTION_ORDER) do
    local group = PERF_SECTION_GROUP[name]
    if group then
      imgui.spacing()
      imgui.text(group)
    end
    local value = snapshot.sections[name]
    local text = string.format("  %s: %.4f", PERF_SECTION_LABEL[name], value)
    if name == "weapon_glow" then text = text .. string.format(" (%.1f calls)", snapshot.glow_calls) end
    if value >= PERF_HIGH_MS then utils.TextColored(text, PERF_COLOR_HIGH) else imgui.text(text) end
  end
end

-- Isolate appearance-editor locals from the main Lua chunk's 200-local limit.
(function()
  local PRESET_PATH = "Transmogify/appearance_presets/"
  local NATIVE_TYPES = {
    byte = sdk.find_type_definition("System.Byte"),
    word = sdk.find_type_definition("System.UInt32"),
    pointer = sdk.find_type_definition("System.UInt64"),
  }
  local PRESET_FORMAT = "transmogify_appearance"
  local PRESET_VERSION = 1
  local ACTION_NEW, ACTION_DUPLICATE = "new", "duplicate"
  local ACTION_UPDATE = "update"
  local ACTION_SAVE, ACTION_LOAD = "save", "load"
  local ACTION_NPC = "npc"
  local ACTION_RENAME, ACTION_DELETE = "rename", "delete"
  local ACTION_OPEN_FOLDER = "open_folder"
  local ACTION_REFRESH = "refresh"
  local ACTIONS = {{ACTION_NEW, "New"}, {ACTION_DUPLICATE, "Duplicate"}, {ACTION_RENAME, "Rename"}, {ACTION_DELETE, "Delete"}}
  local IMGUI_COLOR_TEXT = 0
  local DETAIL_TYPE = "app.BodyDetailContext"
  local DETAIL_PARTS_TYPE = "app.GUIPreviewModelEditor.BodyDetailParts"
  local POSTURE_TYPE = "app.CharacterEditDefine.Pretender"
  local TATTOO_SLOT_TYPE = "app.charaedit.ch000.Tattoos.SlotData"
  local SCAR_SLOT_TYPE = "app.charaedit.ch000.Scars.SlotData"
  local COLOR_TYPE = sdk.find_type_definition("via.Color")
  local DETAIL_ENABLED_OFFSET = 0x20
  local ARRAY_LENGTH_OFFSET = 0x1c
  local ARRAY_VALUES_OFFSET = 0x20
  local POINTER_BYTES = 8
  local MAKEUP_FIELDS = {Eyeliner = true, Eyeshadow = true, Cheek = true, Lips = true}
  local SELF_FIELDS = {
    [DETAIL_TYPE .. ".EyesContext"] = "Common", [DETAIL_TYPE .. ".EyelashesContext"] = "Base",
    [DETAIL_TYPE .. ".EyeshadowContext"] = "Common", [DETAIL_TYPE .. ".LipsContext"] = "Common",
  }
  local STYLE_FIELDS = {
    "HeadStyle", "SkinStyle", "MuscleStyle", "HairStyle", "BeardStyle", "BodyHairStyle",
    "EyeStyle", "EyeLeftStyle", "EyeRightStyle", "EyebrowStyle", "EyelashStyle",
    "EyelinerStyle", "EyeshadowStyle", "CheekStyle", "LipStyle", "FrecklesStyle", "NoseStyle",
    "FurStyle", "FurPattern", "FurFaceStyle", "FurForeheadStyle", "FurEyeStyle", "FurCheekStyle", "FurNoseStyle",
  }
  local TYPE_LIMITS = {
    ["System.Byte"] = {0, 255}, ["System.UInt16"] = {0, 65535},
    ["System.Int32"] = {-2147483648, 2147483647}, ["System.UInt32"] = {0, 4294967295},
  }
  local FIELD_CACHE = {}
  local ENUM_CACHE = {}
  local READBACK_EPSILON = 0.0001
  local BASE_BODY_COUNT = 4
  local BASE_PHASE = "base"
  local READBACK_UPDATES = 3
  local APPEARANCE_MENUS = {[13] = "app.ui070414", [30] = "app.ui070406_01"}
  local NPC_APPEARANCE_PROMPT = "Select NPC to copy"
  Transmogify.CHARACTER_TAB = 3
  Transmogify.appearance_presets = {name = "", files = {}, selected = 0}
  Transmogify.npc_appearance_picker = {search = "", rows = {}, filtered = {}, labels = {NPC_APPEARANCE_PROMPT},
    selected_index = 1, status = "waiting", retry_frames = 0}

  local NativeAppearanceView
  local NATIVE_APPEARANCE_METHODS = {}

  function NATIVE_APPEARANCE_METHODS:get_address() return self.address end
  function NATIVE_APPEARANCE_METHODS:get_type_definition() return self.definition end

  function NATIVE_APPEARANCE_METHODS:get_field(name)
    local field = assert(self.definition:get_field(name), "Missing native appearance field: " .. name)
    local field_type = field:get_type()
    local pointer = sdk.to_ptr(self.address + field:get_offset_from_base())
    if field_type:is_value_type() then
      local type_name = field_type:get_full_name()
      if type_name == "via.Color" then
        local color = ValueType.new(COLOR_TYPE)
        color:set_field("rgba", sdk.get_native_field(pointer, NATIVE_TYPES.word, "m_value"))
        return color
      end
      local scalar_type = field_type
      if type_name:sub(1, 7) ~= "System." then
        scalar_type = assert(field_type:get_field("value__"), "Missing appearance enum storage type: " .. type_name):get_type()
      end
      return sdk.get_native_field(pointer, scalar_type, "m_value")
    end
    local address = sdk.get_native_field(pointer, NATIVE_TYPES.pointer, "m_value")
    return NativeAppearanceView(address, field_type)
  end

  function NATIVE_APPEARANCE_METHODS:set_field(name, value)
    local field = assert(self.definition:get_field(name), "Missing native appearance field: " .. name)
    local field_type = field:get_type()
    assert(field_type:is_value_type(), "Appearance writes must contain value fields only: " .. name)
    local type_name = field_type:get_full_name()
    local scalar_type = field_type
    if type_name == "via.Color" then
      scalar_type, value = NATIVE_TYPES.word, value:get_field("rgba")
    elseif type_name:sub(1, 7) ~= "System." then
      scalar_type = assert(field_type:get_field("value__"), "Missing appearance enum storage type: " .. type_name):get_type()
    end
    sdk.set_native_field(sdk.to_ptr(self.address + field:get_offset_from_base()), scalar_type, "m_value", value)
  end

  function NATIVE_APPEARANCE_METHODS:read_byte(offset)
    return sdk.get_native_field(sdk.to_ptr(self.address + offset), NATIVE_TYPES.byte, "m_value")
  end

  function NATIVE_APPEARANCE_METHODS:write_byte(offset, value)
    assert(offset == DETAIL_ENABLED_OFFSET, "Unexpected native appearance flag offset")
    sdk.set_native_field(sdk.to_ptr(self.address + offset), NATIVE_TYPES.byte, "m_value", value)
  end

  function NATIVE_APPEARANCE_METHODS:get_SlotDatas()
    return self:get_field(self.definition:get_full_name() == "app.charaedit.ch000.Tattoos" and "_Tattoos" or "_Scars")
  end

  function NATIVE_APPEARANCE_METHODS:get_size()
    assert(self.definition:get_full_name():sub(-2) == "[]", "Expected appearance array")
    return sdk.get_native_field(sdk.to_ptr(self.address + ARRAY_LENGTH_OFFSET), NATIVE_TYPES.word, "m_value")
  end

  local NATIVE_APPEARANCE_METATABLE = {
    __index = function(object, key)
      if type(key) ~= "number" then return NATIVE_APPEARANCE_METHODS[key] or object:get_field(key) end
      assert(key >= 0 and key < object:get_size() and key % 1 == 0, "Appearance array index out of bounds")
      local address = sdk.get_native_field(sdk.to_ptr(object.address + ARRAY_VALUES_OFFSET + key * POINTER_BYTES), NATIVE_TYPES.pointer, "m_value")
      local element_type = sdk.find_type_definition(object.definition:get_full_name():sub(1, -3))
      return NativeAppearanceView(address, element_type)
    end,
  }

  NativeAppearanceView = function(address, definition)
    assert(type(address) == "number" and address > 0 and address % POINTER_BYTES == 0, "Invalid native appearance working pointer")
    return setmetatable({address = address, definition = definition}, NATIVE_APPEARANCE_METATABLE)
  end

  local function PresetName(name)
    return utils.NormalizeFileName(name, 80)
  end

  function Transmogify.RefreshAppearancePresets()
    local state = Transmogify.appearance_presets
    local selected = state.files[state.selected]
    state.files = {}
    for _, path in ipairs(fs.glob([[^.*\.[jJ][sS][oO][nN]$]])) do
      path = path:gsub("\\", "/")
      local name = path:sub(#PRESET_PATH + 1, -6)
      if path:sub(1, #PRESET_PATH):lower() == PRESET_PATH:lower() and PresetName(name) == name then
        state.files[#state.files + 1] = name
      end
    end
    table.sort(state.files, function(a, b) return a:lower() < b:lower() end)
    state.selected = 0
    for index, name in ipairs(state.files) do
      if name == selected then state.selected = index end
    end
    state.listed = true
    Transmogify.FilterNPCList()
  end

  local function FindAppearanceFile(name)
    for _, candidate in ipairs(Transmogify.appearance_presets.files) do
      if candidate:lower() == name:lower() then return candidate end
    end
  end

  local function AppearanceFileExists(name)
    return utils.FileExists(PRESET_PATH .. name .. ".json")
  end

  local function MigrateNpcAppearances(source, name)
    for id, preset in pairs(CURRENT_SETTINGS.npcAppearances) do
      if preset == source then
        CURRENT_SETTINGS.npcAppearances[id] = name
        Transmogify.npc_looks.checked[id] = nil
        Transmogify.preset_editor.pending_save = true
      end
    end
  end

  local function RecheckNpcAppearances(name)
    for id, preset in pairs(CURRENT_SETTINGS.npcAppearances) do
      if preset == name then Transmogify.npc_looks.checked[id] = nil end
    end
  end

  local function UpdateAppearanceFiles(request)
    local state = Transmogify.appearance_presets
    if request.action == ACTION_OPEN_FOLDER then
      state.message = "Could not open the appearance preset folder."
      utils.OpenFolder(PRESET_PATH)
      state.status, state.message = "complete", "Opened the appearance preset folder."
      return
    end
    Transmogify.RefreshAppearancePresets()
    if request.action == ACTION_REFRESH then
      state.status, state.message = "complete", "Preset list refreshed."
      return
    end
    local source = PresetName(request.source)
    assert(source and FindAppearanceFile(source) == source, "The selected preset no longer exists. Refresh the list.")
    local source_path = PRESET_PATH .. source .. ".json"
    if request.action == ACTION_DELETE then
      state.message = "Could not delete preset: " .. source
      utils.DeleteFile(source_path)
      MigrateNpcAppearances(source, nil)
      Transmogify.RefreshAppearancePresets()
      if state.last_file == source_path then state.last_file = nil end
      state.name = ""
      state.status, state.message = "complete", "Deleted preset: " .. source
      return
    end
    assert(request.action == ACTION_DUPLICATE or request.action == ACTION_RENAME, "Unknown appearance file operation")
    local name = assert(PresetName(request.name), "Invalid preset name")
    local case_rename = request.action == ACTION_RENAME and source:lower() == name:lower()
    assert(case_rename or not FindAppearanceFile(name) and not AppearanceFileExists(name), "A preset with that name already exists.")
    local destination_path = PRESET_PATH .. name .. ".json"
    if request.action == ACTION_RENAME then
      state.message = "Could not rename preset: " .. source
      utils.RenameFile(source_path, destination_path)
      MigrateNpcAppearances(source, name)
      if state.last_file == source_path then state.last_file = destination_path end
    else
      local preset = assert(json.load_file(source_path), "Could not read the selected preset")
      assert(preset.format == PRESET_FORMAT and preset.version == PRESET_VERSION, "Unsupported appearance preset format/version")
      preset.name = name
      assert(json.dump_file(destination_path, preset, 2), "Could not save the new preset file")
    end
    RecheckNpcAppearances(name)
    Transmogify.RefreshAppearancePresets()
    if Transmogify.window.tab == Transmogify.CHARACTER_TAB then
      for index, candidate in ipairs(state.files) do if candidate == name then state.selected = index end end
    end
    state.name = ""
    state.status = "complete"
    state.message = (request.action == ACTION_RENAME and "Renamed preset: " or "Created preset: ") .. name
  end

  function Transmogify.IsAppearanceBusy()
    local state = Transmogify.appearance_presets
    return state.request ~= nil or state.pending ~= nil
  end

  local function ResetNpcAppearanceSelection()
    local picker = Transmogify.npc_appearance_picker
    picker.search, picker.selected_index = "", 1
    Transmogify.FilterNpcAppearances()
    Transmogify.appearance_presets.npc_name = nil
  end

  function Transmogify.ResetAppearanceEditor()
    local state = Transmogify.appearance_presets
    state.selected, state.name = 0, ""
    ResetNpcAppearanceSelection()
    state.operation, state.error = nil, nil
    state.status, state.message = nil, nil
  end

  function Transmogify.QueueAppearanceOperation(action, name)
    local state = Transmogify.appearance_presets
    if Transmogify.IsAppearanceBusy() then return end
    state.error, state.status, state.message = nil, nil, nil
    local controller = GuiManager and GuiManager._CharaEditCtrl
    if action ~= ACTION_OPEN_FOLDER and (not controller or not utils.GetGameObject(controller) or not controller.Edit) then
      state.error = "Open the character editor first."
      return
    end
    local source = state.files[state.selected]
    if action == ACTION_NEW or action == ACTION_DUPLICATE or action == ACTION_RENAME then
      name = PresetName(name)
      if not name then
        state.error = "Use a name of 1-80 characters without filename symbols or consecutive dots."
        return
      end
      if name:lower() == SET_VALUE_NONE:lower() then
        state.error = "Enter a name other than NONE."
        return
      end
      Transmogify.RefreshAppearancePresets()
      local case_rename = action == ACTION_RENAME and source and source:lower() == name:lower()
      if not case_rename and (FindAppearanceFile(name) or AppearanceFileExists(name)) then
        state.error = "A preset with that name already exists."
        return
      end
    end
    if action ~= ACTION_NEW and action ~= ACTION_NPC and action ~= ACTION_REFRESH and action ~= ACTION_OPEN_FOLDER and not source then
      state.error = "Select an appearance preset first."
      return
    end
    local request = {action = action, name = name, source = source}
    if action == ACTION_NPC then
      local picker = Transmogify.npc_appearance_picker
      local npc = picker.status == "ready" and picker.filtered[picker.selected_index]
      if not npc then
        state.error = "Select an NPC appearance first."
        return
      end
      request.npc_id, request.npc_appearance_id, request.name = npc.id, npc.appearance_id, npc.name
      state.selected = 0
    elseif action == ACTION_LOAD then
      ResetNpcAppearanceSelection()
    end
    if action == ACTION_NEW or action == ACTION_UPDATE or action == ACTION_LOAD or action == ACTION_NPC then
      local is_player = controller:get_IsPlayer()
      local is_barber = controller:get_IsBarber()
      local character
      if is_barber then
        if is_player then character = utils.GetPlayer() else character = utils.GetMainPawn() end
      end
      if action ~= ACTION_NPC then
        request.action = action == ACTION_LOAD and ACTION_LOAD or ACTION_SAVE
        request.name = action == ACTION_NEW and name or source
      end
      request.overwrite = action == ACTION_UPDATE
      request.target_index = is_player and 1 or 2
      request.character_address = character and sdk.to_ptr(character)
      request.controller_address, request.is_barber = sdk.to_ptr(controller), is_barber
      request.subject_id = controller.Edit.CharaId
    end
    state.request, state.operation = request, nil
    state.status, state.message = "queued", "Waiting for the appearance operation."
  end

  local function PresetFields(type_name)
    if FIELD_CACHE[type_name] then return FIELD_CACHE[type_name] end
    assert(type_name == DETAIL_TYPE or type_name:sub(1, #DETAIL_TYPE + 1) == DETAIL_TYPE .. "." or
      type_name == POSTURE_TYPE or type_name == TATTOO_SLOT_TYPE or type_name == SCAR_SLOT_TYPE,
      "Unsupported appearance data type: " .. type_name)
    local fields = {}
    local definition = sdk.find_type_definition(type_name)
    while definition do
      for _, field in ipairs(definition:get_fields()) do
        local name = field:get_name()
        if not field:is_static() and name:sub(1, 1) == "_" then
          fields[#fields + 1] = {name = name:sub(2), type_name = field:get_type():get_full_name()}
        end
      end
      definition = definition:get_parent_type()
      if not definition or definition:get_full_name():sub(1, #DETAIL_TYPE + 1) ~= DETAIL_TYPE .. "." then break end
    end
    assert(#fields > 0, "Missing appearance fields: " .. type_name)
    FIELD_CACHE[type_name] = fields
    return fields
  end

  local function AppearanceValue(object, type_name, name)
    if SELF_FIELDS[type_name] == name then return object end
    if type_name == DETAIL_TYPE .. ".EyesContext" and (name == "Left" or name == "Right") then
      return object:get_field("_" .. name .. "Eye")
    end
    if name == "Enabled" then return object:read_byte(DETAIL_ENABLED_OFFSET) ~= 0 end
    if name == "SlotDatas" then return object:get_SlotDatas() end
    if type_name == DETAIL_TYPE then
      local parts = object:get_type_definition():get_full_name() == DETAIL_PARTS_TYPE
      if MAKEUP_FIELDS[name] then
        local makeup = parts and object.Makeup or object._Makeup
        return makeup:get_field("_" .. name)
      end
      if parts then return object:get_field(name) end
    end
    return object:get_field("_" .. name)
  end

  local function ReadAppearanceObject(object, type_name)
    assert(object, "Missing appearance object: " .. type_name)
    local result = {}
    for _, entry in ipairs(PresetFields(type_name)) do
      local value = AppearanceValue(object, type_name, entry.name)
      assert(value ~= nil, "Missing appearance value: " .. type_name .. "." .. entry.name)
      if entry.type_name == "via.Color" then
        local packed = value:get_field("rgba")
        value = {r = packed & 0xff, g = (packed >> 8) & 0xff, b = (packed >> 16) & 0xff, a = (packed >> 24) & 0xff}
      elseif entry.type_name:sub(-2) == "[]" then
        local values, count
        if getmetatable(value) == NATIVE_APPEARANCE_METATABLE then
          values, count = {}, value:get_size()
          for index = 1, count do values[index] = value[index - 1] end
        else
          values, count = utils.GetLuaArray(value)
        end
        local array = {}
        for index = 1, count do
          array[index] = ReadAppearanceObject(values[index], entry.type_name:sub(1, -3))
        end
        value = array
      elseif type(value) ~= "number" and type(value) ~= "boolean" then
        value = ReadAppearanceObject(value, entry.type_name)
      end
      result[entry.name] = value
    end
    return result
  end

  local function CheckAppearanceNumber(value, type_name, path)
    assert(type(value) == "number" and value == value and math.abs(value) <= 3.402823466e38,
      "Invalid number: " .. path)
    if type_name == "System.Single" then return end
    assert(value % 1 == 0, "Expected integer: " .. path)
    local limits = TYPE_LIMITS[type_name]
    if limits then
      assert(value >= limits[1] and value <= limits[2], "Number out of range: " .. path)
      return
    end
    if not ENUM_CACHE[type_name] then
      local values = {}
      for _, number in pairs(utils.GetEnumDic(type_name)) do values[number] = true end
      ENUM_CACHE[type_name] = values
    end
    assert(ENUM_CACHE[type_name][value], "Unknown appearance enum value: " .. path)
  end

  local function CheckAppearanceData(value, expected, path)
    assert(type(value) == type(expected), "Invalid or missing value: " .. path)
    if type(expected) == "table" then
      for key, item in pairs(expected) do CheckAppearanceData(value[key], item, path .. "." .. tostring(key)) end
      for key in pairs(value) do assert(expected[key] ~= nil, "Unexpected value: " .. path .. "." .. tostring(key)) end
    elseif type(expected) == "number" then
      CheckAppearanceNumber(value, "System.Single", path)
    end
  end

  local function PrepareAppearanceWrites(data, type_name, target, source, writes)
    assert(target and source and target:get_address() ~= source:get_address(), "Appearance working copy is not independent: " .. type_name)
    for _, entry in ipairs(PresetFields(type_name)) do
      local value = data[entry.name]
      local path = type_name .. "." .. entry.name
      local target_value = AppearanceValue(target, type_name, entry.name)
      local source_value = AppearanceValue(source, type_name, entry.name)
      assert(target_value ~= nil and source_value ~= nil, "Missing appearance working value: " .. path)
      if entry.type_name == "via.Color" then
        for _, channel in ipairs({"r", "g", "b", "a"}) do CheckAppearanceNumber(value[channel], "System.Byte", path .. "." .. channel) end
        local color = ValueType.new(COLOR_TYPE)
        color:set_field("rgba", value.r | (value.g << 8) | (value.b << 16) | (value.a << 24))
        value = color
      elseif entry.type_name:sub(-2) == "[]" then
        local element_type = entry.type_name:sub(1, -3)
        assert(target_value:get_address() ~= source_value:get_address() and target_value:get_size() == #value and
          source_value:get_size() == #value, "Appearance working array is shared or has a different layout: " .. path)
        for index, item in ipairs(value) do
          PrepareAppearanceWrites(item, element_type, target_value[index - 1], source_value[index - 1], writes)
        end
        value = nil
      elseif entry.type_name == "System.Boolean" then
        assert(type(value) == "boolean", "Expected boolean: " .. path)
      elseif type(value) == "number" then
        CheckAppearanceNumber(value, entry.type_name, path)
      else
        PrepareAppearanceWrites(value, entry.type_name, target_value, source_value, writes)
        value = nil
      end
      if value ~= nil then
        writes[#writes + 1] = {object = target, field = "_" .. entry.name, value = value,
          byte_offset = entry.name == "Enabled" and DETAIL_ENABLED_OFFSET or nil}
      end
    end
  end

  local function CaptureAppearance(context, name)
    local result = {format = PRESET_FORMAT, version = PRESET_VERSION, name = name,
      species = context.human:get_Species(), gender = context.human:get_Gender(), styles = {},
      face = {}, body = {}, posture = ReadAppearanceObject(context.body._PretenderData, POSTURE_TYPE),
      details = ReadAppearanceObject(context.detail, DETAIL_TYPE)}
    for _, field in ipairs(STYLE_FIELDS) do result.styles[field] = context.swapper._Meta:get_field("_" .. field) end
    for _, name in ipairs({"face", "body"}) do
      local inputs = assert(context[name]:getEditValues(), "Appearance inputs unavailable: " .. name)
      local input_values, input_count = utils.GetLuaArray(inputs)
      for index = 0, input_count - 1 do
        local input = input_values[index + 1]
        result[name][tostring(input._EditKeyHash)] = input._Value
      end
    end
    return result
  end

  local function AppearanceContext(request)
    local controller = GuiManager and GuiManager._CharaEditCtrl
    if not controller or not utils.GetGameObject(controller) or sdk.to_ptr(controller) ~= request.controller_address or
      controller:get_IsBarber() ~= request.is_barber or not controller.IsSavedInitHistory or controller.PreviewModelDispBanned then return nil end
    local edit = controller.Edit
    local human = edit and edit.EditCtrl
    local editor = controller:get_ModelEditor()
    local object = editor and editor:get_PreviewModelObj()
    local menu = controller.CurrSubMenu
    if not human or not utils.GetGameObject(human) or edit.CharaId ~= request.subject_id or
      human:get_PreviewCharacterID() ~= edit.CharaId or request.human_address and sdk.to_ptr(human) ~= request.human_address or
      not menu or menu:get_type_definition():get_full_name() ~= APPEARANCE_MENUS[controller.FlowNow] then return nil end
    if request.is_barber then
      local character
      if request.target_index == 1 then character = utils.GetPlayer()
      elseif request.target_index == 2 then character = utils.GetMainPawn() end
      if request.target_index > 2 or not character or sdk.to_ptr(character) ~= request.character_address or
        character:get_CharaID() ~= edit.CharaId then return nil end
    end
    if not object or not object:get_Valid() then return nil, request.phase == BASE_PHASE end
    local context = {controller = controller, human = human, editor = editor, object = object,
      face = editor:get_FaceEdit(), body = editor:get_BodyEdit(), detail = editor:get_DetailEdit(), swapper = editor:get_PartSwap()}
    for _, name in ipairs({"face", "body", "detail", "swapper"}) do
      if not context[name] or not utils.GetGameObject(context[name]) then return nil, request.phase == BASE_PHASE end
    end
    if not context.swapper._Meta or not context.body._PretenderData or not editor.BodyDetailEdit or
      not editor.BodyDetailEdit.Skin or not editor.BodyDetailEdit.Hair then return nil, request.phase == BASE_PHASE end
    return context
  end

  local function AppearanceDifferences(actual, expected, path, differences)
    if type(actual) == "table" and type(expected) == "table" then
      for key, value in pairs(expected) do AppearanceDifferences(actual[key], value, path .. "." .. tostring(key), differences) end
      for key in pairs(actual) do
        if expected[key] == nil then differences[#differences + 1] = {path = path .. "." .. tostring(key), reason = "unexpected value"} end
      end
      return
    end
    if type(actual) == "number" and type(expected) == "number" and math.abs(actual - expected) <= READBACK_EPSILON then return end
    if actual ~= expected then differences[#differences + 1] = {path = path, expected = expected, actual = actual} end
  end

  local NO_APPEARANCE_STYLE = 0
  local NPC_EDITOR_RETRY_FRAMES = 15
  Transmogify.npc_editor = {status = "waiting", retry_frames = 0, catalog_changes = {}, allowance_changes = {}}

  local function AllowAppearanceStyle(human, field, style, species_id, gender_id)
    local database = assert(human:get_field(field), "Missing preview style eligibility: " .. field)
    local style_exists = database:ContainsKey(style)
    local species = style_exists and database:get_Item(style)
    local species_exists = species and species:ContainsKey(species_id)
    local genders = species_exists and species:get_Item(species_id)
    local allowed = genders and genders:Contains(gender_id) or false
    if not allowed then
      if not species then
        species = sdk.create_instance("System.Collections.Generic.Dictionary`2<System.UInt32,System.Collections.Generic.HashSet`1<System.UInt32>>"):add_ref()
        species:call(".ctor()")
      end
      if not genders then
        genders = sdk.create_instance("System.Collections.Generic.HashSet`1<System.UInt32>"):add_ref()
        genders:call(".ctor()")
      end
      genders:Add(gender_id)
      if not species_exists then species:Add(species_id, genders) end
      if not style_exists then database:Add(style, species) end
    end
    assert(database:get_Item(style):get_Item(species_id):Contains(gender_id),
      "Preview did not retain style eligibility: " .. field)
    return {style = style, species = species_id, gender = gender_id, added = not allowed}
  end

  local NPC_EDITOR_FORMS = {
    {name = "Human Female", species = "Human", gender = "Female", heads = "HFHeadStyles", hairs = "FHairStyles", head_prefix = "Head_HF_", prefix = "HF",
      skins = "HFSkinStyles", beards = "BeardStyles", eyes = "EyeStyles", fur = false},
    {name = "Human Male", species = "Human", gender = "Male", heads = "HMHeadStyles", hairs = "HairStyles", head_prefix = "Head_HM_", prefix = "HM",
      skins = "HMSkinStyles", beards = "BeardStyles", eyes = "EyeStyles", fur = false},
    {name = "Beastren Female", species = "Beastman", gender = "Female", heads = "BFHeadStyles", hairs = "BFHairStyles", head_prefix = "Head_BF_", prefix = "BF",
      skins = "BFSkinStyles", beards = "BBeardStyles", eyes = "BEyeStyles", fur = "BFFurStyles", freckles = false},
    {name = "Beastren Male", species = "Beastman", gender = "Male", heads = "BMHeadStyles", hairs = "BMHairStyles", head_prefix = "Head_BM_", prefix = "BM",
      skins = "BMSkinStyles", beards = "BBeardStyles", eyes = "BEyeStyles", fur = "BMFurStyles", freckles = false},
  }
  local NPC_EDITOR_STYLES = {
    {key = "heads", field = "HeadStyle", database = "_HeadLimitDB", texture_type = "app.GUITextureLoaderDefine.EditHeadTextureID"},
    {key = "hairs", field = "HairStyle", database = "_HairLimitDB", texture_type = "app.GUITextureLoaderDefine.EditHairTextureID"},
    {key = "skins", field = "SkinStyle", database = "_SkinLimitDB", texture_type = "app.GUITextureLoaderDefine.EditSkinTextureID"},
    {key = "beards", field = "BeardStyle", database = "_BeardLimitDB", texture_type = "app.GUITextureLoaderDefine.EditBeardTextureID"},
    {key = "eyes", field = "EyeStyle", fields = {"EyeStyle", "EyeLeftStyle", "EyeRightStyle"}, database = "_EyeLimitDB", texture_type = "app.GUITextureLoaderDefine.EditEyeTextureID"},
    {key = "eyelashes", field = "EyelashStyle", catalog = "EyelashStyles", texture_type = "app.GUITextureLoaderDefine.EditEyelashesTextureID"},
    {key = "freckles", field = "FrecklesStyle", catalog = "FreckleStyles", texture_type = "app.GUITextureLoaderDefine.EditFrecklesTextureID"},
    {key = "scars", field = "ScarStyle", catalog = "ScarStyles", slots = "Scars", texture_type = "app.GUITextureLoaderDefine.EditScarTextureID"},
    {key = "tattoos", field = "TattooStyle", catalog = "TattooStyles", slots = "Tattoos", texture_type = "app.GUITextureLoaderDefine.EditTattooTextureID"},
    {key = "fur", field = "FurStyle", texture_type = "app.GUITextureLoaderDefine.EditFurStyleTextureID"},
    {key = "dirt", field = "System.Int32", catalog = "DirtStyles", path = {"_Dirt", "_DirtPattern"}, texture_type = "app.GUITextureLoaderDefine.EditDirtTextureID"},
  }
  local NPC_EDITOR_ENUM_CACHE = {}
  local function NpcEditorEnum(type_name)
    local cached = NPC_EDITOR_ENUM_CACHE[type_name]
    if cached then return cached.values, cached.names end
    local definition = assert(sdk.find_type_definition(type_name), "Missing native NPC editor enum: " .. type_name)
    local values, names = {}, {}
    for _, field in ipairs(definition:get_fields()) do
      if field:is_static() then
        local value, name = field:get_data(nil), field:get_name()
        values[name], names[value] = value, name
      end
    end
    NPC_EDITOR_ENUM_CACHE[type_name] = {values = values, names = names}
    return values, names
  end

  local NPC_EDITOR_COLOR_SOURCES = {
    Skin = {{"_Skin", "_Color"}}, Eyes = {}, Eyebrows = {{"_Eyebrows", "_Color"}},
    Eyeliner = {{"_Makeup", "_Eyeliner", "_Color"}}, Nose = {{"_Nose", "_Color"}, {"_Nose", "_Color2"}},
    Teeth = {{"_Teeth", "_Color"}}, TeethDirt = {{"_Teeth", "_DirtColor"}}, Freckles = {{"_Freckles", "_Color"}},
    Cheeks = {{"_Makeup", "_Cheek", "_Color"}}, FurPattern = {},
    FurFacePattern = {{"_FurFacePattern", "_Color1"}, {"_FurFacePattern", "_Color2"}},
    Lips = {{"_Makeup", "_Lips", "_Color1"}}, Claws = {{"_Claws", "_Color"}},
    Hair = {{"_Hair", "_RootColor"}, {"_Hair", "_TipColor"}, {"_Beard", "_RootColor"}, {"_Beard", "_TipColor"}, {"_BodyHair", "_Color"}},
    Eyeshadow = {{"_Makeup", "_Eyeshadow", "_Color1"}, {"_Makeup", "_Eyeshadow", "_Color2"}},
    Tattoos = {{"_Tattoos", "_Tattoos", "*", "_Color1"}, {"_Tattoos", "_Tattoos", "*", "_Color2"}, {"_Tattoos", "_Tattoos", "*", "_Color3"}},
    Dirt = {{"_Dirt", "_Color1"}, {"_Dirt", "_Color2"}}, Eyelashes = {{"_Eyelashes", "_RootColor"}, {"_Eyelashes", "_TipColor"}},
  }
  for _, eye in ipairs({"_Common", "_LeftEye", "_RightEye"}) do
    for index = 1, 4 do NPC_EDITOR_COLOR_SOURCES.Eyes[#NPC_EDITOR_COLOR_SOURCES.Eyes + 1] = {"_Eyes", eye, "_IrisColor" .. index} end
  end
  for index = 1, 4 do NPC_EDITOR_COLOR_SOURCES.FurPattern[index] = {"_FurPatterns", "_Color" .. index} end
  local INVALID_EDITOR_TEXTURE = -1
  local function NpcEditorContext()
    local controller = GuiManager and GuiManager._CharaEditCtrl
    if not controller or not utils.GetGameObject(controller) then return nil end
    local human = controller.Edit and controller.Edit.EditCtrl
    if not human or not utils.GetGameObject(human) then return controller end
    return controller, human
  end

  -- An NPC with a written look keeps its native record only as a stored original (ReadNpcAppearanceData form). This
  -- view answers the catalog's field reads the way the native record did; unavailable parts read as null references.
  local STORED_RECORD = {}
  local function StoredRecordView(raw)
    if type(raw) ~= "table" then return raw end
    if raw.unavailable then return nil end
    return setmetatable({raw = raw}, STORED_RECORD)
  end
  STORED_RECORD.__index = {
    get_field = function(self, name)
      local raw = self.raw
      if name == "rgba" then return raw.r | (raw.g << 8) | (raw.b << 16) | (raw.a << 24) end
      return StoredRecordView(raw.fields and raw.fields[name])
    end,
  }

  local function NpcEditorValues(appearance, path)
    local nodes, missing = {{value = appearance}}, 0
    for _, field in ipairs(path) do
      local next_nodes = {}
      for _, node in ipairs(nodes) do
        if field == "*" then
          local slots, count
          if getmetatable(node.value) == STORED_RECORD then
            slots, count = {}, node.value.raw.count
            for index = 1, count do slots[index] = StoredRecordView(node.value.raw.values[index]) end
          else
            slots, count = utils.GetLuaArray(node.value)
          end
          for index = 1, count do
            local slot = slots[index]
            if not slot then missing = missing + 1
            elseif slot:get_field("_Style") ~= NO_APPEARANCE_STYLE then next_nodes[#next_nodes + 1] = {value = slot, slot = index} end
          end
        else
          local value = node.value:get_field(field)
          if value == nil then missing = missing + 1
          else next_nodes[#next_nodes + 1] = {value = value, slot = node.slot} end
        end
      end
      nodes = next_nodes
    end
    return nodes, missing
  end

  local function ReadNpcEditorCatalog()
    local state = Transmogify.npc_editor
    local manager = sdk.get_managed_singleton("app.CharacterEditManager")
    local database = manager and manager._AppearanceDB
    if not database or database:get_Count() == 0 then return nil end
    if state.catalog and state.catalog.database_address == sdk.to_ptr(database) and state.catalog.character_count == database:get_Count() then
      return state.catalog
    end
    state.message = "Reading registered NPC styles and colors."
    local looks = Transmogify.GetNPCLookState()
    local species_names, gender_names = NpcEditorEnum("app.Species"), NpcEditorEnum("app.Gender")
    local licenses = NpcEditorEnum("app.charaedit.ch000.useredit.Define.SimpleColorLicense")
    local catalog = {database_address = sdk.to_ptr(database), character_count = database:get_Count(), variant_count = 0,
      supported_variants = 0, forms = {}, catalogs = {}, colors = {}, palettes = {}, appearances = {}, excluded = {}}
    local form_lookup, style_names, textures, palette_sets = {}, {}, {}, {}
    for name in pairs(NPC_EDITOR_COLOR_SOURCES) do palette_sets[name] = {} end
    for _, kind in ipairs(NPC_EDITOR_STYLES) do
      if not kind.path then local _, names = NpcEditorEnum("app." .. kind.field); style_names[kind.key] = names end
      textures[kind.key] = NpcEditorEnum(kind.texture_type)
    end
    for index, form in ipairs(NPC_EDITOR_FORMS) do
      local species = assert(species_names[form.species], "Missing native species: " .. form.species)
      local gender = assert(gender_names[form.gender], "Missing native gender: " .. form.gender)
      local row = {name = form.name, species = species, gender = gender}
      for _, kind in ipairs(NPC_EDITOR_STYLES) do row[kind.key] = {} end
      catalog.forms[index] = row
      form_lookup[tostring(species) .. ":" .. tostring(gender)] = row
    end
    for character_id, variants in pairs(utils.GetLuaDic(database)) do
      local appearances = {}
      if variants == utils.NATIVE_NULL then
        catalog.excluded[#catalog.excluded + 1] = {character_id = character_id, reason = "Missing appearance dictionary"}
      else
        appearances = utils.GetLuaDic(variants)
      end
      local written = looks and looks.written[tostring(character_id)]
      for appearance_id, appearance in pairs(appearances) do
        if appearance == utils.NATIVE_NULL then appearance = nil end
        local original = written and written.originals[tostring(appearance_id)]
        if original then appearance = StoredRecordView(original) end
        catalog.variant_count = catalog.variant_count + 1
        catalog.appearances[#catalog.appearances + 1] = {id = character_id, appearance_id = appearance_id}
        state.message = "Reading NPC " .. tostring(character_id) .. " / appearance " .. tostring(appearance_id) .. "."
        local species = appearance and appearance:get_field("_Species")
        local gender = appearance and appearance:get_field("_Gender")
        local form = form_lookup[tostring(species) .. ":" .. tostring(gender)]
        if not form then
          catalog.excluded[#catalog.excluded + 1] = {character_id = character_id, appearance_id = appearance_id,
            species = species, gender = gender, reason = appearance and "Unsupported race/form" or "Missing appearance data"}
        else
          catalog.supported_variants = catalog.supported_variants + 1
          for _, kind in ipairs(NPC_EDITOR_STYLES) do
            local paths = {}
            if kind.path then paths[1] = kind.path
            elseif kind.slots then paths[1] = {"_" .. kind.slots, "_" .. kind.slots, "*", "_Style"}
            else for _, field in ipairs(kind.fields or {kind.field}) do paths[#paths + 1] = {"_" .. field} end end
            for _, path in ipairs(paths) do
              local values, missing = NpcEditorValues(appearance, path)
              if missing > 0 then
                catalog.excluded[#catalog.excluded + 1] = {character_id = character_id, appearance_id = appearance_id,
                  field = table.concat(path, "."), reason = "Missing native style data"}
              end
              for _, value in ipairs(values) do
                local style = value.value
                local name = style_names[kind.key] and style_names[kind.key][style]
                if kind.path and type(style) == "number" and style % 1 == 0 and style >= 0 and style <= TYPE_LIMITS["System.Byte"][2] then name = "DirtPattern_" .. style end
                if name and name ~= "None" and name ~= "Invalid" and (style ~= NO_APPEARANCE_STYLE or kind.path) then
                  local entry = form[kind.key][style]
                  if not entry then entry = {style = style, name = name, sources = {}}; form[kind.key][style] = entry end
                  entry.sources[#entry.sources + 1] = {character_id = character_id, appearance_id = appearance_id,
                    field = table.concat(path, "."), slot = value.slot}
                elseif style ~= NO_APPEARANCE_STYLE or name ~= "None" then
                  catalog.excluded[#catalog.excluded + 1] = {character_id = character_id, appearance_id = appearance_id,
                    field = table.concat(path, "."), value = style, reason = "Unknown native style"}
                end
              end
            end
          end
          for palette, paths in pairs(NPC_EDITOR_COLOR_SOURCES) do
            for _, path in ipairs(paths) do
              local values, missing = NpcEditorValues(appearance, path)
              if missing > 0 then
                catalog.excluded[#catalog.excluded + 1] = {character_id = character_id, appearance_id = appearance_id,
                  field = table.concat(path, "."), reason = "Missing native color data"}
              end
              for _, value in ipairs(values) do palette_sets[palette][value.value:get_field("rgba") & 0xffffffff] = true end
            end
          end
        end
      end
    end
    for index, form in ipairs(catalog.forms) do
      local config = NPC_EDITOR_FORMS[index]
      for _, kind in ipairs(NPC_EDITOR_STYLES) do
        local field = config[kind.key]
        if field == nil then field = kind.catalog end
        local entries = {}
        for _, entry in pairs(form[kind.key]) do
          local texture_name = entry.name
          if kind.key == "heads" then texture_name = config.head_prefix .. entry.name
          elseif kind.key == "skins" then texture_name = "Skin_" .. config.prefix .. "_" .. entry.name
          elseif kind.key == "fur" then texture_name = "FurStyle_" .. config.prefix .. "_" .. entry.name:sub(10)
          elseif kind.key == "beards" then
            local suffix = entry.name:sub(7)
            local preferred = "Beard_" .. (config.species == "Human" and "HM" or "BM") .. "_" .. suffix
            local alternate = "Beard_" .. (config.species == "Human" and "BM" or "HM") .. "_" .. suffix
            texture_name = textures[kind.key][preferred] and preferred or alternate
          end
          entry.texture = textures[kind.key][texture_name] or INVALID_EDITOR_TEXTURE
          local separator = entry.name:find("_", 1, true)
          entry.pattern = separator and tonumber(entry.name:sub(separator + 1)) or 0
          table.sort(entry.sources, function(a, b)
            if a.character_id ~= b.character_id then return a.character_id < b.character_id end
            if a.appearance_id ~= b.appearance_id then return a.appearance_id < b.appearance_id end
            if a.field ~= b.field then return a.field < b.field end
            return (a.slot or 0) < (b.slot or 0)
          end)
          entries[#entries + 1] = entry
          if field then
            local target = catalog.catalogs[field]
            if not target then target = {key = kind.key, field = field, entries = {}}; catalog.catalogs[field] = target end
            local existing = target.entries[entry.style]
            if not existing then
              existing = {style = entry.style, name = entry.name, texture = entry.texture, pattern = entry.pattern, sources = {}}
              target.entries[entry.style] = existing
            end
            for _, source in ipairs(entry.sources) do existing.sources[#existing.sources + 1] = source end
          end
        end
        table.sort(entries, function(a, b) return a.name < b.name end)
        form[kind.key] = entries
      end
    end
    for _, target in pairs(catalog.catalogs) do
      local entries = {}
      for _, entry in pairs(target.entries) do entries[#entries + 1] = entry end
      table.sort(entries, function(a, b) return a.name < b.name end)
      target.entries = entries
    end
    local all_colors = {}
    for palette, values in pairs(palette_sets) do
      local colors = {}
      for color in pairs(values) do colors[#colors + 1] = color; all_colors[color] = true end
      table.sort(colors)
      catalog.palettes[#catalog.palettes + 1] = {name = palette, license = assert(licenses[palette], "Missing native color license: " .. palette), colors = colors}
    end
    table.sort(catalog.palettes, function(a, b) return a.license < b.license end)
    for color in pairs(all_colors) do catalog.colors[#catalog.colors + 1] = color end
    table.sort(catalog.colors)
    state.catalog = catalog
    return catalog
  end

  function Transmogify.FilterNpcAppearances()
    local picker = Transmogify.npc_appearance_picker
    local selected = picker.filtered[picker.selected_index]
    local search = string.lower(picker.search)
    picker.filtered, picker.labels, picker.selected_index = {}, {NPC_APPEARANCE_PROMPT}, 1
    for _, row in ipairs(picker.rows) do
      if search == "" or utils.StringFindRaw(row.search, search) then
        local index = #picker.labels + 1
        picker.filtered[index], picker.labels[index] = row, row.name
        if selected and selected.id == row.id and selected.appearance_id == row.appearance_id then picker.selected_index = index end
      end
    end
  end

  function Transmogify.UpdateNpcAppearancePicker()
    local picker = Transmogify.npc_appearance_picker
    local visible = picker.visible
    picker.visible = nil
    if not visible then return end
    local controller = NpcEditorContext()
    local catalog = Transmogify.npc_editor.catalog
    if not controller or Transmogify.npc_editor.status ~= "ready" or not catalog then return end
    if picker.source == catalog then return end
    if picker.retry_frames > 0 then
      picker.retry_frames = picker.retry_frames - 1
      return
    end
    picker.retry_frames = NPC_EDITOR_RETRY_FRAMES
    picker.source, picker.status, picker.message = catalog, "failed", "Reading NPC appearance data."
    local manager = sdk.get_managed_singleton("app.NPCManager")
    local database = manager and manager:get_IsDataSetup() and manager:get_CharacterDataDict()
    if not database or database:get_Count() == 0 then
      picker.source, picker.status, picker.message = nil, "waiting", "Waiting for NPC appearances."
      return
    end
    picker.message = "Reading NPC appearance names."
    local characters = utils.GetLuaDic(database)
    local appearances = {}
    for _, row in ipairs(catalog.appearances) do
      appearances[row.id] = appearances[row.id] or {}
      appearances[row.id][#appearances[row.id] + 1] = row.appearance_id
    end
    local rows = {}
    for id, ids in pairs(appearances) do
      local identity = utils.GetNpcCatalogIdentity(id, characters[id])
      if identity then
        local names, labels = identity.names, {}
        for _, variant in ipairs(identity.variants) do
          if variant.name ~= "" then labels[variant.appearance] = labels[variant.appearance] or variant.name end
        end
        table.sort(ids)
        local fallback = #names > 0 and table.concat(names, " / ") or "Unnamed NPC"
        for index, appearance_id in ipairs(ids) do
          local name = labels[appearance_id] or fallback
          if #ids > 1 and (#names < 2 or not labels[appearance_id]) then name = fallback .. " " .. index end
          rows[#rows + 1] = {id = id, appearance_id = appearance_id, name = name,
            search = string.lower(name .. " " .. fallback .. " " .. tostring(id))}
        end
      end
    end
    table.sort(rows, function(a, b)
      local left, right = string.lower(a.name), string.lower(b.name)
      if left ~= right then return left < right end
      if a.id ~= b.id then return a.id < b.id end
      return a.appearance_id < b.appearance_id
    end)
    local counts, positions = {}, {}
    for _, row in ipairs(rows) do
      local name = string.lower(row.name)
      counts[name] = (counts[name] or 0) + 1
    end
    for _, row in ipairs(rows) do
      local name = string.lower(row.name)
      if counts[name] > 1 then
        positions[name] = (positions[name] or 0) + 1
        row.name = row.name .. " (" .. positions[name] .. ")"
        row.search = row.search .. " " .. string.lower(row.name)
      end
    end
    picker.rows = rows
    Transmogify.FilterNpcAppearances()
    picker.status, picker.message = "ready", nil
  end

  local function AppendNpcEditorArray(original, extras, element_type, count)
    if #extras == 0 then return original, utils.GetLuaArray(original) end
    local extended = sdk.create_managed_array(element_type, count + #extras):add_ref()
    original:call("CopyTo(System.Array, System.Int32)", extended, 0)
    local setter = assert(extended:get_type_definition():get_method("Set"), "Native editor array setter is unavailable")
    for index, value in ipairs(extras) do setter:call(extended, count + index - 1, value) end
    local values, total = utils.GetLuaArray(extended)
    assert(total == count + #extras, "Native editor array has an unexpected size")
    return extended, values, total
  end

  local function ApplyNpcEditorSupport(human, accessor)
    local state = Transmogify.npc_editor
    if state.status == "failed" then return end
    state.status = "failed"
    local catalog = ReadNpcEditorCatalog()
    if not catalog then
      state.status, state.message = "waiting", "Features enabled; waiting for the game's NPC appearance registry."
      return
    end
    if human then
      if not state.human_state or state.human_state.address ~= sdk.to_ptr(human) then
        state.human_state = {address = sdk.to_ptr(human)}
        state.allowance_changes, state.color_changes = {}, nil
      end
      local applied = state.human_state
      applied.ready = false
      for _, kind in ipairs(NPC_EDITOR_STYLES) do
        if kind.database then
          local database = human:get_field(kind.database)
          if not database then
            state.status, state.message = "waiting", "Waiting for native editor style dictionaries."
            return
          end
          local previous = applied[kind.key]
          if not previous or previous.database ~= sdk.to_ptr(database) or previous.catalog ~= catalog then
            state.message = "Preparing NPC " .. kind.key .. " before native preview validation."
            local added = 0
            for _, form in ipairs(catalog.forms) do
              for _, entry in ipairs(form[kind.key]) do
                local result = AllowAppearanceStyle(human, kind.database, entry.style, form.species, form.gender)
                if result.added then added = added + 1 end
              end
            end
            applied[kind.key] = {database = sdk.to_ptr(database), catalog = catalog}
            state.allowance_changes[kind.key] = added
          end
        end
      end
      do
        local database = human:get_field("_LicenseColors")
        if not database then
          state.status, state.message = "waiting", "Waiting for native color palettes."
          return
        end
        applied.colors = applied.colors or {}
        state.color_changes = state.color_changes or {palettes = {}}
        for _, palette in ipairs(catalog.palettes) do
          if #palette.colors > 0 then
            local original = database:ContainsKey(palette.license) and database:get_Item(palette.license)
            if not original then
              state.status, state.message = "waiting", "Waiting for native color palette: " .. palette.name
              return
            end
            local previous = applied.colors[palette.license]
            if not previous or previous.array ~= sdk.to_ptr(original) or previous.catalog ~= catalog then
              state.message = "Adding exact NPC colors to " .. palette.name .. "."
              local present, extras, colors = {}, {}, {}
              local original_values, original_count = utils.GetLuaArray(original)
              for _, color in pairs(original_values) do present[color:get_field("rgba") & 0xffffffff] = true end
              for _, packed in ipairs(palette.colors) do
                if not present[packed] then
                  local color = ValueType.new(COLOR_TYPE)
                  color:set_field("rgba", packed)
                  extras[#extras + 1] = color
                  colors[#colors + 1] = packed
                  present[packed] = true
                end
              end
              local extended, extended_values, total = AppendNpcEditorArray(original, extras, COLOR_TYPE, original_count)
              for index, packed in ipairs(colors) do
                assert((extended_values[original_count + index]:get_field("rgba") & 0xffffffff) == packed,
                  "Native color palette did not retain an NPC color: " .. palette.name)
              end
              if extended ~= original then database:set_Item(palette.license, extended) end
              applied.colors[palette.license] = {array = sdk.to_ptr(extended), catalog = catalog}
              state.color_changes.palettes[palette.name] = {license = palette.license, original_count = original_count,
                added = #extras, colors = colors, total = total}
            end
          end
        end
      end
      applied.ready = true
    end
    if accessor then
      if not state.accessor_state or state.accessor_state.address ~= sdk.to_ptr(accessor) then
        state.accessor_state = {address = sdk.to_ptr(accessor)}
        state.catalog_changes = {}
      end
      state.accessor_state.ready = false
      for _, kind in ipairs(NPC_EDITOR_STYLES) do
        do
          local style_type = kind.path and kind.field or "app." .. kind.field
          local element_type = assert(sdk.find_type_definition("app.GUICharaEditData.PatternParam`2<" .. style_type .. "," .. kind.texture_type .. ">"),
            "Missing native catalog row type: " .. kind.key)
          for field, target in pairs(catalog.catalogs) do
            if target.key == kind.key then
              local original = accessor:call("get_" .. field)
              if not original then
                state.status, state.message = "waiting", "Waiting for native catalog: " .. field
                return
              end
              local previous = state.accessor_state[field]
              if not previous or previous.array ~= sdk.to_ptr(original) or previous.catalog ~= catalog then
                state.message = "Adding NPC choices to " .. field .. "."
                local original_values, original_count = utils.GetLuaArray(original)
                local present, extras, entries = {}, {}, {}
                for _, entry in pairs(original_values) do present[entry.Style] = true end
                for _, entry in ipairs(target.entries) do
                  if not present[entry.style] then
                    local extra = sdk.create_instance(element_type:get_full_name()):add_ref()
                    extra:call(".ctor()")
                    extra.Style, extra.TextureID = entry.style, entry.texture
                    extra.PatternNo = kind.key == "heads" and 0 or entry.pattern
                    extra.SequenceNo = original_count + #extras + 1
                    extras[#extras + 1] = extra
                    entries[#entries + 1] = {catalog_index = original_count + #extras - 1, style = entry.style,
                      name = entry.name, texture = entry.texture, sources = entry.sources}
                    present[entry.style] = true
                  end
                end
                local extended, extended_values, total = AppendNpcEditorArray(original, extras, element_type, original_count)
                for _, entry in ipairs(entries) do
                  assert(extended_values[entry.catalog_index + 1].Style == entry.style, "Native catalog did not retain NPC style: " .. entry.name)
                end
                if extended ~= original then accessor:call("set_" .. field, extended) end
                state.accessor_state[field] = {array = sdk.to_ptr(extended), catalog = catalog}
                state.catalog_changes[field] = {original_count = original_count, added = #extras,
                  total = total, entries = entries}
              end
            end
          end
        end
      end
      state.accessor_state.ready = true
    end
    state.status = state.human_state and state.human_state.ready and
      state.accessor_state and state.accessor_state.ready and "ready" or "waiting"
    state.message = "NPC appearance options: " .. catalog.supported_variants .. " variants, " .. #catalog.colors .. " exact colors."
    if state.status == "ready" and not state.logged then
      state.logged = true
      utils.Log("[Transmogify][NpcEditor] " .. state.message)
    end
  end

  local function ResetNpcEditorSession(controller)
    local state = Transmogify.npc_editor
    state.controller = controller and sdk.to_ptr(controller)
    state.catalog, state.human_state, state.accessor_state = nil, nil, nil
    state.catalog_changes, state.allowance_changes, state.color_changes = {}, {}, nil
    state.status, state.message, state.logged, state.retry_frames = "waiting", nil, nil, 0
  end

  function Transmogify.UpdateNpcEditorSupport()
    local state = Transmogify.npc_editor
    local controller, human = NpcEditorContext()
    if not controller then
      if state.controller then ResetNpcEditorSession(nil) end
      return
    end
    if state.controller ~= sdk.to_ptr(controller) then ResetNpcEditorSession(controller) end
    if state.status == "failed" or not human then return end
    local accessor = controller:get_field("_DataAccessor")
    if not accessor then return end
    if state.status == "ready" and state.human_state.address == sdk.to_ptr(human) and
      state.accessor_state.address == sdk.to_ptr(accessor) then return end
    if state.retry_frames > 0 then
      state.retry_frames = state.retry_frames - 1
      return
    end
    state.retry_frames = NPC_EDITOR_RETRY_FRAMES
    ApplyNpcEditorSupport(human, accessor)
  end

  for method, hook in pairs({setup = Transmogify.HOOKS.editorSetup, requestApply = Transmogify.HOOKS.editorRequestApply}) do
    sdk.hook(hook,
      function(args)
        local storage = thread.get_hook_storage()
        storage.transmogify_npc_editor_human = nil
        local controller, human = NpcEditorContext()
        if not human or sdk.to_ptr(human) ~= args[2] then return end
        if Transmogify.npc_editor.controller ~= sdk.to_ptr(controller) then ResetNpcEditorSession(controller) end
        if method == "setup" then
          storage.transmogify_npc_editor_human = human
        else
          ApplyNpcEditorSupport(human)
        end
      end,
      function(retval)
        local storage = thread.get_hook_storage()
        local previous = storage.transmogify_npc_editor_human
        storage.transmogify_npc_editor_human = nil
        if previous then
          local controller, human = NpcEditorContext()
          if human and sdk.to_ptr(human) == sdk.to_ptr(previous) and
            Transmogify.npc_editor.controller == sdk.to_ptr(controller) then
            Transmogify.npc_editor.human_state = nil
            ApplyNpcEditorSupport(human)
          end
        end
        return retval
      end)
  end
  sdk.hook(Transmogify.HOOKS.charaEditStart,
    function(args)
      local controller = sdk.to_managed_object(args[2])
      thread.get_hook_storage().transmogify_npc_editor_controller = controller
      ResetNpcEditorSession(controller)
    end,
    function(retval)
      local storage = thread.get_hook_storage()
      local previous = storage.transmogify_npc_editor_controller
      storage.transmogify_npc_editor_controller = nil
      local controller, human = NpcEditorContext()
      if previous and controller and sdk.to_ptr(controller) == sdk.to_ptr(previous) then
        ApplyNpcEditorSupport(human, controller:get_field("_DataAccessor"))
      end
      return retval
    end)
  sdk.hook(Transmogify.HOOKS.charaEditUiSetup,
    function(args)
      local controller, human = NpcEditorContext()
      if controller and sdk.to_ptr(controller) == args[3] then
        if Transmogify.npc_editor.controller ~= sdk.to_ptr(controller) then ResetNpcEditorSession(controller) end
        ApplyNpcEditorSupport(human, controller:get_field("_DataAccessor"))
      end
    end,
    function(retval) return retval end)

  local NPC_APPEARANCE_PREFIX = "app.charaedit.ch000."
  local NPC_DETAIL_BASE = "app.BodyDetailBase`3<"
  local NPC_APPEARANCE_RUNTIME_FIELDS = {
    _IsSlotNoChanged = true, _PrevSlotCount = true, _ProcDistIndex = true, _StartSlotNo = true,
  }
  local NPC_DETAIL_SCALE = 0.009999999776482582
  local NPC_SCALED_TYPES = {["System.Byte"] = true, ["System.SByte"] = true, ["System.UInt16"] = true}

  -- The Enabled byte at 0x20 is declared on the generic BodyDetailBase`3 parent. Scar and tattoo SlotData derive from
  -- BodyDetailRoot directly and hold _Opacity there instead.
  local function IsDetailBase(definition)
    local name = definition and definition:get_full_name()
    return name ~= nil and name:sub(1, #NPC_DETAIL_BASE) == NPC_DETAIL_BASE
  end

  local function ReadNpcAppearanceData(value, typeName)
    if value == nil or value == utils.NATIVE_NULL then return {type = typeName, unavailable = true} end
    if type(value) == "number" or type(value) == "boolean" or type(value) == "string" then return value end
    if typeName == "via.Color" then
      local packed = value:get_field("rgba")
      return {r = packed & 0xff, g = (packed >> 8) & 0xff, b = (packed >> 16) & 0xff, a = (packed >> 24) & 0xff}
    end
    if typeName:sub(-2) == "[]" then
      local elements, count = utils.GetLuaArray(value)
      local result = {type = typeName, count = count, values = {}}
      for index = 1, result.count do
        result.values[index] = ReadNpcAppearanceData(elements[index], typeName:sub(1, -3))
      end
      return result
    end
    if typeName:sub(1, #NPC_APPEARANCE_PREFIX) ~= NPC_APPEARANCE_PREFIX and
      typeName ~= "app.CharacterEditDefine.EditValueData" and typeName ~= "app.CharacterEditDefine.PretenderData" then
      return {type = typeName, unavailable = true, reason = "Unsupported NPC appearance source type"}
    end
    local result = {type = typeName, fields = {}}
    local definition = assert(sdk.find_type_definition(typeName), "Missing NPC appearance type: " .. typeName)
    while definition do
      for _, field in ipairs(definition:get_fields()) do
        local name = field:get_name()
        if not field:is_static() and name:sub(1, 1) == "_" and not NPC_APPEARANCE_RUNTIME_FIELDS[name] then
          result.fields[name] = ReadNpcAppearanceData(value:get_field(name), field:get_type():get_full_name())
        end
      end
      definition = definition:get_parent_type()
      if not definition or definition:get_full_name():sub(1, #NPC_APPEARANCE_PREFIX) ~= NPC_APPEARANCE_PREFIX then break end
    end
    if IsDetailBase(definition) then result.enabled = value:read_byte(DETAIL_ENABLED_OFFSET) ~= 0 end
    return result
  end

  local NPC_DEFAULT_CACHE = {}
  local NPC_DEFAULT_TYPES = {Eyelash = "EyelashBase", EyeshadowBase = "EyeshadowBase", EyeshadowCommon = "EyeshadowBase",
    LipBase = "Lips", LipCommon = "Lips"}
  local NPC_SLOTS_PER_REGION = 2
  local MAX_SINGLE = 3.402823466e38

  local function ReportNpcNormalization(request, path, original, replacement, reason)
    local before = type(original) == "table" and "table" or tostring(original)
    local after = type(replacement) == "table" and "table" or tostring(replacement)
    local npc = request.npc_source
    utils.Log("[NpcAppearance] warning: " .. npc.name .. " [" .. npc.character_id .. ":" .. npc.appearance_id .. "] " ..
      path .. ": " .. reason .. "; " .. before .. " -> " .. after)
  end

  local function NpcDefaultValue(type_name, name, value_type, species)
    if type_name == POSTURE_TYPE then return 0.0 end
    if name == "Enabled" then return false end
    local source_type
    if type_name == SCAR_SLOT_TYPE or type_name == TATTOO_SLOT_TYPE then
      source_type = type_name .. ".InitVal"
    else
      local part = type_name:sub(#DETAIL_TYPE + 2, -8)
      if part == "Eyes" or part == "EyeBase" then
        local species_names = utils.GetEnumDic("app.Species")
        source_type = "app.charaedit.ch000.EyeBase.InitVal." .. (species == species_names.Beastman and "Beastman" or "Human")
        if name == "LeftEyeState" or name == "RightEyeState" then name = "EyeState" end
        if name == "LeftEyeSquintRate" or name == "RightEyeSquintRate" then name = "EyeSquintRate" end
      else
        source_type = "app.charaedit.ch000." .. (NPC_DEFAULT_TYPES[part] or part) .. ".InitVal"
      end
      if name == "WrinkeStrength" then name = "WrinkleStrength" end
    end
    local key = source_type .. "." .. name
    local cached = NPC_DEFAULT_CACHE[key]
    if cached ~= nil then return cached end
    local definition = assert(sdk.find_type_definition(source_type), "Missing native appearance defaults: " .. source_type)
    local field = assert(definition:get_field(name), "Missing native appearance default: " .. key)
    local value = field:get_data(nil)
    assert(value ~= nil, "Unavailable native appearance default: " .. key)
    if value_type == "via.Color" then
      local packed = value:get_field("rgba")
      value = {r = packed & 0xff, g = (packed >> 8) & 0xff, b = (packed >> 16) & 0xff, a = (packed >> 24) & 0xff}
    elseif value_type == "System.UInt16" then
      value = value & 0xffff
    elseif value_type:sub(1, 7) ~= "System." then
      value = value & 0xffffffff
    end
    NPC_DEFAULT_CACHE[key] = value
    return value
  end

  local function NormalizeNpcNumber(request, path, value, value_type, fallback, minimum, maximum, quiet)
    local original, reason = value
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
      value, reason = fallback, "Invalid or missing value; native default"
    end
    if value_type:sub(1, 7) ~= "System." then
      local values = ENUM_CACHE[value_type]
      if not values then
        values = {}
        local definition = assert(sdk.find_type_definition(value_type), "Missing appearance enum: " .. value_type)
        for _, field in ipairs(definition:get_fields()) do
          if field:is_static() then values[field:get_data(nil)] = true end
        end
        ENUM_CACHE[value_type] = values
      end
      if value % 1 ~= 0 or not values[value] then value, reason = fallback, "Unknown appearance enum; native default" end
    else
      local limits = TYPE_LIMITS[value_type]
      minimum = minimum or limits and limits[1] or -MAX_SINGLE
      maximum = maximum or limits and limits[2] or MAX_SINGLE
      if value_type ~= "System.Single" and value % 1 ~= 0 then value, reason = math.floor(value), "Fractional integer; rounded down" end
      local bounded = math.max(minimum, math.min(maximum, value))
      if bounded ~= value then value, reason = bounded, "Number out of range; clamped to native limits" end
    end
    if reason and not quiet then ReportNpcNormalization(request, path, original, value, reason) end
    return value
  end

  -- Locates a preset schema entry in a record read by ReadNpcAppearanceData. A nil key means the entry is stored on
  -- the record object itself.
  local function NpcRecordLocation(source, type_name, name)
    local key = "_" .. name
    if type_name == DETAIL_TYPE then
      if name == "FurPattern" then key = "_FurPatterns" end
      if MAKEUP_FIELDS[name] then return source.fields._Makeup, key end
    elseif type_name == DETAIL_TYPE .. ".EyesContext" then
      if name == "Left" or name == "Right" then key = "_" .. name .. "Eye" end
    elseif SELF_FIELDS[type_name] == name then
      return source, nil
    end
    if name == "SlotDatas" then key = type_name == DETAIL_TYPE .. ".TattoosContext" and "_Tattoos" or "_Scars" end
    return source, key
  end

  local function NpcFieldType(type_name, key)
    local definition = assert(sdk.find_type_definition(type_name), "Missing NPC source type: " .. type_name)
    local field = definition:get_field(key)
    while not field and definition:get_parent_type() do
      definition = definition:get_parent_type()
      field = definition:get_field(key)
    end
    return assert(field, "Missing NPC source field: " .. type_name .. "." .. key):get_type():get_full_name()
  end

  -- Returns the native shape template's input defaults by hash string and each input's visit position by hash;
  -- a parent input is always visited before its children.
  local function ReadEditTemplate(group, species, gender)
    local manager = sdk.get_managed_singleton("app.CharacterEditManager")
    local sections
    if group == "face" then sections = manager:call("getFaceEditSections(app.Species)", species)
    else sections = manager:call("getBodyEditGroup(app.Gender)", gender) end
    assert(sections, "Missing native NPC shape template: " .. group)
    local defaults, order, nodes, position = {}, {}, {}, 0
    local section_values, section_count = utils.GetLuaArray(sections)
    for index = 1, section_count do
      if section_values[index] then nodes[#nodes + 1] = section_values[index] end
    end
    while #nodes > 0 do
      local node = table.remove(nodes)
      local children
      if node:get_type_definition():get_full_name() == "app.CharacterEditDefine.Input.Section" then
        local inputs = node:get_Inputs()
        if inputs then
          local values, count = utils.GetLuaArray(inputs)
          for index = 1, count do
            if values[index] then nodes[#nodes + 1] = values[index] end
          end
        end
        children = node:get_SubSections()
      else
        local hash = node:get_Hash()
        position = position + 1
        defaults[tostring(hash)], order[hash] = node:get_Value(), position
        children = node:get_Children()
      end
      if children then
        local values, count = utils.GetLuaArray(children)
        for index = 1, count do
          if values[index] then nodes[#nodes + 1] = values[index] end
        end
      end
    end
    return defaults, order
  end

  local function ConvertNpcAppearanceObject(source, type_name, request, path, quiet)
    if type(source) ~= "table" or type(source.fields) ~= "table" then
      if not quiet then ReportNpcNormalization(request, path, source, "native defaults", "Invalid or missing appearance group") end
      source, quiet = {fields = {}}, true
    end
    local result = {}
    for _, entry in ipairs(PresetFields(type_name)) do
      local object, key = NpcRecordLocation(source, type_name, entry.name)
      local value = not key and source or nil
      if type(object) == "table" and type(object.fields) == "table" then
        local used = request.source_fields[object]
        if not used then used = {path = path, keys = {}}; request.source_fields[object] = used end
        if value == nil then
          used.keys[key] = true
          value = object.fields[key]
        end
        if entry.name == "Enabled" and value == nil then value = object.enabled end
      end
      local field_path = path .. "." .. entry.name
      if entry.type_name:sub(-2) == "[]" then
        local array = {}
        if type(value) == "table" and type(value.values) == "table" then
          for index, item in ipairs(value.values) do
            array[index] = ConvertNpcAppearanceObject(item, entry.type_name:sub(1, -3), request, field_path .. "." .. index, quiet)
          end
          if value.count ~= #array then ReportNpcNormalization(request, field_path, value.count, #array, "Array count differs from readable entries") end
        elseif not quiet then
          ReportNpcNormalization(request, field_path, value, 0, "Invalid or missing cosmetic list; empty list")
        end
        value = array
      elseif entry.type_name == "via.Color" then
        local fallback = NpcDefaultValue(type_name, entry.name, entry.type_name, request.preset.species)
        local color = {}
        for _, channel in ipairs({"r", "g", "b", "a"}) do
          color[channel] = NormalizeNpcNumber(request, field_path .. "." .. channel,
            type(value) == "table" and value[channel] or nil, "System.Byte", fallback[channel], nil, nil, quiet)
        end
        value = color
      elseif entry.type_name == "System.Boolean" then
        if type(value) ~= "boolean" then
          local fallback = NpcDefaultValue(type_name, entry.name, entry.type_name, request.preset.species)
          if not quiet then ReportNpcNormalization(request, field_path, value, fallback, "Invalid or missing boolean; native default") end
          value = fallback
        end
      elseif entry.type_name == "System.Single" or TYPE_LIMITS[entry.type_name] or
        sdk.find_type_definition(entry.type_name):get_field("value__") then
        if entry.type_name == "System.Single" and type(value) == "number" and object and object.type then
          if NPC_SCALED_TYPES[NpcFieldType(object.type, key)] then value = value * NPC_DETAIL_SCALE end
        end
        local fallback = NpcDefaultValue(type_name, entry.name, entry.type_name, request.preset.species)
        value = NormalizeNpcNumber(request, field_path, value, entry.type_name, fallback, nil, nil, quiet)
      else
        value = ConvertNpcAppearanceObject(value, entry.type_name, request, field_path, quiet)
      end
      result[entry.name] = value
    end
    if type_name == DETAIL_TYPE .. ".EyesContext" then result.Common.Enabled = true end
    return result
  end

  local function PrepareNpcAppearance(request, context, current)
    local preset, raw = request.preset, request.npc_raw
    local source = raw.fields
    request.source_fields = {[raw] = {path = "source", keys = {_AppearanceID = true, _Species = true, _Gender = true,
      _BodyEdit = true, _FaceEdit = true, _Pretender = true, _Makeup = true}}}
    preset.details = ConvertNpcAppearanceObject(raw, DETAIL_TYPE, request, "details")
    preset.posture = ConvertNpcAppearanceObject(source._Pretender, POSTURE_TYPE, request, "posture")
    preset.styles, preset.face, preset.body = {}, {}, {}
    local metadata_type = context.swapper._Meta:get_type_definition()
    local base_head
    for _, field in ipairs(STYLE_FIELDS) do
      request.source_fields[raw].keys["_" .. field] = true
      local value_type = metadata_type:get_field("_" .. field):get_type():get_full_name()
      local values = {}
      for _, member in ipairs(sdk.find_type_definition(value_type):get_fields()) do
        if member:is_static() then values[member:get_data(nil)] = true end
      end
      ENUM_CACHE[value_type] = values
      local value = source["_" .. field]
      if type(value) ~= "number" or not values[value] then
        local fallback = NO_APPEARANCE_STYLE
        if not values[fallback] then
          base_head = base_head or assert(context.human:getBaseheadPreset(0), "Native base-head defaults are unavailable")
          local native_field = field == "FurPattern" and "FurPatternStyle" or field
          fallback = base_head:get_field("_" .. native_field)
          assert(values[fallback], "Native base-head fallback is invalid: " .. field)
        end
        ReportNpcNormalization(request, "styles." .. field, value, fallback, "Unknown or missing style; native fallback")
        value = fallback
      end
      preset.styles[field] = value
    end
    for _, group in ipairs({"face", "body"}) do
      local data = source[group == "face" and "_FaceEdit" or "_BodyEdit"]
      local inputs = type(data) == "table" and data.values
      local supplied = {}
      if type(inputs) ~= "table" then
        ReportNpcNormalization(request, group, data, "native defaults", "Missing shape inputs")
        inputs = {}
      end
      for index, input in ipairs(inputs) do
        local fields = type(input) == "table" and input.fields
        if type(fields) == "table" and type(fields._EditKeyHash) == "number" then
          request.source_fields[input] = {path = group .. "." .. index, keys = {_EditKeyHash = true, _Value = true}}
          local key = tostring(fields._EditKeyHash)
          if supplied[key] ~= nil then ReportNpcNormalization(request, group .. "." .. key, supplied[key], fields._Value, "Duplicate input; last value retained") end
          supplied[key] = fields._Value
        else
          ReportNpcNormalization(request, group .. "." .. index, input, "omitted", "Invalid shape-input record")
        end
      end
      local defaults = ReadEditTemplate(group, preset.species, preset.gender)
      local values = utils.GetLuaDic(group == "face" and context.editor:getFaceEditValue() or context.editor:getBodyEditValue())
      for key in pairs(current[group]) do
        local input = values[tonumber(key)]
        assert(input and input ~= utils.NATIVE_NULL, "Missing native appearance input: " .. key)
        local fallback = assert(defaults[key], "Missing native NPC input default: " .. group .. "." .. key)
        preset[group][key] = NormalizeNpcNumber(request, group .. "." .. key, supplied[key], "System.Single", fallback,
          input:get_MinValue(), input:get_MaxValue())
      end
      for key, value in pairs(supplied) do
        if current[group][key] == nil then ReportNpcNormalization(request, group .. "." .. key, value, "omitted", "Input is not supported by the target editor") end
      end
    end
    for _, group in ipairs({"Scars", "Tattoos"}) do
      local path = "details." .. group .. ".SlotDatas"
      local source_slots, target_slots = preset.details[group].SlotDatas, current.details[group].SlotDatas
      local count = #target_slots
      assert(count > 0 and count % NPC_SLOTS_PER_REGION == 0, "Unsupported native cosmetic slot layout: " .. group)
      local slots, occupied, region_changes = {}, {}, 0
      local slot_type = group == "Scars" and SCAR_SLOT_TYPE or TATTOO_SLOT_TYPE
      for index = 1, count do
        slots[index] = ConvertNpcAppearanceObject(nil, slot_type, request, path .. "." .. index, true)
        slots[index].Region = math.floor((index - 1) / NPC_SLOTS_PER_REGION)
      end
      for index, item in ipairs(source_slots) do
        if item.Style ~= NO_APPEARANCE_STYLE then
          local target
          for candidate = 1, count do
            if not occupied[candidate] and slots[candidate].Region == item.Region then target = candidate; break end
          end
          if target then
            slots[target], occupied[target] = item, true
            if target ~= index then ReportNpcNormalization(request, path .. "." .. index, index, target, "Moved cosmetic entry to its editor region") end
          else
            ReportNpcNormalization(request, path .. "." .. index, item, "omitted", "No remaining editor slot for this region")
          end
        end
      end
      for index = 1, count do
        local item = source_slots[index]
        if not occupied[index] and item and item.Style == NO_APPEARANCE_STYLE then
          local region = slots[index].Region
          if item.Region ~= region then region_changes = region_changes + 1 end
          item.Region, slots[index] = region, item
        end
      end
      if #source_slots ~= count then
        ReportNpcNormalization(request, path, #source_slots, count, "Mapped cosmetic list to editor slots; missing slots are native empty values")
      elseif region_changes > 0 then
        ReportNpcNormalization(request, path .. ".Region", region_changes, 0, "Assigned native regions to empty editor slots")
      end
      preset.details[group].SlotDatas = slots
    end
    for object, used in pairs(request.source_fields) do
      for key, value in pairs(object.fields) do
        if not used.keys[key] then ReportNpcNormalization(request, used.path .. "." .. key, value, "omitted", "Unknown source field") end
      end
    end
    request.source_fields, request.npc_raw = nil, nil
    request.npc_prepared = true
  end

  function Transmogify.UpdateAppearancePresets()
    local state = Transmogify.appearance_presets
    local request = state.pending or state.request
    if not request then return end
    local pending = state.pending ~= nil
    state.request, state.pending = nil, nil
    state.status, state.message = "failed", "Checking the appearance preview."
    state.error = nil
    if request.action ~= ACTION_SAVE and request.action ~= ACTION_LOAD and request.action ~= ACTION_NPC then
      UpdateAppearanceFiles(request)
      return
    end
    local context, rebuilding = AppearanceContext(request)
    if rebuilding then
      state.pending = request
      state.status, state.message = "waiting", "Waiting for the new race/form preview components."
      return
    end
    if not context or request.phase ~= BASE_PHASE and request.editor_address and (sdk.to_ptr(context.editor) ~= request.editor_address or
      sdk.to_ptr(context.object) ~= request.object_address or sdk.to_ptr(context.controller) ~= request.controller_address) then
      state.pending, state.status = nil, "unavailable"
      state.message = "Open the barber or creator hub / Detailed Customization and let its preview settle."
      return
    end
    local ready = context.object:get_DrawSelf() and context.human._ApplyFlag == 0 and not context.swapper:get_PartBeingSwapping()
    if pending then
      request.frames = request.frames + 1
      if not ready or request.frames < READBACK_UPDATES then
        state.pending = request
        state.status, state.message = "waiting", "Appearance submitted; waiting for the native preview rebuild."
        return
      end
      if request.phase == BASE_PHASE then
        assert(context.human:get_Species() == request.preset.species and context.human:get_Gender() == request.preset.gender and
          context.swapper._Meta._Species == request.preset.species and context.swapper._Meta._Gender == request.preset.gender,
          "Native base change did not reach the preset's race/form")
        state.message = "Refreshing the rebuilt appearance editor."
        context.editor:resetAllPresetNo()
        context.editor:collectParam(true)
        context.editor:updateTemp()
        context.editor:clearHistory()
        context.editor:addHistory("Race/form: " .. request.preset.name, false, false, nil)
        if context.editor.UpdateParamEvent then context.editor.UpdateParamEvent:Invoke() end
        request.phase = nil
        utils.Log("Appearance base change ready: " .. request.path)
      else
        state.pending, state.status = nil, "failed"
        state.message = "Checking the loaded appearance."
        local actual = CaptureAppearance(context, request.preset.name)
        local differences = {}
        AppearanceDifferences(actual, request.preset, "preset", differences)
        context.editor:collectParam(true)
        context.editor:addHistory("Preset: " .. request.preset.name, false, false, nil)
        context.editor:updateTemp()
        if context.editor.UpdateParamEvent then context.editor.UpdateParamEvent:Invoke() end
        state.status = #differences == 0 and "complete" or "mismatch"
        state.message = #differences == 0 and "Loaded preview matches the preset. Inspect the character's appearance." or
          "Preview load finished with " .. #differences .. " differing values; see the REFramework log."
        if request.npc_source and Transmogify.window.tab == Transmogify.CHARACTER_TAB then state.npc_name = request.npc_source.name end
        local differing = {}
        for _, difference in ipairs(differences) do
          differing[#differing + 1] = difference.path .. (difference.reason and " (" .. difference.reason .. ")" or
            ": expected " .. tostring(difference.expected) .. ", got " .. tostring(difference.actual))
        end
        utils.Log("Appearance preset load: " .. request.preset.name .. "; source=" .. request.path .. "; " .. state.message ..
          (#differing > 0 and " Differences: " .. table.concat(differing, "; ") or ""))
        return
      end
    end
    if not ready then
      state.status, state.message = "unavailable", "Wait for the appearance preview to finish rebuilding."
      return
    end
    local npc_load = request.action == ACTION_NPC or request.npc_source ~= nil
    local name = npc_load and request.name or PresetName(request.name)
    if not name then
      state.status, state.message = "unavailable", "Use a preset name of 1-80 characters without Windows filename symbols."
      return
    end
    local existing
    if not npc_load then
      Transmogify.RefreshAppearancePresets()
      for _, candidate in ipairs(state.files) do
        if candidate:lower() == name:lower() then existing = candidate; break end
      end
      if request.action == ACTION_LOAD and not existing and not request.preset then
        state.status, state.message = "unavailable", "Preset file no longer exists. Refresh the list."
        return
      end
      name = existing or name
    end
    local path = request.path or PRESET_PATH .. name .. ".json"
    state.status, state.message = "failed", "Reading the current appearance."
    local current = CaptureAppearance(context, name)
    if request.action == ACTION_SAVE then
      if request.overwrite and not existing then
        state.status, state.message = "unavailable", "The selected preset no longer exists. Refresh the list."
        return
      end
      if not request.overwrite and (existing or AppearanceFileExists(name)) then
        state.status, state.message = "unavailable", "A preset with that name already exists."
        return
      end
      assert(json.dump_file(path, current, 2), "Could not save appearance preset: " .. path)
      RecheckNpcAppearances(name)
      Transmogify.RefreshAppearancePresets()
      if Transmogify.window.tab == Transmogify.CHARACTER_TAB then
        ResetNpcAppearanceSelection()
        for index, candidate in ipairs(state.files) do if candidate == name then state.selected = index end end
      end
      state.name, state.last_file = "", path
      state.status, state.message = "complete", "Saved preset: " .. name
      utils.Log("Appearance preset save: " .. path)
      return
    end
    if request.action == ACTION_NPC then
      state.message = "Reading the selected NPC's appearance."
      local manager = sdk.get_managed_singleton("app.CharacterEditManager")
      local database = manager and manager._AppearanceDB
      local records = database and utils.GetLuaDic(database)[request.npc_id]
      if records == utils.NATIVE_NULL then records = nil end
      local appearance_id = request.npc_appearance_id
      request.npc_source = {character_id = request.npc_id, appearance_id = appearance_id, name = name}
      if not records or appearance_id == nil or not records:ContainsKey(appearance_id) then
        state.status, state.message = "unavailable", "Selected NPC appearance is unavailable. Reopen the editor and select an available appearance."
        utils.Log("[NpcAppearance] " .. state.message .. " NPC=" .. tostring(request.npc_id) .. "; appearance=" .. tostring(appearance_id))
        return
      end
      local appearance = utils.GetLuaDic(records)[appearance_id]
      if not appearance or appearance == utils.NATIVE_NULL then
        state.status, state.message = "unavailable", "Selected NPC appearance has no native data."
        utils.Log("[NpcAppearance] " .. state.message .. " NPC=" .. tostring(request.npc_id) .. "; appearance=" .. tostring(appearance_id))
        return
      end
      -- An NPC with an assigned look copies its stored original record, not the look written over it. JSON storage
      -- drops empty tables, so the stored form regains its empty lists and field sets first.
      local looks = Transmogify.GetNPCLookState()
      local written = looks and looks.written[tostring(request.npc_id)]
      local original = written and written.originals[tostring(appearance_id)]
      if original then
        local pending = {original}
        while #pending > 0 do
          local raw = table.remove(pending)
          if raw.count ~= nil and raw.values == nil then raw.values = {} end
          if raw.type ~= nil and raw.count == nil and not raw.unavailable and raw.fields == nil then raw.fields = {} end
          for _, child in pairs(raw.values or raw.fields or {}) do
            if type(child) == "table" then pending[#pending + 1] = child end
          end
        end
      end
      request.npc_raw = original or ReadNpcAppearanceData(appearance, appearance:get_type_definition():get_full_name())
      local source = request.npc_raw.fields
      request.preset = {format = PRESET_FORMAT, version = PRESET_VERSION, name = name,
        species = source._Species, gender = source._Gender}
      path = "NPC " .. request.npc_id .. " / appearance " .. appearance_id
      request.path, request.action = path, ACTION_LOAD
    end
    assert(request.action == ACTION_LOAD, "Unknown appearance preset action")
    state.message = "Validating preset: " .. name
    local preset = request.preset or assert(json.load_file(path), "Could not read appearance preset: " .. path)
    assert(preset.format == PRESET_FORMAT and preset.version == PRESET_VERSION, "Unsupported appearance preset format/version")
    if not request.npc_source then assert(PresetName(preset.name), "Invalid preset display name") end
    if request.npc_source then
      local species_names, gender_names = utils.GetEnumDic("app.Species"), utils.GetEnumDic("app.Gender")
      if (preset.species ~= species_names.Human and preset.species ~= species_names.Beastman) or
        (preset.gender ~= gender_names.Female and preset.gender ~= gender_names.Male) then
        state.status, state.message = "unavailable", "Unsupported NPC race/form; preview left unchanged."
        utils.Log("[NpcAppearance] " .. name .. ": " .. state.message)
        return
      end
    end
    CheckAppearanceNumber(preset.species, "app.Species", "species")
    CheckAppearanceNumber(preset.gender, "app.Gender", "gender")
    local change_base = preset.species ~= current.species or preset.gender ~= current.gender
    if request.npc_source and not change_base and not request.npc_prepared then PrepareNpcAppearance(request, context, current) end
    local details, posture, writes
    if not request.npc_source or not change_base then
      for field, value in pairs(current) do
        if field ~= "face" and field ~= "body" then CheckAppearanceData(preset[field], value, "preset." .. field) end
      end
      for field in pairs(preset) do assert(current[field] ~= nil, "Unexpected preset field: " .. tostring(field)) end
      for _, group in ipairs({"face", "body"}) do
        if not change_base then
          CheckAppearanceData(preset[group], current[group], "preset." .. group)
        else
          assert(type(preset[group]) == "table" and (request.npc_source or next(preset[group]) ~= nil), "Missing shape inputs: " .. group)
          for key, value in pairs(preset[group]) do
            assert(type(key) == "string" and tostring(tonumber(key)) == key, "Invalid shape input key: " .. tostring(key))
            CheckAppearanceNumber(tonumber(key), group == "face" and "app.FaceEditID" or "app.BodyEditID", group .. "." .. key)
            CheckAppearanceNumber(value, "System.Single", group .. "." .. key)
          end
        end
      end
      local metadata_type = context.swapper._Meta:get_type_definition()
      for _, field in ipairs(STYLE_FIELDS) do
        CheckAppearanceNumber(preset.styles[field], metadata_type:get_field("_" .. field):get_type():get_full_name(), "styles." .. field)
      end
      local native_editor = NativeAppearanceView(context.editor:get_address(), context.editor:get_type_definition())
      details = native_editor:get_field("TempEdit")
      posture = native_editor:get_field("TempPret")
      writes = {}
      PrepareAppearanceWrites(preset.details, DETAIL_TYPE, details, context.detail, writes)
      PrepareAppearanceWrites(preset.posture, POSTURE_TYPE, posture, context.body._PretenderData, writes)
    end
    if change_base then
      assert(not request.base_change, "Preview race/form changed during preset loading")
      local base_index
      for index = 0, BASE_BODY_COUNT - 1 do
        local base = context.human:getBaseBodyPreset(index)
        if base and base._Species == preset.species and base._Gender == preset.gender then base_index = index; break end
      end
      assert(base_index ~= nil, "No native base body matches this preset's race/form")
      assert(preset.species == current.species or not context.swapper._Meta:get_IsSpeciesLocked(), "Preview race is natively locked")
      assert(preset.gender == current.gender or not context.swapper._Meta:get_IsGenderLocked(), "Preview form is natively locked")
      request.preset, request.path, request.frames = preset, path, 0
      request.human_address = sdk.to_ptr(context.human)
      request.phase = BASE_PHASE
      request.base_change = {species = current.species, gender = current.gender,
        target_species = preset.species, target_gender = preset.gender, base_index = base_index}
      state.message = "Switching the preview to the preset's race/form: " .. name
      context.human:call("setBaseBody(System.Int32, System.Boolean)", base_index, true)
      state.pending, state.last_file = request, path
      state.status, state.message = "waiting", "Race/form submitted; waiting for the native preview rebuild."
      utils.Log("Appearance base change submitted: " .. path .. "; base=" .. base_index)
      return
    end
    for _, group in ipairs({"face", "body"}) do
      local values = utils.GetLuaDic(group == "face" and context.editor:getFaceEditValue() or context.editor:getBodyEditValue())
      for key, value in pairs(preset[group]) do
        local input = values[tonumber(key)]
        assert(input and input ~= utils.NATIVE_NULL, "Missing native appearance input: " .. key)
        assert(value >= input:get_MinValue() and value <= input:get_MaxValue(), "Shape input out of range: " .. group .. "." .. key)
      end
    end
    state.message = "Preparing the native appearance working copy: " .. name
    for _, write in ipairs(writes) do
      if write.byte_offset then
        write.object:write_byte(write.byte_offset, write.value and 1 or 0)
      else
        write.object:set_field(write.field, write.value)
      end
    end
    local preparation_differences = {}
    AppearanceDifferences(ReadAppearanceObject(details, DETAIL_TYPE), preset.details, "details", preparation_differences)
    AppearanceDifferences(ReadAppearanceObject(posture, POSTURE_TYPE), preset.posture, "posture", preparation_differences)
    if #preparation_differences > 0 then
      context.editor:updateTemp()
      error("Appearance working copy did not retain " .. #preparation_differences .. " requested values")
    end
    for _, entry in ipairs({{"HeadStyle", "_HeadLimitDB"}, {"HairStyle", "_HairLimitDB"}}) do
      AllowAppearanceStyle(context.human, entry[2], preset.styles[entry[1]], preset.species, preset.gender)
    end
    state.message = "Applying preset to the preview: " .. name
    for _, group in ipairs({"face", "body"}) do
      local id_type = group == "face" and "app.FaceEditID" or "app.BodyEditID"
      for key, value in pairs(preset[group]) do context[group]:call("setEditValue(" .. id_type .. ", System.Single, System.Boolean)", tonumber(key), value + 0.0, true) end
    end
    context.body._PretenderData:call("copyFrom(" .. POSTURE_TYPE .. ")", sdk.to_ptr(posture:get_address()))
    for _, field in ipairs(STYLE_FIELDS) do context.swapper._Meta:set_field("_" .. field, preset.styles[field]) end
    sdk.call_native_func(sdk.to_ptr(details:get_address()), details:get_type_definition(), "copyTo(app.BodyDetailEditor)", context.detail)
    context.editor:resetAllPresetNo()
    context.editor:collectParam(true)
    context.editor:copyContext()
    request.human_address = sdk.to_ptr(context.human)
    request.editor_address, request.object_address, request.controller_address = sdk.to_ptr(context.editor), sdk.to_ptr(context.object), sdk.to_ptr(context.controller)
    request.preset, request.path, request.frames = preset, path, 0
    state.pending, state.last_file = request, path
    state.status, state.message = "waiting", "Appearance submitted; waiting for the native preview rebuild."
    utils.Log("Appearance preset submitted: " .. path)
  end

  -- NPC looks: an assigned appearance preset is written into every _AppearanceDB record of the NPC. A build reads
  -- those records, so NPCs spawned later show the look; a loaded NPC respawns once the game allows it. The records
  -- and the resident storage both last until the game restarts, so the stored originals always match them.
  local MANAGED_FIELDS_OFFSET = 0x10
  local APPEARANCE_DATA_TYPE = "app.charaedit.ch000.AppearanceData"
  local EDIT_VALUE_TYPE = "app.CharacterEditDefine.EditValueData"
  local NPC_LOOK = {
    INTERVAL = 30, DOCUMENT_PREFIX = "Transmogify.NpcLook.", ENTRY_KEY = "look", INDEX_KEY = "npc_look_written",
    PENDING_KEY = "npc_look_pending", HOLDER = "getNPCHolder(app.CharacterID)", REGENERATE = "updateCharacterData_Regenerate(app.CharacterID)",
    PAINTING_CAP = 20, MATERIAL_BAKE_PREBAKE = 3, NO_SHARED_SLOT = 0xFF, ARISEN_ID = "ch000000_00", REQUEST_RETRY_PASSES = 20,
  }
  -- marked/none_hashes/holders are read by the painting hooks. holders lists the marked NPCs holding a painting group
  -- at the last tick and painted counts them; granted counts NPCs the slot hook painted since then.
  Transmogify.npc_looks = {countdown = 0, checked = {}, labels = {}, marked = {}, none_hashes = {}, holders = {}, painted = 0,
    granted = 0, backup = {}, requested = {}}

  -- REFramework assigns a ValueType with its boxed size, header included, and so writes 0x10 bytes past a color
  -- or embedded struct. Value-type data is written one scalar at a time at its native address instead.
  local WriteNpcAppearanceData
  local function WriteNpcAppearanceFields(object, address, definition, raw)
    local value_type = definition:is_value_type()
    local fields = raw.fields or {}
    while definition do
      for _, field in ipairs(definition:get_fields()) do
        local name = field:get_name()
        local value = fields[name]
        if not field:is_static() and value ~= nil and not (type(value) == "table" and value.unavailable) then
          local field_type = field:get_type()
          if type(value) ~= "table" then
            sdk.set_native_field(object or sdk.to_ptr(address), definition, name, value)
          elseif field_type:is_value_type() then
            local offset = field:get_offset_from_fieldptr()
            if not value_type then
              assert(field:get_offset_from_base() == MANAGED_FIELDS_OFFSET + offset, "Unexpected NPC appearance field layout: " .. name)
              offset = MANAGED_FIELDS_OFFSET + offset
            end
            if field_type:get_full_name() == "via.Color" then
              sdk.set_native_field(sdk.to_ptr(address + offset), COLOR_TYPE, "rgba",
                value.r | (value.g << 8) | (value.b << 16) | (value.a << 24))
            else
              WriteNpcAppearanceFields(nil, address + offset, field_type, value)
            end
          else
            local replacement = WriteNpcAppearanceData(object:get_field(name), value, field_type:get_full_name())
            if replacement then object:set_field(name, replacement) end
          end
        end
      end
      definition = definition:get_parent_type()
      if not definition or definition:get_full_name():sub(1, #NPC_APPEARANCE_PREFIX) ~= NPC_APPEARANCE_PREFIX then break end
    end
    if raw.enabled ~= nil then
      assert(object and IsDetailBase(definition), "NPC appearance Enabled flag outside a detail component")
      object:write_byte(DETAIL_ENABLED_OFFSET, raw.enabled and 1 or 0)
    end
  end

  -- Writes ReadNpcAppearanceData output into an existing reference-type part in place. An array of another size is
  -- replaced by a new array, which is returned for the caller to assign. Struct elements are built as ValueTypes and
  -- stored with the array's own Set, which copies exactly one element; missing object elements are constructed.
  WriteNpcAppearanceData = function(target, raw, typeName)
    if raw.unavailable then return nil end
    assert(target ~= nil and target ~= utils.NATIVE_NULL, "Missing NPC appearance target: " .. typeName)
    if typeName:sub(-2) ~= "[]" then
      local definition = assert(sdk.find_type_definition(typeName), "Missing NPC appearance type: " .. typeName)
      WriteNpcAppearanceFields(target, target:get_address(), definition, raw)
      return nil
    end
    local element_type = typeName:sub(1, -3)
    local element_definition = sdk.find_type_definition(element_type)
    local elements, count = utils.GetLuaArray(target)
    local resized = count ~= raw.count
    if resized then
      target = sdk.create_managed_array(element_definition, raw.count):add_ref()
      elements = {}
    end
    local setter = target:get_type_definition():get_method("Set")
    for index = 1, raw.count do
      local value = raw.values[index]
      if element_definition:is_value_type() then
        if not value.unavailable then
          local element = ValueType.new(element_definition)
          WriteNpcAppearanceFields(nil, element:address(), element_definition, value)
          setter:call(target, index - 1, element)
        end
      else
        if not elements[index] and not value.unavailable then
          elements[index] = sdk.create_instance(element_type):add_ref()
          elements[index]:call(".ctor()")
          setter:call(target, index - 1, elements[index])
        end
        WriteNpcAppearanceData(elements[index], value, element_type)
      end
    end
    return resized and target or nil
  end

  local function NpcRecordValue(value, record_type, key, preset_type)
    if preset_type == "via.Color" then return {r = value.r, g = value.g, b = value.b, a = value.a} end
    if type(value) == "boolean" then return value end
    assert(type(value) == "number", "Invalid preset value: " .. record_type .. "." .. key)
    local storage_type = NpcFieldType(record_type, key)
    if preset_type == "System.Single" and NPC_SCALED_TYPES[storage_type] then value = value / NPC_DETAIL_SCALE end
    if storage_type == "System.Single" then return value + 0.0 end
    return math.tointeger(math.floor(value + 0.5))
  end

  local function ApplyPresetToNpcObject(target, values, type_name)
    for _, entry in ipairs(PresetFields(type_name)) do
      local value = values[entry.name]
      if value ~= nil then
        local object, key = NpcRecordLocation(target, type_name, entry.name)
        assert(type(object) == "table" and type(object.fields) == "table", "NPC record lacks preset part: " .. type_name .. "." .. entry.name)
        if not key then
          ApplyPresetToNpcObject(object, value, entry.type_name)
        elseif entry.name == "Enabled" and object.fields._Enabled == nil then
          assert(object.enabled ~= nil, "NPC record lacks preset flag: " .. type_name .. ".Enabled")
          object.enabled = value
        elseif entry.type_name:sub(-2) == "[]" then
          local element_type = entry.type_name:sub(1, -3)
          local slots = {type = entry.type_name, count = #value, values = {}}
          for index, slot in ipairs(value) do
            local fields = {}
            for _, slot_entry in ipairs(PresetFields(element_type)) do
              local slot_key = "_" .. slot_entry.name
              if slot[slot_entry.name] ~= nil then fields[slot_key] = NpcRecordValue(slot[slot_entry.name], element_type, slot_key, slot_entry.type_name) end
            end
            slots.values[index] = {type = element_type, fields = fields}
          end
          object.fields[key] = slots
        elseif entry.type_name == "via.Color" or type(value) ~= "table" then
          object.fields[key] = NpcRecordValue(value, object.type, key, entry.type_name)
        else
          ApplyPresetToNpcObject(object.fields[key], value, entry.type_name)
        end
      end
    end
  end

  -- Writes a saved preset into an NPC appearance record read by ReadNpcAppearanceData, reversing the NPC import's
  -- mapping and units. Values the preset does not define keep the record's own; shape inputs become exactly the preset's.
  local function ApplyAppearancePreset(raw, preset)
    local fields = raw.fields
    fields._Species, fields._Gender = preset.species, preset.gender
    for _, name in ipairs(STYLE_FIELDS) do
      if preset.styles[name] ~= nil then fields["_" .. name] = preset.styles[name] end
    end
    for _, group in ipairs({"face", "body"}) do
      if type(preset[group]) == "table" then
        local _, order = ReadEditTemplate(group, preset.species, preset.gender)
        local keys = {}
        for key in pairs(preset[group]) do keys[#keys + 1] = assert(math.tointeger(tonumber(key)), "Invalid preset input: " .. key) end
        -- The record restore sets inputs in array order and a parent's change shifts its children, so parents go first.
        table.sort(keys, function(a, b)
          local left, right = order[a] or math.huge, order[b] or math.huge
          if left ~= right then return left < right end
          return a < b
        end)
        local inputs = {type = EDIT_VALUE_TYPE .. "[]", count = #keys, values = {}}
        for index, key in ipairs(keys) do
          inputs.values[index] = {type = EDIT_VALUE_TYPE, fields = {_EditKeyHash = key,
            _Value = NpcRecordValue(preset[group][tostring(key)], EDIT_VALUE_TYPE, "_Value", "System.Single")}}
        end
        fields[group == "face" and "_FaceEdit" or "_BodyEdit"] = inputs
      end
    end
    if type(preset.posture) == "table" then ApplyPresetToNpcObject(fields._Pretender, preset.posture, POSTURE_TYPE) end
    if type(preset.details) == "table" then ApplyPresetToNpcObject(raw, preset.details, DETAIL_TYPE) end
    return raw
  end

  -- The resident storage encodes empty tables as JSON null; stored records are compared and written in that form.
  local function JsonForm(value)
    return json.load_string(json.dump_string(value, -1))
  end

  local function NpcLookRecords(database, id)
    local records = database[id]
    if not records or records == utils.NATIVE_NULL then return nil end
    local looks = {}
    for appearance_id, data in pairs(utils.GetLuaDic(records)) do
      if data ~= utils.NATIVE_NULL then looks[appearance_id] = data end
    end
    return next(looks) and looks or nil
  end

  -- Every NPC with a written look is marked for runtime painting, and the prebake keys of its appearance records are
  -- made to miss, so a marked NPC without a painting group stays in None instead of showing its original prebake.
  -- A prebake key is utils.MurmurHash of "<CharacterID name>_<appearance ID>"; "ch300595_0" is Romule's look 0.
  local function RefreshNpcLookMarks(state)
    local _, id_names = NpcEditorEnum("app.CharacterID")
    local marked, hashes = {}, {}
    for key, entry in pairs(state.written) do
      local id = math.tointeger(tonumber(key))
      marked[id] = true
      for appearance_key in pairs(entry.originals) do
        if id_names[id] then hashes[utils.MurmurHash(id_names[id] .. "_" .. appearance_key)] = true end
      end
    end
    state.marked, state.none_hashes = marked, hashes
  end

  -- Each NPC's originals live in their own resident document, so a save re-encodes only that NPC; the main store
  -- indexes which NPCs have one. Returns the time spent in ms.
  local function SaveNpcLook(state, key)
    local started = utils.Seconds()
    RefreshNpcLookMarks(state)
    assert(Transmogify.SetNativeData(NPC_LOOK.ENTRY_KEY, state.written[key], NPC_LOOK.DOCUMENT_PREFIX .. key),
      "NPC look storage is unavailable")
    local index = {}
    for written_key in pairs(state.written) do index[written_key] = true end
    assert(Transmogify.SetNativeData(NPC_LOOK.INDEX_KEY, index), "Native storage is unavailable")
    return (utils.Seconds() - started) * 1000
  end

  local function SavePendingRespawns(state)
    assert(Transmogify.SetNativeData(NPC_LOOK.PENDING_KEY, state.pending), "Native storage is unavailable")
  end

  local function NpcLookLabel(state, manager, id, key)
    if state.labels[key] then return state.labels[key] end
    local data = manager:call("getNPCCharacterData(app.CharacterID)", id)
    local name = data and data:get_Name()
    state.labels[key] = (name and name ~= "" and name or "NPC") .. " [" .. key .. "]"
    return state.labels[key]
  end

  local function MarkNpcRespawn(state, manager, id, key)
    local holder = manager:call(NPC_LOOK.HOLDER, id)
    local character = holder and holder:isFlagEntity() and holder:get_chara()
    if not character then return end
    local address = character:get_address()
    -- A respawn already requested for this character rebuilds it from the records just written.
    if state.pending[key] ~= address then state.requested[key] = nil end
    state.pending[key] = address
    SavePendingRespawns(state)
  end

  -- Returns the outcome, or false when the native shape templates are not ready yet, so the NPC is tried again on a
  -- later update.
  local function WriteNpcLook(state, manager, database, id, key, name, preset, fingerprint)
    local editor = sdk.get_managed_singleton("app.CharacterEditManager")
    if not editor:call("getFaceEditSections(app.Species)", preset.species) or
      not editor:call("getBodyEditGroup(app.Gender)", preset.gender) then
      return false
    end
    local records = NpcLookRecords(database, id)
    if not records then
      utils.Log("[NpcLook] " .. NpcLookLabel(state, manager, id, key) .. ": has no appearance records; " .. name .. " was not applied.")
      return "skipped"
    end
    local started, save_ms = utils.Seconds(), 0
    local entry = state.written[key]
    if not entry then
      entry = {preset = name, originals = {}}
      for appearance_id, data in pairs(records) do
        entry.originals[tostring(appearance_id)] = JsonForm(ReadNpcAppearanceData(data, APPEARANCE_DATA_TYPE))
      end
      state.written[key] = entry
      save_ms = save_ms + SaveNpcLook(state, key)
    end
    local differences = {}
    for appearance_id, data in pairs(records) do
      local original = entry.originals[tostring(appearance_id)]
      if original then
        local look = JsonForm(ApplyAppearancePreset(JsonForm(original), preset))
        WriteNpcAppearanceData(data, look, APPEARANCE_DATA_TYPE)
        AppearanceDifferences(JsonForm(ReadNpcAppearanceData(data, APPEARANCE_DATA_TYPE)), look,
          "appearance " .. appearance_id, differences)
      end
    end
    entry.preset, entry.fingerprint = name, fingerprint
    save_ms = save_ms + SaveNpcLook(state, key)
    MarkNpcRespawn(state, manager, id, key)
    local label = NpcLookLabel(state, manager, id, key)
    utils.Log(string.format("[NpcLook] %s: wrote %s in %.1f ms (%.1f ms saving)%s", label, name,
      (utils.Seconds() - started) * 1000, save_ms, state.pending[key] and "; respawn pending." or "."))
    if #differences > 0 then
      utils.Log(string.format("[NpcLook] %s: %d written value(s) were not retained (first: %s).", label, #differences,
        differences[1].path))
    end
    return "written"
  end

  local function RestoreNpcLook(state, manager, database, id, key, entry)
    local started = utils.Seconds()
    local records = NpcLookRecords(database, id) or {}
    for appearance_key, original in pairs(entry.originals) do
      local data = records[math.tointeger(tonumber(appearance_key))]
      if data then WriteNpcAppearanceData(data, original, APPEARANCE_DATA_TYPE) end
    end
    state.written[key] = nil
    local save_ms = SaveNpcLook(state, key)
    MarkNpcRespawn(state, manager, id, key)
    utils.Log(string.format("[NpcLook] %s: restored the original look in %.1f ms (%.1f ms saving)%s",
      NpcLookLabel(state, manager, id, key), (utils.Seconds() - started) * 1000, save_ms,
      state.pending[key] and "; respawn pending." or "."))
    return "restored"
  end

  -- A missing or unsupported preset file counts as no look while the assignment itself is kept. Returns the outcome,
  -- or false to try the NPC again on a later update.
  local function ReconcileNpcLook(state, manager, database, key)
    local id = assert(math.tointeger(tonumber(key)), "Invalid NPC look CharacterID: " .. tostring(key))
    local name = CURRENT_SETTINGS.npcAppearances[key]
    local preset, fingerprint
    if name then
      preset = json.load_file(PRESET_PATH .. name .. ".json")
      -- An unknown race or gender never gets a native shape template, so it is unsupported rather than not ready.
      local _, species_names = NpcEditorEnum("app.Species")
      local _, gender_names = NpcEditorEnum("app.Gender")
      if type(preset) == "table" and preset.format == PRESET_FORMAT and preset.version == PRESET_VERSION and
        species_names[preset.species] and gender_names[preset.gender] and gender_names[preset.gender] ~= "None" and
        type(preset.styles) == "table" then
        local text = json.dump_string(preset, -1)
        fingerprint = 2166136261
        for index = 1, #text do fingerprint = ((fingerprint ~ text:byte(index)) * 16777619) & 0xFFFFFFFF end
      else
        preset = nil
        utils.Log("[NpcLook] " .. NpcLookLabel(state, manager, id, key) .. ": appearance preset " .. name ..
          " is missing or unsupported; the original look stays.")
      end
    end
    local entry = state.written[key]
    if not preset then
      if entry then return RestoreNpcLook(state, manager, database, id, key, entry) end
      return "unsupported"
    end
    if entry and entry.fingerprint == fingerprint then
      if entry.preset ~= name then
        entry.preset = name
        SaveNpcLook(state, key)
      end
      return "unchanged"
    end
    return WriteNpcLook(state, manager, database, id, key, name, preset, fingerprint)
  end

  -- A pending NPC still shows the character built before its records changed. Another character, or none, means
  -- the game rebuilt it from the current records. The mark stays until then, because a requested respawn leaves the
  -- old character in the world while it fades out.
  local function UpdateNpcRespawns(state, manager)
    if not next(state.pending) or not utils.GetPlayer() or GuiManager:isPausedGUI() then return end
    local changed = false
    for key, address in pairs(state.pending) do
      local id = assert(math.tointeger(tonumber(key)), "Invalid NPC look CharacterID: " .. tostring(key))
      local holder = manager:call(NPC_LOOK.HOLDER, id)
      local character = holder and holder:isFlagEntity() and holder:get_chara()
      -- The fading character is never building, so a building one at the same address is the new build.
      local request = state.requested[key]
      if not character or character:get_address() ~= address or (request and character:get_IsBuilding()) then
        state.pending[key], changed = nil, true
        if not request then
          utils.Log("[NpcLook] " .. NpcLookLabel(state, manager, id, key) ..
            (character and ": rebuilt by the game; no respawn needed." or ": unloaded; it spawns with the current look."))
        end
        state.requested[key] = nil
      elseif not character:get_IsBuilding() and holder:isCanDestroyEntity() then
        -- A request the game dropped is repeated once, after about 10 seconds of play; passes skip paused time.
        if not request then
          manager:call(NPC_LOOK.REGENERATE, id)
          state.requested[key] = {passes = 0}
          utils.Log("[NpcLook] " .. NpcLookLabel(state, manager, id, key) .. ": respawning.")
        elseif not request.retried then
          request.passes = request.passes + 1
          if request.passes > NPC_LOOK.REQUEST_RETRY_PASSES then
            manager:call(NPC_LOOK.REGENERATE, id)
            request.retried = true
            utils.Log("[NpcLook] " .. NpcLookLabel(state, manager, id, key) .. ": respawn requested again.")
          end
        end
      end
    end
    if changed then SavePendingRespawns(state) end
  end

  -- Returns the marked NPCs whose world character or cutscene copy is the top owner of a painting group, and their
  -- count. The cap counts NPCs, so a painted NPC's rebuild or copy is never refused.
  local function CountNpcLookPainting(state, editor)
    local holders, count = {}, 0
    local slots, slot_count = utils.GetLuaArray(editor._SharedTableSlots)
    for index = 1, slot_count do
      local slot = slots[index]
      local owner = slot and not slot:isEmpty() and slot:getTopOwner()
      local character = owner and utils.GetObjectComponent(owner, "app.Character")
      local id = character and character:get_CharaID()
      if id and state.marked[id] and not holders[id] then holders[id], count = true, count + 1 end
    end
    return holders, count
  end

  -- A marked NPC built with its prebake missed the painting hooks; it respawns once per session to pick them up.
  local function CheckNpcLookPainting(state, manager)
    for key in pairs(state.written) do
      local id = math.tointeger(tonumber(key))
      local holder = not state.pending[key] and not state.backup[key] and manager:call(NPC_LOOK.HOLDER, id)
      local character = holder and holder:isFlagEntity() and holder:get_chara()
      local swapper = character and not character:get_IsBuilding() and character:get_HumanPartSwapper()
      local detail = swapper and swapper:get_BodyDetailEditor()
      if detail and detail:call("get_MaterialBake") == NPC_LOOK.MATERIAL_BAKE_PREBAKE then
        state.backup[key] = true
        MarkNpcRespawn(state, manager, id, key)
        utils.Log("[NpcLook] " .. NpcLookLabel(state, manager, id, key) .. ": built with its original painting; respawn pending.")
      end
    end
  end

  -- Returns the NPC look state loaded from the resident store, or nil while it is unavailable. Readers of NPC
  -- records use it for the stored originals, including right after Reset Scripts.
  function Transmogify.GetNPCLookState()
    local state = Transmogify.npc_looks
    local main = Transmogify.GetNativeStorage()
    if not main then return nil end
    if main ~= state.main then
      local written = {}
      for key in pairs(Transmogify.GetNativeData(NPC_LOOK.INDEX_KEY) or {}) do
        written[key] = Transmogify.GetNativeData(NPC_LOOK.ENTRY_KEY, NPC_LOOK.DOCUMENT_PREFIX .. key)
      end
      local pending = Transmogify.GetNativeData(NPC_LOOK.PENDING_KEY) or {}
      state.main, state.checked, state.written, state.pending = main, {}, written, pending
      state.round = {keys = {}, count = 0, ms = 0, written = 0, restored = 0, unchanged = 0, unsupported = 0, skipped = 0}
      RefreshNpcLookMarks(state)
    end
    return state
  end

  function Transmogify.UpdateNPCLooks()
    local state = Transmogify.npc_looks
    state.countdown = state.countdown - 1
    if state.countdown > 0 then return end
    state.countdown = NPC_LOOK.INTERVAL
    local manager = sdk.get_managed_singleton("app.NPCManager")
    local editor = sdk.get_managed_singleton("app.CharacterEditManager")
    if not manager or not manager:get_IsDataSetup() or not editor or not editor._AppearanceDB then return end
    if not Transmogify.GetNPCLookState() then return end
    local database, waiting
    local round = state.round
    for _, assignments in ipairs({CURRENT_SETTINGS.npcAppearances, state.written}) do
      for key in pairs(assignments) do
        if not state.checked[key] then
          -- Marked first, so a failing NPC reports once instead of on every update.
          state.checked[key] = true
          database = database or utils.GetLuaDic(editor._AppearanceDB)
          local started = utils.Seconds()
          local outcome = ReconcileNpcLook(state, manager, database, key)
          if not outcome then
            state.checked[key], waiting = nil, true
          elseif round and not round.keys[key] then
            round.keys[key] = true
            round[outcome], round.count = round[outcome] + 1, round.count + 1
            round.ms = round.ms + (utils.Seconds() - started) * 1000
          end
        end
      end
    end
    -- One summary per game start or Reset Scripts, once every NPC of that round has been checked.
    if round and not waiting then
      state.round = nil
      if round.count > 0 then
        utils.Log(string.format("[NpcLook] Checked %d NPC look(s) in %.1f ms: %d written, %d restored, %d unchanged, " ..
          "%d unsupported%s.", round.count, round.ms, round.written, round.restored, round.unchanged, round.unsupported,
          round.skipped > 0 and (", " .. round.skipped .. " without appearance records") or ""))
      end
    end
    if next(state.marked) then
      state.holders, state.painted = CountNpcLookPainting(state, editor)
      state.granted = 0
      if utils.GetPlayer() and not GuiManager:isPausedGUI() then CheckNpcLookPainting(state, manager) end
    end
    UpdateNpcRespawns(state, manager)
  end

  -- A marked NPC's slot decision is asked with the Arisen's CharacterID, so the game's own allocator gives it a
  -- painting group and its record restore selects runtime painting. Below the cap only; the cap reserves nothing.
  sdk.hook(Transmogify.HOOKS.makeSharedTableSlotNo,
    function(args)
      local state = Transmogify.npc_looks
      local id = sdk.to_int64(args[3]) & 0xFFFFFFFF
      if not state.marked[id] then return end
      if not state.holders[id] and state.painted + state.granted >= NPC_LOOK.PAINTING_CAP then
        if not state.cap_logged then
          state.cap_logged = true
          utils.Log("[NpcLook] Painting cap of " .. NPC_LOOK.PAINTING_CAP .. " reached; further NPCs with looks use None painting.")
        end
        return
      end
      state.arisen_id = state.arisen_id or sdk.find_type_definition("app.CharacterID"):get_field(NPC_LOOK.ARISEN_ID):get_data(nil)
      args[3] = sdk.to_ptr(state.arisen_id)
      thread.get_hook_storage().npc_look_painting = id
    end,
    function(retval)
      local storage = thread.get_hook_storage()
      local id = storage.npc_look_painting
      storage.npc_look_painting = nil
      local state = Transmogify.npc_looks
      if id and not state.holders[id] and (sdk.to_int64(retval) & 0xFF) ~= NPC_LOOK.NO_SHARED_SLOT then
        state.holders[id], state.granted = true, state.granted + 1
      end
      return retval
    end)

  -- A marked NPC reaches the prebake check only without a painting group; missing its keys keeps it in None.
  sdk.hook(Transmogify.HOOKS.isRegisteredPreBake,
    function(args)
      thread.get_hook_storage().npc_look_prebake = sdk.to_int64(args[3]) & 0xFFFFFFFF
    end,
    function(retval)
      local storage = thread.get_hook_storage()
      local hash = storage.npc_look_prebake
      storage.npc_look_prebake = nil
      if hash and Transmogify.npc_looks.none_hashes[hash] then return sdk.to_ptr(0) end
      return retval
    end)

  function Transmogify.DrawCharacterTab()
    local state = Transmogify.appearance_presets
    if not state.listed then Transmogify.RefreshAppearancePresets() end
    local busy = Transmogify.IsAppearanceBusy()
    local controller = GuiManager and GuiManager._CharaEditCtrl
    local active = controller and utils.GetGameObject(controller) ~= nil
    imgui.text("Character Editor")
    if active then
      local subject = controller:get_IsPlayer() and "Arisen" or "Main Pawn"
      utils.TextColored("Editing: " .. subject, COLOR_INFO)
    else
      imgui.set_next_item_width(160)
      local changed, target = imgui.combo("##appearance_target", Transmogify.barber_target_index, Transmogify.BARBER_TARGETS)
      if changed then Transmogify.barber_target_index = target end
      imgui.same_line()
      local facility = sdk.get_managed_singleton("app.FacilityManager")
      local opening = facility and facility:get_IsExecuteCharaEdit()
      imgui.begin_disabled(busy or opening == true or Transmogify.barber_open_request ~= nil)
      if imgui.button("Open Character Editor") then
        local is_player = Transmogify.barber_target_index == 1
        local character
        if is_player then character = utils.GetPlayer() else character = utils.GetMainPawn() end
        Transmogify.barber_open_request = {is_player = is_player, character_address = character and sdk.to_ptr(character)}
      end
      imgui.end_disabled()
    end
    if Transmogify.barber_open_message then utils.TextColored(Transmogify.barber_open_message, COLOR_INFO) end
    imgui.begin_disabled(busy)
    local changed, hide = imgui.checkbox("Hide weapons in the editor", CURRENT_SETTINGS.hide_weapons_in_barber)
    if changed then
      CURRENT_SETTINGS.hide_weapons_in_barber = hide
      Transmogify.SettingsChanged(true)
    end
    imgui.end_disabled()
    if not active then
      utils.TextColored("Open the Character Editor to copy NPC looks and use appearance presets.", COLOR_INFO)
    end
    imgui.separator()
    imgui.text("Copy NPC Appearance")
    local picker = Transmogify.npc_appearance_picker
    picker.visible = true
    local npc_ready = picker.status == "ready" and picker.source == Transmogify.npc_editor.catalog and
      Transmogify.npc_editor.status == "ready"
    imgui.begin_disabled(busy or not active or state.operation ~= nil or not npc_ready)
    imgui.set_next_item_width(150)
    local search_changed, search = imgui.input_text("Search##npc_appearance_search", picker.search)
    if search_changed then
      picker.search = search
      Transmogify.FilterNpcAppearances()
    end
    imgui.same_line()
    imgui.set_next_item_width(300)
    local npc_changed, npc_index = imgui.combo("##npc_appearance_selection", picker.selected_index, picker.labels)
    if npc_changed then
      picker.selected_index = npc_index
      state.error, state.status, state.message = nil, nil, nil
      if picker.filtered[npc_index] then Transmogify.QueueAppearanceOperation(ACTION_NPC) end
    end
    imgui.end_disabled()
    utils.TextColored("Loads the NPC's look into the editor preview.", COLOR_INFO)
    utils.TextColored("Save it as an appearance preset to keep it.", COLOR_INFO)
    if active and not npc_ready and picker.status ~= "failed" and Transmogify.npc_editor.status ~= "failed" then
      utils.TextColored("Loading NPC appearances...", COLOR_INFO)
    end
    imgui.separator()
    busy = Transmogify.IsAppearanceBusy()
    local labels = {"Select appearance preset"}
    for _, name in ipairs(state.files) do labels[#labels + 1] = name end
    imgui.begin_disabled(busy or not active or state.operation ~= nil)
    imgui.text("Appearance preset")
    imgui.set_next_item_width(300)
    local changed, selected = imgui.combo("##appearance_selection", state.selected + 1, labels)
    if changed then
      state.selected, state.error, state.status, state.message = selected - 1, nil, nil, nil
      if state.files[state.selected] then Transmogify.QueueAppearanceOperation(ACTION_LOAD) end
    end
    imgui.end_disabled()
    busy = Transmogify.IsAppearanceBusy()
    imgui.begin_disabled(busy or not active or state.operation ~= nil)
    for index, entry in ipairs(ACTIONS) do
      if index > 1 then imgui.same_line() end
      imgui.begin_disabled(entry[1] ~= ACTION_NEW and not state.files[state.selected])
      if imgui.button(entry[2] .. "##appearance_action") then
        state.operation, state.error, state.status, state.message = entry[1], nil, nil, nil
        state.name = entry[1] == ACTION_NEW and (state.npc_name or "") or state.files[state.selected]
        if entry[1] == ACTION_DUPLICATE then state.name = state.name .. " copy" end
      end
      imgui.end_disabled()
    end
    imgui.same_line()
    imgui.begin_disabled(not state.files[state.selected])
    if imgui.button("Update##appearance") then state.operation, state.error, state.status, state.message = ACTION_UPDATE, nil, nil, nil end
    imgui.end_disabled()
    imgui.end_disabled()
    imgui.begin_disabled(busy or not active or state.operation ~= nil)
    if imgui.button("Refresh List##appearance") then Transmogify.QueueAppearanceOperation(ACTION_REFRESH) end
    imgui.end_disabled()
    imgui.same_line()
    imgui.begin_disabled(busy or state.operation ~= nil)
    if imgui.button("Open Folder##appearance") then Transmogify.QueueAppearanceOperation(ACTION_OPEN_FOLDER) end
    imgui.end_disabled()
    imgui.text("Files: reframework/data/" .. PRESET_PATH)
    if state.operation then
      imgui.separator()
      local operation = state.operation
      imgui.begin_disabled(busy or not active)
      if operation == ACTION_UPDATE or operation == ACTION_DELETE then
        if operation == ACTION_DELETE then
          imgui.text("Delete selected preset?")
          imgui.text(state.files[state.selected])
        else
          imgui.text("Replace '" .. state.files[state.selected] .. "' with the current appearance?")
        end
        utils.TextColored(operation == ACTION_DELETE and "Permanently delete this preset file." or "Save the current preview over this file.", COLOR_INFO)
      else
        imgui.text("Preset name")
        imgui.set_next_item_width(-1)
        local nameChanged, name = imgui.input_text("##appearance_name", state.name)
        state.name = name
        if nameChanged then state.error = nil end
      end
      if imgui.button("Confirm##appearance_operation") then Transmogify.QueueAppearanceOperation(operation, state.name) end
      imgui.end_disabled()
      imgui.same_line()
      imgui.begin_disabled(busy)
      if imgui.button("Cancel##appearance_operation") then
        state.operation, state.error, state.name = nil, nil, ""
        state.status, state.message = nil, nil
      end
      imgui.end_disabled()
    end
    local request = state.pending or state.request
    if request and (request.action == ACTION_LOAD or request.action == ACTION_NPC) then
      utils.TextColored("Applying appearance...", COLOR_INFO)
    end
    local problem = state.error
    if not problem and (state.status == "failed" or state.status == "unavailable") then
      problem = state.message
    end
    if not problem and active and Transmogify.npc_editor.status == "failed" then
      problem = "NPC appearance options could not initialize: " .. tostring(Transmogify.npc_editor.message)
    end
    if not problem and active and picker.status == "failed" then problem = picker.message end
    if problem then
      imgui.push_style_color(IMGUI_COLOR_TEXT, 0xFF0000FF)
      imgui.text(problem)
      imgui.pop_style_color(1)
    end
  end
end)()

do
  local WINDOW = {
    TAB_PRESETS = 1,
    TAB_LANTERN = 2,
    TAB_CHARACTER = Transmogify.CHARACTER_TAB,
    TAB_NPCS = 4,
    TAB_SETTINGS = 5,
    WINDOW_TABS = {"Presets", "Lantern", "Character", "NPCs", "Settings"},
    ASSIGNMENT_LABELS = {"Arisen", "Main Pawn", "Pawn 2", "Pawn 3"},
    WINDOW_NO_SCROLLBAR = 8,
    WINDOW_NO_SCROLL_WITH_MOUSE = 16,
    WINDOW_NO_COLLAPSE = 32,
    WINDOW_NO_SAVED_SETTINGS = 256,
    IMGUI_COLOR_TEXT = 0,
    WINDOW_MARGIN = 16,
    ITEM_SPACING = 8,
    SIZE_MIN = 25,
    SIZE_MAX = 300,
    SIZE_STEP = 5,
  }
  Transmogify.window.tab = WINDOW.TAB_PRESETS

  function Transmogify.FlushWindowSave()
    local window = Transmogify.window
    if window.geometry_dirty then Transmogify.preset_editor.pending_save = true end
    Transmogify.FlushPresetSave()
    window.geometry_dirty = false
  end

  function Transmogify.HideWindow()
    Transmogify.FlushWindowSave()
    Transmogify.window.open = false
  end

  function Transmogify.DrawWindow()
    local window = Transmogify.window
    if not window.open or not reframework:is_drawing_ui() then return end
    Transmogify.preset_editor.drawn = true
    Transmogify.preset_editor.ui_open = true
    local geometry = CURRENT_SETTINGS.window
    if not window.placed then
      local display = imgui.get_display_size()
      local width = math.max(Transmogify.WINDOW_WIDTH, geometry.width or Transmogify.WINDOW_WIDTH)
      local height = math.max(Transmogify.WINDOW_HEIGHT, geometry.height or Transmogify.WINDOW_HEIGHT)
      local x = math.max(0, math.min(geometry.x or (display.x - width) / 2, display.x - width))
      local y = math.max(0, math.min(geometry.y or (display.y - height) / 2, display.y - height))
      imgui.set_next_window_pos(Vector2f.new(x, y), 0, Vector2f.new(0, 0))
      imgui.set_next_window_size(Vector2f.new(width, height), 0)
      window.placed = true
    end

    imgui.push_font(font)
    imgui.push_style_var(imgui.ImGuiStyleVar.WindowMinSize,
      Vector2f.new(Transmogify.WINDOW_WIDTH, Transmogify.WINDOW_HEIGHT))
    local open = imgui.begin_window(modname .. " " .. version .. "###TransmogifyWindow", true,
      WINDOW.WINDOW_NO_SCROLLBAR + WINDOW.WINDOW_NO_SCROLL_WITH_MOUSE +
      WINDOW.WINDOW_NO_COLLAPSE + WINDOW.WINDOW_NO_SAVED_SETTINGS)
    imgui.pop_style_var(1)
    local position = imgui.get_window_pos()
    local size = imgui.get_window_size()
    if geometry.x ~= position.x or geometry.y ~= position.y or geometry.width ~= size.x or geometry.height ~= size.y then
      geometry.x, geometry.y, geometry.width, geometry.height = position.x, position.y, size.x, size.y
      window.geometry_dirty = true
    end
    local adjusting = false
    if open then
      if not Transmogify.init_complete then
        local message = Transmogify.init_status
        if Transmogify.init_weapon_total > 0 then
          message = message .. ": " .. Transmogify.init_weapon_current .. " / " .. Transmogify.init_weapon_total
        end
        if Transmogify.init_waiting_prefab then message = message .. " (waiting on " .. Transmogify.init_waiting_prefab .. ")" end
        utils.TextColored(message, COLOR_INFO)
      else
        local changed, enabled = imgui.checkbox("Enable Transmogs", CURRENT_SETTINGS.enabled)
        if changed then
          CURRENT_SETTINGS.enabled = enabled
          Transmogify.SettingsChanged(true)
        end
        imgui.separator()
        local tabSpace = size.x - WINDOW.WINDOW_MARGIN * 2 - WINDOW.ITEM_SPACING * (#WINDOW.WINDOW_TABS - 1)
        local textSpace, tabText = 0, {}
        for index, label in ipairs(WINDOW.WINDOW_TABS) do
          tabText[index] = imgui.calc_text_size(label).x
          textSpace = textSpace + tabText[index]
        end
        local labelSpace = tabSpace - WINDOW.ITEM_SPACING * 2 * #WINDOW.WINDOW_TABS
        local compactTabs = textSpace > labelSpace
        if compactTabs then
          imgui.push_font_size(math.floor(fontSize * labelSpace / textSpace))
          textSpace = 0
          for index, label in ipairs(WINDOW.WINDOW_TABS) do
            tabText[index] = imgui.calc_text_size(label).x
            textSpace = textSpace + tabText[index]
          end
        end
        local tabPadding = (tabSpace - textSpace) / #WINDOW.WINDOW_TABS
        for index, label in ipairs(WINDOW.WINDOW_TABS) do
          if index > 1 then imgui.same_line() end
          if window.tab == index then imgui.push_style_color(WINDOW.IMGUI_COLOR_TEXT, COLOR_INFO) end
          local clicked = imgui.button(label .. "##window_tab", Vector2f.new(tabText[index] + tabPadding, 0))
          if window.tab == index then imgui.pop_style_color(1) end
          if clicked and window.tab ~= index then
            Transmogify.FlushPresetSave()
            if window.tab == WINDOW.TAB_CHARACTER then Transmogify.ResetAppearanceEditor() end
            window.tab = index
            if index == WINDOW.TAB_NPCS then Transmogify.RefreshAppearancePresets() end
          end
        end
        if compactTabs then imgui.pop_font_size() end
        imgui.separator()

        local visible = imgui.begin_child_window("tab_content_" .. window.tab, Vector2f.new(0, 0), false, 0)
        if visible then
          if window.tab == WINDOW.TAB_PRESETS then
            imgui.text("Character assignments")
            if imgui.begin_table("character_assignments", 2,
              imgui.TableFlags.SizingStretchSame + imgui.TableFlags.NoPadOuterX, Vector2f.new(0, 0), 0) then
              local assignments = {}
              for index, charInfo in ipairs(char_info_list) do
                assignments[#assignments + 1] = {label = WINDOW.ASSIGNMENT_LABELS[index], settings_set = charInfo.settings_set}
              end
              for first = 1, #assignments, 2 do
                imgui.table_next_row()
                for column = 0, 1 do
                  local assignment = assignments[first + column]
                  if assignment then
                    imgui.table_set_column_index(column)
                    imgui.text(assignment.label)
                  end
                end
                imgui.table_next_row()
                for column = 0, 1 do
                  local assignment = assignments[first + column]
                  if assignment then
                    imgui.table_set_column_index(column)
                    imgui.set_next_item_width(-1)
                    local selected = GetIndexByVal(transmogSetList, CURRENT_SETTINGS[assignment.settings_set])
                    local assignmentChanged, nextIndex = imgui.combo("##assign_" .. assignment.settings_set, selected, transmogSetList)
                    if assignmentChanged then
                      CURRENT_SETTINGS[assignment.settings_set] = transmogSetList[nextIndex]
                      Transmogify.SettingsChanged(true)
                    end
                  end
                end
              end
              imgui.end_table()
            end
            imgui.separator()
            adjusting = Transmogify.DrawPresetEditor()
          else
            if window.tab == WINDOW.TAB_LANTERN then
              local showChanged, show = imgui.checkbox("Show Lantern", CURRENT_SETTINGS.show_lantern)
              if showChanged then
                CURRENT_SETTINGS.show_lantern = show
                if not show then CURRENT_SETTINGS.hide_lantern_when_off = false end
                Transmogify.preset_editor.pending_save = true
              end
              imgui.begin_disabled(not CURRENT_SETTINGS.show_lantern)
              local hideChanged, hide = imgui.checkbox("Hide Lantern When Off", CURRENT_SETTINGS.hide_lantern_when_off)
              if hideChanged then
                CURRENT_SETTINGS.hide_lantern_when_off = hide
                Transmogify.preset_editor.pending_save = true
              end
              imgui.end_disabled()
              imgui.text("Lantern Size")
              imgui.set_next_item_width(math.min(450, size.x - WINDOW.WINDOW_MARGIN * 2))
              local sizeChanged, lanternSize = imgui.drag_int("%##lantern_size", CURRENT_SETTINGS.lantern_size, WINDOW.SIZE_STEP, WINDOW.SIZE_MIN, WINDOW.SIZE_MAX)
              adjusting = imgui.is_item_active()
              if sizeChanged then
                CURRENT_SETTINGS.lantern_size = utils.GetSize(lanternSize, WINDOW.SIZE_MIN, WINDOW.SIZE_MAX, WINDOW.SIZE_STEP)
                Transmogify.preset_editor.pending_save = true
              end
            elseif window.tab == WINDOW.TAB_CHARACTER then
              Transmogify.DrawCharacterTab()
            elseif window.tab == WINDOW.TAB_NPCS then
              Transmogify.DrawNPCTab()
            elseif window.tab == WINDOW.TAB_SETTINGS then
              for _, option in ipairs({
                {"Also transmog scene-specific equipment", "cinematic_transmog"},
                {"Enable Pawn Shadow Ban Protection", "pawn_shadow_ban_protection"},
                {"Resize on Sheathe/Draw", "resizeOnSheathe"},
                {"Disable Draconic Effect", "hideDraconic"},
                {"Performance Monitor", "performance_monitor"},
              }) do
                local optionChanged, value = imgui.checkbox(option[1], CURRENT_SETTINGS[option[2]])
                if optionChanged then
                  CURRENT_SETTINGS[option[2]] = value
                  if option[2] == "hideDraconic" then Transmogify.hide_draconic_countdown = Transmogify.HIDE_DRACONIC.DELAY end
                  Transmogify.SettingsChanged(true)
                end
              end
              SetPerfEnabled(CURRENT_SETTINGS.performance_monitor)
              if CURRENT_SETTINGS.performance_monitor then DrawPerfStatsUI() end
            end
          end
        end
        imgui.end_child_window()
      end
    end
    local geometryFinished = window.geometry_dirty and not imgui.is_mouse_down(0)
    if geometryFinished then Transmogify.preset_editor.pending_save = true end
    imgui.end_window()
    imgui.pop_font()
    if not open then
      Transmogify.HideWindow()
    elseif not adjusting then
      Transmogify.FlushPresetSave()
      if geometryFinished then window.geometry_dirty = false end
    end
  end
end

local function drawUI()
  local window = Transmogify.window
  imgui.push_font(font)
  imgui.set_next_item_open(window.open, 0)
  local open = imgui.tree_node(modname .. " " .. version)
  if open then imgui.tree_pop() end
  imgui.pop_font()
  if open == window.open then return end
  if open then
    window.open = true
  else
    Transmogify.HideWindow()
  end
end

Transmogify.init_start_time = utils.Seconds()
Transmogify.init_coroutine = nil
Transmogify.init_prefab_loader = nil
Transmogify.init_waiting_prefab = nil
Transmogify.init_complete = false
Transmogify.init_status = "Initializing Transmogify..."
Transmogify.init_weapon_current = 0
Transmogify.init_weapon_total = 0
re.on_draw_ui(drawUI)

local function OnScriptReset()
  Transmogify.CleanupWeaponPreparations()
  Transmogify.HideWindow()
  if Transmogify.init_complete then Transmogify.SelectPreset("") end
  Transmogify.ResetAppearanceEditor()
  local loader = Transmogify.init_prefab_loader
  Transmogify.init_prefab_loader = nil
  if loader then loader:Cleanup() end
end

local ShouldTransmogWeapons
do
  local function IsCorrectResourceFromFacts(part, weapon_id, equip_category)
    if not part.mesh_object then return false end
    local item_by_id = ITEM_INFO_DIC[weapon_id]
    if not item_by_id then return false end
    local item_info = item_by_id[equip_category]
    if not item_info then return false end
    return part.mesh_path == item_info.mesh_path and part.material_path == item_info.mat_path
  end

  -- Whether a character's weapons need installing again, decided on the engine facts YowaveUtils.weapons.read gathers in
  -- one call.
  function ShouldTransmogWeapons(character, set_name, char_info)
    local transmog_weapons = false
    if character then
      local npc = char_info and char_info.npc
      local facts = native_weapons.read(character:get_address(), npc == true, SLOT_MAIN_HAND, SLOT_OFF_HAND)
      if not facts.human then return false end
      if (facts.main and facts.main.look) or (facts.off and facts.off.look) then return true end
      local main_weapon_item_data, off_weapon_item_data, _, _, native_ids = Transmogify.GetWorldWeaponDataFromFacts(facts, npc)
      if native_ids == false then return false end

      local job = nil
      if main_weapon_item_data then
        job = main_weapon_item_data:getJob()
      elseif off_weapon_item_data then
        job = off_weapon_item_data:getJob()
      end

      if not job then
        return
      end

      local right, left = facts.right, facts.left
      local paused = facts.paused

      if job == EQUIP_JOB_ARCHER then
        local quiver = facts.quiver
        if not quiver or not quiver.object_valid then return true end
      end

      if not paused and char_info then
        local signature = Transmogify.GetWeaponGlowSignature(set_name, job)
        if char_info.weapon_glow_signature ~= signature or char_info.weapon_glow_character ~= sdk.to_ptr(character) then
          return true
        end
      end

      local equip_info_type_list = JOB_TO_WEAPON_EQUIP_INFO_TYPE_LIST[job]
      for i, equip_info_type in pairs(equip_info_type_list) do
        local equip_info = EQUIPMENT_INFO[equip_info_type]
        local slot = equip_info.slot

        local slot_item_data = nil
        local slot_part = nil
        if slot == SLOT_MAIN_HAND then
          slot_item_data = main_weapon_item_data
          if equip_info.hand == RIGHT_HAND then
            slot_part = right
          elseif equip_info.hand == LEFT_HAND then
            slot_part = left
          end
        elseif slot == SLOT_OFF_HAND then
          slot_item_data = off_weapon_item_data
          slot_part = left
        end

        if slot_item_data then
          local transmog_id_name = GetSetTransmogValue(set_name, equip_info_type)
          local transmog_id = GetTransmogId(transmog_id_name) or slot_item_data._WeaponId
          local sizes = CURRENT_SETTINGS.enabled and CURRENT_SETTINGS.setSize[set_name]
          local visible = transmog_id_name ~= SET_VALUE_HIDE and (not sizes or (sizes[equip_info_type] or 100) > 0)

          if not (slot_part and slot_part.mesh) then
            transmog_weapons = true
          elseif not IsCorrectResourceFromFacts(slot_part, transmog_id, slot_item_data._EquipCategory) then
            transmog_weapons = true
          elseif visible and Transmogify.GetHideWhenSheathed(set_name, equip_info_type) then
            -- The draw check owns this weapon's visibility: a mismatch with the draw state makes it apply again.
            local sheathed = Transmogify.GetDrawStateFromFacts(facts, main_weapon_item_data, off_weapon_item_data) ==
              Transmogify.DRAW_STATE.SHEATHED
            if slot_part.enabled == sheathed then
              Transmogify.ClearAppliedDrawState(character, npc, char_info)
            end
          elseif slot_part.enabled ~= visible then
            -- A weapon Hide when sheathed hid is shown again by the draw check rather than reinstalled.
            if visible and char_info and char_info.sheathe_hidden then
              Transmogify.ClearAppliedDrawState(character, npc, char_info)
            else
              transmog_weapons = true
            end
          end
        end
      end
      if not transmog_weapons and npc then
        local specs = Transmogify.GetWeaponPartSpecs(main_weapon_item_data, off_weapon_item_data, nil, nil, set_name, native_ids)
        if not specs then return false end
        for _, spec in ipairs(specs) do
          local part
          if spec.part == Transmogify.WEAPON_PARTS.right then part = right
          elseif spec.part == Transmogify.WEAPON_PARTS.left then part = left
          else part = facts.quiver end
          if not part or not part.object or not part.mesh or not part.mesh_ready or not part.material_ready then return true end
          if spec.resources and (part.mesh_path ~= spec.resources.mesh_path or
            part.material_path ~= spec.resources.mat_path) then return true end
        end
      end
      -- Hidden meshes skip the glow hook, so their glow is set again when they reappear rather than compared here. With
      -- an intensity when sheathed, the comparison waits for the draw check to apply a state, which writes the glow.
      if not transmog_weapons and not paused and char_info and not char_info.sheathe_hidden and
        not (Transmogify.PresetUsesSheathedGlow(set_name) and not Transmogify.GetAppliedDrawState(character, npc, char_info)) then
        local right_mesh = right and right.mesh and sdk.to_managed_object(right.mesh)
        local left_mesh = left and left.mesh and sdk.to_managed_object(left.mesh)
        transmog_weapons = Transmogify.ProcessWeaponSetGlow(set_name, main_weapon_item_data, off_weapon_item_data,
          right_mesh, left_mesh, false, Transmogify.IsGlowSheathed(character, npc, char_info, set_name))
      end
    end
    return transmog_weapons
  end
end

function Transmogify.UpdateNPCWeapons(character, set_name, original, override, pending_only)
  if Transmogify.HasWorldWeaponPreparation(character) ~= (pending_only == true) then return false end
  local main, off, _, _, native_ids = Transmogify.GetWorldWeaponData(character, true)
  if native_ids == false then return false end
  if not main and not off and (native_ids.right ~= 0 or native_ids.left ~= 0 or native_ids.quiver ~= 0) then return false end
  local draw = Transmogify.npc_draw_states[tostring(cm.getCharaID:call(character))]
  if draw and draw.character ~= sdk.to_ptr(character) then draw = nil end
  local applied_state = Transmogify.GetAppliedDrawState(character, true)
  local info = {npc = true, weapon_glow_signature = original.weapon_glow_signature,
    weapon_glow_character = sdk.to_ptr(character), sheathe_hidden = draw ~= nil and draw.sheathe_hidden}
  if pending_only or ShouldTransmogWeapons(character, set_name, info) then
    if not TransmogWeapons(character, set_name, true) then return false end
  end
  if not ApplyWeaponDrawState(character, set_name, true, applied_state) then return false end
  local job = main and main:getJob() or (off and off:getJob())
  local signature = Transmogify.GetWeaponGlowSignature(set_name, job)
  local changed = original.weapon_glow_signature ~= signature or original.weapons_active ~= override
  original.weapon_glow_signature, original.weapons_active = signature, override
  return changed
end

local function ShouldTransmogArmors(character, set_name)
  if not character then return false end
  local facts = Transmogify.ReadArmor("world", nil, character, Transmogify.GetArmorTargets(set_name))
  if not facts.meta or facts.undress ~= UNDERSS_NONE or facts.swapping then return false end
  if facts.items then
    for _, item in pairs(facts.items) do
      if item.look then return true end
    end
  end
  local desired = Transmogify.GetDesiredArmorStyles(facts, set_name)
  if not desired then return false end
  for category, style in pairs(desired) do
    if facts.styles[category] ~= style then return true end
  end
  return false
end

re.on_script_reset(OnScriptReset)

Transmogify.refresh_gui_face_timer = 5
Transmogify.refresh_gui_face = {}
Transmogify.menu_face_refresh_request = nil
Transmogify.game_loaded = true
Transmogify.is_paused_gui = false
Transmogify.LOGIC_WARMUP_FRAMES = 60
Transmogify.logic_warmup_frames = Transmogify.LOGIC_WARMUP_FRAMES
Transmogify.had_player_in_prev_frame = false
local finished_rearm = false

local function GetFrameCharacters()
  local player, pawn, pawn2, pawn3 = utils.GetParty()
  return {player = player, pawn = pawn, pawn2 = pawn2, pawn3 = pawn3}
end

function Transmogify.UpdateStartup()
  if Transmogify.init_start_time then
    if utils.Seconds() - Transmogify.init_start_time < 3 then return end
    Transmogify.init_start_time = nil
    Transmogify.init_started = utils.Seconds()
    Transmogify.init_coroutine = coroutine.create(Init)
  end

  if not Transmogify.init_complete and Transmogify.init_coroutine and Transmogify.ResumeCatalogBuild() then return end

  if not Transmogify.IsAppearanceBusy() then Transmogify.UpdateMenuFaceRefresh() end
end

-- Resumes the catalog build in Transmogify.init_coroutine: the first build from Transmogify.UpdateStartup, later updates
-- from Transmogify.UpdateCatalogCheck. Returns true while it still runs; a failed build ends its prefab loads and raises.
function Transmogify.ResumeCatalogBuild()
  local init_success, init_error = coroutine.resume(Transmogify.init_coroutine)
  if not init_success then
    local loader = Transmogify.init_prefab_loader
    Transmogify.init_prefab_loader, Transmogify.init_coroutine, Transmogify.init_waiting_prefab = nil, nil, nil
    if loader then
      local cleaned, cleanup_error = pcall(loader.Cleanup, loader)
      if not cleaned then error(tostring(init_error) .. "; cleanup failed: " .. tostring(cleanup_error), 0) end
    end
    error(init_error)
  end
  if coroutine.status(Transmogify.init_coroutine) ~= "dead" then return true end
  Transmogify.init_coroutine = nil
  return false
end

re.on_frame(
  function()
    Transmogify.UpdatePresetEditor()
    Transmogify.DrawWindow()
  end
)

do
  local EYE = {
    INTERVAL = 30, FULL_PASS_INTERVAL = 10, INDEX_KEY = "eyes_written",
    STATUS_MASK = (1 << 21) | (1 << 22), HEAD = "head", EPSILON = 0.001, PLAGUE_THRESHOLD = 0.0001,
    GLOW_HASH = utils.MurmurHash("Eye_Emissive_Intensity"), PLAGUE_HASH = utils.MurmurHash("Emissive_Intensity"),
    COLOR1_HASH = utils.MurmurHash("Emissive_Color1"), COLOR2_HASH = utils.MurmurHash("Emissive_Color2"),
    DEFAULT_COLOR1 = {x = 1, y = 0, z = 0}, DEFAULT_COLOR2 = {x = 1, y = 0, z = 50 / 255},
    SKIPPED_SCENES = {[120] = true, [1200] = true, [2400] = true, [3000] = true, [3100] = true, [7100] = true},
  }
  local EYE_SIDES = {{key = "left", material = "l_eye_mat"}, {key = "right", material = "r_eye_mat"}}
  local OUTCOME_RANK = {default = 1, game = 2, custom = 3}
  local PATHFINDER_ID = sdk.find_type_definition("app.CharacterID"):get_field("ch310074"):get_data(nil)
  -- Each run (every INTERVAL updates) checks every copy of the characters with eye glow; new copies and characters
  -- whose Brainwash or Phantom possession status changed get a thorough check. The resident index lists the characters
  -- whose eyes this pass changed; full passes check thoroughly and also restore indexed characters without eye glow,
  -- so a glow turned off is undone while characters never changed keep eyes from other mods. Full passes run on the
  -- first run after script load, after settings changes and every FULL_PASS_INTERVAL runs.
  Transmogify.eye_glow = {countdown = 0, full = true, passes = 0, seen = {}, status = {}}

  local function HasEyeGlow(eyes)
    return eyes ~= nil and (eyes.left.enabled or (not eyes.same and eyes.right.enabled))
  end

  local EYE_NATIVE = {head = EYE.HEAD, left = EYE_SIDES[1].material, right = EYE_SIDES[2].material,
    glow = EYE.GLOW_HASH, plague = EYE.PLAGUE_HASH, color1 = EYE.COLOR1_HASH, color2 = EYE.COLOR2_HASH}
  local native_eyes = YowaveUtils.eyes

  local function EyeColorMatches(current, color)
    return math.abs(current.x - color.x) <= EYE.EPSILON and math.abs(current.y - color.y) <= EYE.EPSILON and
      math.abs(current.z - color.z) <= EYE.EPSILON and math.abs(current.w - 1) <= EYE.EPSILON
  end

  -- Returns one eye's desired colors and intensity (nil leaves intensity to a game state) and the head's outcome:
  -- "custom" for preset eyes, "default" for the game's eyes, or "game" while a game state owns them.
  local function DesiredEye(settings, state_active, plague)
    if state_active then return EYE.DEFAULT_COLOR1, EYE.DEFAULT_COLOR2, nil, "game" end
    if plague then return EYE.DEFAULT_COLOR1, EYE.DEFAULT_COLOR2, 0, "game" end
    if settings and settings.enabled then
      local color = {x = settings.r, y = settings.g, z = settings.b}
      return color, color, settings.intensity, "custom"
    end
    return EYE.DEFAULT_COLOR1, EYE.DEFAULT_COLOR2, 0, "default"
  end

  -- Game writers and this driver always change both eyes together, so outside thorough checks one eye's intensity,
  -- first color and plague glow stand for the head: the right eye when only it glows, otherwise the left. head is a
  -- copy's head facts (see YowaveUtils.eyes.read). Returns the head's write for eyes.apply, or nil when the quick check
  -- finds it current, and the head's outcome.
  local function DecideEyeHead(head, eyes, thorough, check_state)
    local state_active = check_state and head.state
    if not thorough then
      local side = eyes and not eyes.same and not eyes.left.enabled and eyes.right.enabled and "right" or "left"
      local eye = head[side]
      local color1, _, intensity, outcome = DesiredEye(eyes and eyes[side], state_active,
        eye.plague > EYE.PLAGUE_THRESHOLD)
      if EyeColorMatches(eye.color1, color1) and (not intensity or math.abs(eye.glow - intensity) <= EYE.EPSILON) then
        return nil, outcome
      end
    end
    local write, outcome = {mesh = head.mesh}, nil
    for _, side in ipairs(EYE_SIDES) do
      local color1, color2, intensity, eye_outcome = DesiredEye(eyes and eyes[eyes.same and "left" or side.key],
        state_active, head[side.key].plague > EYE.PLAGUE_THRESHOLD)
      outcome = outcome == "custom" and outcome or eye_outcome
      write[side.key] = {color1 = color1, color2 = color2, intensity = intensity}
    end
    return write, outcome
  end

  -- characters holds this update's party characters in char_info_list order.
  function Transmogify.UpdateEyeGlow(characters)
    local state = Transmogify.eye_glow
    state.countdown = state.countdown - 1
    if state.countdown > 0 then return end
    state.countdown = EYE.INTERVAL
    state.passes = state.passes + 1
    local memo = Transmogify.GetNativeStorage()
    if memo and memo ~= state.memo then
      local index, ready = Transmogify.GetNativeData(EYE.INDEX_KEY)
      if ready then state.memo, state.index = memo, index or {} end
    end
    local index = memo and memo == state.memo and state.index
    if not index then return end
    local full = state.full or state.passes >= EYE.FULL_PASS_INTERVAL
    if full then state.full, state.passes = false, 0 end
    local party, npcs, party_keys = {}, {}, {}
    for position, char_info in ipairs(char_info_list) do
      local character = characters[position]
      if character then
        local id = character:get_CharaID()
        local key = tostring(id)
        local eyes = Transmogify.GetEyeSettings(GetSetNameByCharInfo(char_info))
        party_keys[key] = true
        if HasEyeGlow(eyes) or (full and index[key]) then
          party[#party + 1] = {key = key, id = id, char_info = char_info, character = character, eyes = eyes}
        end
      end
    end
    local keys = {}
    for key in pairs(CURRENT_SETTINGS.npcSets) do keys[key] = true end
    for key in pairs(index) do keys[key] = true end
    for key in pairs(keys) do
      local id = assert(tonumber(key), "Invalid eye glow character ID")
      local eyes = Transmogify.GetEyeSettings(Transmogify.GetNPCSetName(id))
      if not party_keys[key] and id ~= PATHFINDER_ID and (HasEyeGlow(eyes) or (full and index[key])) then
        npcs[#npcs + 1] = {key = key, id = id, eyes = eyes}
      end
    end
    local seen = {}
    if #party == 0 and #npcs == 0 then
      state.seen = seen
      return
    end

    local targets = {}
    for _, entry in ipairs(party) do
      targets[#targets + 1] = {entry = entry, id = entry.id, character = sdk.to_ptr(entry.character), menu = true}
    end
    for _, entry in ipairs(npcs) do
      local character = Transmogify.GetNPCCharacter(entry.id)
      targets[#targets + 1] = {entry = entry, id = entry.id, character = character and sdk.to_ptr(character)}
    end
    local work = Transmogify.GetCurrentCinematic()
    if work and (not (work:get_IsPlaying() or work:get_IsPaused()) or
      EYE.SKIPPED_SCENES[work:get_TimelineEventID()]) then
      work = nil
    end
    local facts = native_eyes.read(EYE_NATIVE, targets, work and sdk.to_ptr(work))
    local writes, menu_entries, outcomes = {}, {}, {}
    for position, target in ipairs(targets) do
      local result = facts[position]
      local status = (result.status or 0) & EYE.STATUS_MASK
      local status_changed = state.status[target.id] ~= nil and state.status[target.id] ~= status
      state.status[target.id] = status
      -- The combined outcome of the copies checked: "custom" when any shows preset eyes, "default" when all show the
      -- game's eyes, "game" when a game state owns some, nil when none was found.
      local combined
      for _, copy in ipairs(result.copies) do
        local new_copy = not state.seen[copy.object]
        seen[copy.object] = true
        if copy.head then
          -- The menu model and the editor preview have no Brainwash material interpolation, so only the plague glow
          -- applies there.
          local write, outcome = DecideEyeHead(copy.head, target.entry.eyes, full or new_copy or status_changed,
            copy.kind == "world" or copy.kind == "clone")
          if write then
            writes[#writes + 1] = write
            if copy.kind == "menu" then menu_entries[#writes] = target.entry end
          end
          if not combined or OUTCOME_RANK[outcome] > OUTCOME_RANK[combined] then combined = outcome end
        end
      end
      outcomes[position] = combined
    end
    local written = #writes > 0 and native_eyes.apply(EYE_NATIVE, writes, EYE.EPSILON) or {}
    for position = 1, #writes do
      if menu_entries[position] and written[position] then
        Transmogify.QueueMenuFaceRefresh(menu_entries[position].char_info)
      end
    end
    local changed = false
    for position, target in ipairs(targets) do
      local entry, outcome = target.entry, outcomes[position]
      if outcome == "custom" and not index[entry.key] then
        index[entry.key], changed = true, true
      elseif outcome == "default" and index[entry.key] and not HasEyeGlow(entry.eyes) then
        index[entry.key], changed = nil, true
      end
    end
    state.seen = seen
    if changed then assert(Transmogify.SetNativeData(EYE.INDEX_KEY, index), "Native storage is unavailable") end
  end
end

function Transmogify.UpdateReconciliation()
  BeginPerfUpdate(CURRENT_SETTINGS.performance_monitor)
  Transmogify.UpdateWeaponGlowInUse()
  StartTimer("barber")
  Transmogify.UpdateNpcEditorSupport()
  Transmogify.UpdateNpcAppearancePicker()
  EndTimer("barber")
  StartTimer("npc_looks")
  Transmogify.UpdateNPCLooks()
  EndTimer("npc_looks")
  Transmogify.UpdateWeaponPreparations()
  if not Transmogify.init_complete then
    EndPerfUpdate()
    return
  end

  StartTimer("catalog")
  Transmogify.UpdateNPCArmorCatalog()
  Transmogify.UpdateCatalogCheck()
  EndTimer("catalog")
  local appearance_work = Transmogify.IsAppearanceBusy()
  -- Barber glow targets wait while an appearance preset applies.
  if appearance_work ~= Transmogify.glow_appearance_work then
    Transmogify.glow_appearance_work = appearance_work
    Transmogify.RequestGlowCheck()
  end
  if appearance_work then
    StartTimer("barber")
    local success, reason = pcall(Transmogify.UpdateAppearancePresets)
    if not success then
      local state = Transmogify.appearance_presets
      state.request, state.pending = nil, nil
      state.status, state.error = "failed", tostring(reason)
      error(reason)
    end
    EndTimer("barber")
  end
  -- One party lookup per update: the party loops below use these instead of resolving the party again.
  local frame_characters = GetFrameCharacters()
  local frame_player = frame_characters.player
  local frame_pawn = frame_characters.pawn
  local frame_pawn2 = frame_characters.pawn2
  local frame_pawn3 = frame_characters.pawn3
  local party = {frame_player, frame_pawn, frame_pawn2, frame_pawn3}
  local party_ids = Transmogify.party_ids
  for id in pairs(party_ids) do party_ids[id] = nil end
  for i = 1, #char_info_list do
    if party[i] then party_ids[cm.getCharaID:call(party[i])] = true end
  end
  local has_player = frame_player ~= nil
  if has_player and not Transmogify.had_player_in_prev_frame then
    Transmogify.logic_warmup_frames = Transmogify.LOGIC_WARMUP_FRAMES
    CancelWorldWeaponPreparations()
    Transmogify.ClearWeaponGlow()
    warfarer_rearm_pending = false
  end
  Transmogify.had_player_in_prev_frame = has_player

  if Transmogify.logic_warmup_frames > 0 then
    Transmogify.logic_warmup_frames = Transmogify.logic_warmup_frames - 1
    EndPerfUpdate()
    return
  end

  StartTimer("weapon_glow")
  Transmogify.UpdateWeaponGlow(party)
  EndTimer("weapon_glow")

  Transmogify.GetNativeStorage()

  local editor = Transmogify.preset_editor
  if editor.refresh_pending and not appearance_work then
    local sizeOnly = not editor.refresh_appearance
    editor.refresh_pending, editor.refresh_appearance = false, false
    ResetCharInfoListDraw()
    StartTimer("gui_transitions")
    RefreshGUITransmogs(sizeOnly)
    EndTimer("gui_transitions")
  end

  StartTimer("barber")
  local barber_request = Transmogify.barber_open_request
  if barber_request then
    Transmogify.barber_open_request = nil
    local character
    if barber_request.is_player then
      character = frame_player
    else
      character = frame_pawn
    end
    local facility = sdk.get_managed_singleton("app.FacilityManager")
    if not character or sdk.to_ptr(character) ~= barber_request.character_address then
      Transmogify.barber_open_message = "Selected character is unavailable."
    elseif not facility or GuiManager:isPausedGUI() or facility:get_ExecFacility() ~= 0 or
      facility:get_IsExecuteCharaEdit() then
      Transmogify.barber_open_message = "Return to the world and close the current menu first."
    else
      facility:call("startBarber(app.GUICharaEditCtrl.DetailEditType, app.FacilityManager.BarberPlace, System.Boolean, System.Action)",
        Transmogify.BARBER_EDIT_CHARACTER, Transmogify.BARBER_PLACE_DEFAULT, barber_request.is_player, nil)
      Transmogify.barber_open_message = nil
    end
  end
  Transmogify.barber_check_countdown = Transmogify.barber_check_countdown - 1
  if Transmogify.barber_check_countdown <= 0 then
    Transmogify.barber_check_countdown = Transmogify.BARBER_CHECK.INTERVAL
    if not appearance_work then UpdateBarberTransmog() end
  end

  EndTimer("barber")

  StartTimer("eye_glow")
  Transmogify.UpdateEyeGlow(party)
  EndTimer("eye_glow")

  for i, char_info in pairs(char_info_list) do
    StartTimer("gui_weapons")
    UpdateGUIWeaponEnchant(char_info)
    EndTimer("gui_weapons")
  end

  StartTimer("lanterns")
  Transmogify.lantern_check_countdown = Transmogify.lantern_check_countdown - 1
  if Transmogify.lantern_check_countdown <= 0 then
    Transmogify.lantern_check_countdown = Transmogify.LANTERN_CHECK.INTERVAL
    Transmogify.UpdateLanterns(party)
  end
  EndTimer("lanterns")

  StartTimer("cinematic_shared")
  Transmogify.cinematic_check_countdown = Transmogify.cinematic_check_countdown - 1
  if Transmogify.cinematic_check_countdown <= 0 then
    Transmogify.cinematic_check_countdown = Transmogify.CINEMATIC_CHECK.INTERVAL
    Transmogify.UpdateCinematicTransmog()
  end
  EndTimer("cinematic_shared")

  local gui_paused = GuiManager:isPausedGUI()
  if gui_paused or Transmogify.gui_check_requested then
    Transmogify.gui_check_countdown = Transmogify.gui_check_countdown - 1
    if Transmogify.gui_check_countdown <= 0 then
      Transmogify.gui_check_countdown = Transmogify.GUI_CHECK.INTERVAL
      -- A portrait capture uses the same builder; a blocked request waits for the next pass.
      if not Transmogify.menu_face_refresh_request and not appearance_work then
        Transmogify.gui_check_requested = false
        local models, failure = {}, nil
        StartTimer("gui_weapons")
        for i in ipairs(char_info_list) do
          if party[i] then
            local success, result = pcall(Transmogify.ReadMenuModel, party[i])
            if success then models[i] = result elseif not failure then failure = result end
          end
        end
        EndTimer("gui_weapons")
        StartTimer("gui_armors")
        if gui_paused then
          for i, char_info in ipairs(char_info_list) do
            local facts = models[i]
            if facts and facts.builder and facts.complete and not facts.lock_equip then
              Transmogify.ApplyGUIArmor(facts.builder, party[i], GetSetNameByCharInfo(char_info))
            end
          end
        end
        EndTimer("gui_armors")
        StartTimer("gui_weapons")
        for i, char_info in ipairs(char_info_list) do
          if models[i] then
            local success, reason = pcall(TransmogGUIWeapons, party[i], CURRENT_SETTINGS[char_info.settings_set], models[i],
              gui_paused)
            if not success and not failure then failure = reason end
          end
        end
        EndTimer("gui_weapons")
        if failure then error(failure) end
      end
    end
  end

  StartTimer("gui_transitions")
  if not Transmogify.is_paused_gui and GuiManager:isPausedGUI() then
    Transmogify.is_paused_gui = true
    Transmogify.RequestGlowCheck()
    CancelWorldWeaponPreparations()
  elseif Transmogify.is_paused_gui and not GuiManager:isPausedGUI() then
    Transmogify.is_paused_gui = false
    Transmogify.RequestGlowCheck()
    RefreshGUIWeaponsOnExit(frame_player)
    RefreshGUIWeaponsOnExit(frame_pawn)
    RefreshGUIWeaponsOnExit(frame_pawn2)
    RefreshGUIWeaponsOnExit(frame_pawn3)
  end

  EndTimer("gui_transitions")

  if not isPaused then
    if Transmogify.game_loaded then
      ResetCharInfoListDraw()

      for i, char_info in ipairs(char_info_list) do
        if party[i] then
          Transmogify.QueueMenuFaceRefresh(char_info)
        end
      end

      Transmogify.game_loaded = false
      utils.LogD("Load Game")
    end

    StartTimer("draconic")
    if Transmogify.hide_draconic_countdown > 0 then
      Transmogify.hide_draconic_countdown = Transmogify.hide_draconic_countdown - 1
      if Transmogify.hide_draconic_countdown <= 0 then
        HideWeaponDraconic(frame_player, CURRENT_SETTINGS.hideDraconic)
        HideArmorDraconic(frame_player, CURRENT_SETTINGS.hideDraconic)

        HideWeaponDraconic(frame_pawn, CURRENT_SETTINGS.hideDraconic)
        HideArmorDraconic(frame_pawn, CURRENT_SETTINGS.hideDraconic)

        HideWeaponDraconic(frame_pawn2, CURRENT_SETTINGS.hideDraconic)
        HideArmorDraconic(frame_pawn2, CURRENT_SETTINGS.hideDraconic)

        HideWeaponDraconic(frame_pawn3, CURRENT_SETTINGS.hideDraconic)
        HideArmorDraconic(frame_pawn3, CURRENT_SETTINGS.hideDraconic)
      end
    end
    EndTimer("draconic")

    StartTimer("world_weapons")
    for key, request in pairs(Transmogify.weapon_preparations) do
      local context = request.context
      if context.kind == Transmogify.WEAPON_CONTEXT.WORLD and not context.npc then
        local char_info, character = GetCharInfoById(context.character:get_CharaID())
        if char_info and character and sdk.to_ptr(character) == sdk.to_ptr(context.character) then
          TransmogWeapons(character, GetSetNameByCharInfo(char_info))
        else
          Transmogify.CancelWeaponPreparation(key)
        end
      end
    end
    Transmogify.weapon_check_countdown = Transmogify.weapon_check_countdown - 1
    if Transmogify.weapon_check_countdown <= 0 then
      Transmogify.weapon_check_countdown = Transmogify.WEAPON_CHECK.INTERVAL
      for i, char_info in ipairs(char_info_list) do
        local character = party[i]
        if character and not Transmogify.HasWorldWeaponPreparation(character) then
          local set_name = CURRENT_SETTINGS[char_info.settings_set]
          if ShouldTransmogWeapons(character, set_name, char_info) then TransmogWeapons(character, set_name) end
        end
      end
    end
    EndTimer("world_weapons")
    StartTimer("npc_armors")
    Transmogify.UpdateNPCTransmog(true)
    EndTimer("npc_armors")

    Transmogify.armor_check_countdown = Transmogify.armor_check_countdown - 1
    if Transmogify.armor_check_countdown <= 0 then
      Transmogify.armor_check_countdown = Transmogify.ARMOR_CHECK.INTERVAL
      for i, char_info in ipairs(char_info_list) do
        local character = party[i]
        local set_name = CURRENT_SETTINGS[char_info.settings_set]
        if character then
          StartTimer("world_armors")
          if ShouldTransmogArmors(character, set_name) then
            TransmogArmors(character, set_name)
            Transmogify.QueueMenuFaceRefresh(char_info)
          end
          EndTimer("world_armors")
        end
      end
      StartTimer("npc_armors")
      Transmogify.UpdateNPCTransmog()
      EndTimer("npc_armors")
    end

    StartTimer("weapon_resize")
    local DRAW_STATE = Transmogify.DRAW_STATE
    Transmogify.draw_check_countdown = Transmogify.draw_check_countdown - 1
    for i, char_info in ipairs(char_info_list) do
      -- Hidden weapons must be back before the hand reaches them, which a bow draw does 3 updates after it starts.
      if char_info.sheathe_hidden and not warfarer_rearm_pending and party[i] and
        cm.getIsDrawedWeapon:call(party[i]) then
        Transmogify.draw_check_countdown = 0
      end
    end
    if Transmogify.draw_check_countdown <= 0 then
      Transmogify.draw_check_countdown = Transmogify.DRAW_CHECK.INTERVAL
      for i, char_info in ipairs(char_info_list) do
        local character = party[i]
        local state = character and Transmogify.GetDrawState(character)
        local set_name = CURRENT_SETTINGS[char_info.settings_set]
        local apply = state and state ~= char_info.draw_state and
          Transmogify.GetDrawStateApply(char_info.draw_state, state, char_info.sheathe_hidden, set_name)
        if apply then
          local applied, hidden = ApplyWeaponDrawState(character, set_name, nil, state, apply == "show")
          if applied then
            char_info.draw_state, char_info.sheathe_hidden = state, hidden
            Transmogify.RequestWorldGlow(cm.getCharaID:call(character))
          end
        elseif state then
          char_info.draw_state = state
        end
      end
      local npc_states = Transmogify.npc_draw_states
      for key, record in pairs(npc_states) do
        local id = tonumber(key)
        local set_name = Transmogify.GetNPCSetName(id)
        if not Transmogify.PresetHidesSheathed(set_name) and not Transmogify.PresetUsesSheathedGlow(set_name) then
          -- The options or the assignment are gone: show weapons Hide when sheathed hid before forgetting the NPC.
          local character = record.sheathe_hidden and Transmogify.GetNPCCharacter(id)
          if character and sdk.to_ptr(character) == record.character then ApplyWeaponDrawState(character, set_name, true) end
          npc_states[key] = nil
        end
      end
      for key in pairs(CURRENT_SETTINGS.npcSets) do
        local id = tonumber(key)
        local set_name = Transmogify.GetNPCSetName(id)
        local character = (Transmogify.PresetHidesSheathed(set_name) or Transmogify.PresetUsesSheathedGlow(set_name)) and
          Transmogify.GetNPCCharacter(id)
        if character and not Transmogify.IsNPCWeaponOverrideStored(key, character) then character = nil end
        local record = npc_states[key]
        if not character then
          npc_states[key] = nil
        else
          local address = sdk.to_ptr(character)
          if not record or record.character ~= address then
            record = {character = address}
            npc_states[key] = record
          end
          local state = Transmogify.GetDrawState(character, true)
          -- The NPC pass may have hidden weapons before this record had a state.
          local apply = state ~= record.draw_state and Transmogify.GetDrawStateApply(record.draw_state, state,
            record.sheathe_hidden or record.draw_state == nil, set_name)
          -- A draw that follows an unnoticed landing is sized at the grab, not with a refresh mid-draw; show-only still
          -- sets the intensity when sheathed.
          if apply == "full" and state == DRAW_STATE.DRAWING then
            apply = Transmogify.PresetUsesSheathedGlow(set_name) and "show" or nil
          end
          if apply then
            local applied, hidden = ApplyWeaponDrawState(character, set_name, true, state, apply == "show")
            if applied then
              record.draw_state, record.sheathe_hidden = state, hidden
              Transmogify.RequestWorldGlow(id)
            end
          else
            record.draw_state = state
          end
        end
      end
    end
    EndTimer("weapon_resize")
  end

  isPaused = true
  StartTimer("weapon_glow")
  local glow_failure = Transmogify.UpdateWeaponGlow(party, true)
  EndTimer("weapon_glow")
  EndPerfUpdate()
  if glow_failure then error(glow_failure, 0) end
end

do
  local failure

  local function RunHostUpdate(update)
    local success, reason = pcall(update)
    if success then return end
    utils.Log("[Transmogify] host update error: " .. tostring(reason))
    failure = failure and failure .. "\n" .. tostring(reason) or tostring(reason)
  end

  -- REFramework callbacks run outside any engine managed frame, so a native call that enters and leaves managed code
  -- there can run this thread's temporary-object cleanup mid-call. The engine dispatches this callback on the main
  -- thread inside a managed frame, once per frame in every observed game state, after the late behavior update.
  Transmogify.frame_host_alive = false
  utils.HookFrameHost(function()
    if not Transmogify.frame_host_alive then
      Transmogify.frame_host_alive = true
      utils.Log("[Transmogify] frame host callback is running")
    end
    failure = nil
    RunHostUpdate(Transmogify.UpdateReconciliation)
    if Transmogify_Warfarer and Transmogify_Warfarer.Tick then RunHostUpdate(Transmogify_Warfarer.Tick) end
    RunHostUpdate(Transmogify.UpdateStartup)
    if failure then error(failure, 0) end
  end)

  -- Fallback: the native frame host hook can fail to install on a game build newer than this script. In that case the
  -- whole per-frame update loop never runs and the mod sits on its initial status forever. Drive the startup work from
  -- a REFramework application entry instead, which is dispatched on the main thread inside a managed frame.
  local fallback_reported = false
  re.on_application_entry("UpdateBehavior", function()
    if Transmogify.frame_host_alive then return end
    if not fallback_reported then
      fallback_reported = true
      utils.Log("[Transmogify] frame host hook is not firing; driving startup from UpdateBehavior instead")
    end
    local ok, reason = pcall(Transmogify.UpdateStartup)
    if not ok then
      utils.Log("[Transmogify] fallback UpdateStartup failed: " .. tostring(reason))
    end
  end)
end

do
  -- Recomputed every update, so a glow turned on in any preset reaches the glow pass by the next update.
  function Transmogify.UpdateWeaponGlowInUse()
    for _, glows in pairs(CURRENT_SETTINGS.setGlow) do
      for equip_type, glow in pairs(glows) do
        if equip_type ~= Transmogify.QUIVER_EQUIP_TYPE and glow.enabled then
          Transmogify.weapon_glow_in_use = true
          return
        end
      end
    end
    Transmogify.weapon_glow_in_use = false
  end

  local native_glow = YowaveUtils.glow
  -- Owner GameObject address -> true for each owner whose weapons the DLL holds.
  local glow_owners = {}
  -- CharacterID -> true for world characters to publish again at the end of the update.
  local world_glow_requests = {}
  -- CharacterID -> {key, npc, sheathed} for each published world character whose preset has an intensity when sheathed
  -- and whose draw state no draw check has applied: its glow follows the live draw state, checked every update.
  local live_draw_glow = {}
  -- The first glow failure since the end of the last update: the hook's, or one while publish applied a target.
  local glow_failure
  Transmogify.GLOW_CHECK = {INTERVAL = 5}
  Transmogify.glow_check_countdown = 0
  Transmogify.glow_check_requested = false

  function Transmogify.RequestGlowCheck()
    Transmogify.glow_check_requested = true
  end

  function Transmogify.RequestWorldGlow(id)
    world_glow_requests[id] = true
  end

  -- Nothing stays published, so the hook reports no rebuilt weapons; the next update publishes everything.
  function Transmogify.ClearWeaponGlow()
    if next(world_glow_requests) then world_glow_requests = {} end
    if next(live_draw_glow) then live_draw_glow = {} end
    Transmogify.RequestGlowCheck()
    if next(glow_owners) == nil then return end
    native_glow.clear()
    glow_owners = {}
  end

  -- At a preparation's start: the hook leaves its owner's weapons until the preparation ends.
  function Transmogify.RetractWeaponGlow(context)
    local owner = context.kind == Transmogify.WEAPON_CONTEXT.BARBER and context.model or utils.GetGameObject(context.owner)
    local key = owner and owner:get_address()
    if not key or not glow_owners[key] then return end
    native_glow.publish(key, {})
    glow_owners[key] = nil
  end

  -- Publishes the owner's weapons, else retracts the owner. An owner stays published while it has weapons, with a glow or
  -- none, so the hook reports weapons the game rebuilds under it. owner is an address; returns it as an integer.
  local function PublishGlowOwner(current, owner, entries)
    if not owner then return end
    local key = type(owner) == "number" and owner or sdk.to_int64(owner)
    if entries and #entries > 0 then
      -- Recorded first: a game exception while publish applies the targets raises after the DLL holds the owner. The
      -- update raises it at its end, so the rest of the pass still runs.
      glow_owners[key] = true
      if current then current[key] = true end
      local published, failure = pcall(native_glow.publish, key, entries)
      if not published then glow_failure = glow_failure or failure end
    elseif glow_owners[key] then
      native_glow.publish(key, {})
      glow_owners[key] = nil
    end
    return key
  end

  local function MatchGlowSpec(specs, part, weapon_id, set_name)
    for _, spec in ipairs(specs or {}) do
      if spec.part == part and spec.weapon_id == weapon_id then
        if GetSetTransmogValue(set_name, spec.equip_type) ~= SET_VALUE_HIDE then return spec end
        return nil
      end
    end
  end

  -- The publishers below decide each weapon's glow from live state once per owner: the party member or NPC with a preset
  -- it belongs to, no running preparation for the owner, and the glow of the part spec or equipment type its weapon ID
  -- matches, unless that equipment type is hidden. The hook checks the weapon itself on every write. Each returns the
  -- owner GameObject's address and the entries, or nothing when its checks fail.

  -- A world character's hand weapons and quiver, then whether they show the intensity when sheathed; char_info is nil for
  -- an NPC.
  local function WorldGlow(character, npc, char_info, set_name)
    if not CURRENT_SETTINGS.sets[set_name] or not Transmogify.HasWeaponGlow(set_name) then return end
    local facts = native_weapons.read(character:get_address(), npc, SLOT_MAIN_HAND, SLOT_OFF_HAND, "glow")
    if not facts.human or Transmogify.IsPreparingWeapons(Transmogify.WEAPON_CONTEXT.WORLD, facts.human) then return end
    local main, off, _, _, native_ids = Transmogify.GetWorldWeaponDataFromFacts(facts, npc)
    if native_ids == false then return end
    local sheathed = Transmogify.IsGlowSheathed(character, npc, char_info, set_name)
    -- The draconic flags set only each part's draconic state, not its glow or resources.
    local specs = Transmogify.GetWeaponPartSpecs(main, off, false, false, set_name, native_ids, sheathed)
    local entries = {}
    for _, slot in ipairs({"right", "left", "quiver"}) do
      local hand = facts[slot]
      if hand and hand.object and hand.mesh then
        local target = slot ~= "quiver" and MatchGlowSpec(specs, Transmogify.WEAPON_PARTS[slot], hand.id, set_name)
        entries[#entries + 1] = Transmogify.NewGlowEntry(hand.object, hand.mesh, target)
      end
    end
    return facts.owner, entries, sheathed
  end

  -- The world character with that CharacterID whose weapons Transmogify serves: a party member, or an NPC with a preset.
  -- Returns the character, whether it is an NPC, its char_info and its preset.
  local function FindWorldCharacter(id)
    local char_info, character = GetCharInfoById(id)
    if char_info then return character, false, char_info, GetSetNameByCharInfo(char_info) end
    local set_name = Transmogify.GetNPCSetName(id)
    if not CURRENT_SETTINGS.sets[set_name] then return nil end
    return Transmogify.GetNPCCharacter(id), true, nil, set_name
  end

  local function PublishWorldCharacter(current, id, character, npc, char_info, set_name)
    local owner, entries, sheathed = WorldGlow(character, npc, char_info, set_name)
    if not owner then
      local object = utils.GetGameObject(character)
      owner = object and object:get_address()
    end
    local key = PublishGlowOwner(current, owner, entries)
    if key and glow_owners[key] and Transmogify.PresetUsesSheathedGlow(set_name) and
      not Transmogify.GetAppliedDrawState(character, npc, char_info) then
      live_draw_glow[id] = {key = key, npc = npc, sheathed = sheathed}
    else
      live_draw_glow[id] = nil
    end
  end

  -- A menu model's weapons, for the party member with that CharacterID; builder is the model's address.
  local function GuiGlow(builder, id)
    local char_info, character = GetCharInfoById(id)
    if not character then return end
    local set_name = GetSetNameByCharInfo(char_info)
    if not CURRENT_SETTINGS.sets[set_name] or not Transmogify.HasWeaponGlow(set_name) or
      Transmogify.IsPreparingWeapons(Transmogify.WEAPON_CONTEXT.GUI, builder) then return end
    local facts = Transmogify.ReadMenuModel(character, builder)
    if not facts.owner or not facts.human then return end
    local main, off = Transmogify.GetWeaponDataFromFact(facts.main), Transmogify.GetWeaponDataFromFact(facts.off)
    local right = facts.right and facts.right.weapon and facts.right
    local left = facts.left and facts.left.weapon and facts.left
    local right_data = right and right.data
    local main_weapon = right_data and right_data.category == CAT_WEAPON and right or left
    if not main or not facts.display_main or facts.display_main ~= main._WeaponId or
      not main_weapon or main_weapon.id ~= main._WeaponId then main = nil end
    if not off or not facts.display_off or facts.display_off ~= off._WeaponId or
      not left or left.id ~= off._WeaponId then off = nil end
    local specs = Transmogify.GetWeaponPartSpecs(main, off, false, false, set_name, nil, false)
    local entries = {}
    for _, slot in ipairs({"right", "left", "quiver"}) do
      local part = facts[slot]
      if part and part.mesh then
        local target = nil
        if slot ~= "quiver" then target = MatchGlowSpec(specs, Transmogify.WEAPON_PARTS[slot], part.id, set_name) end
        entries[#entries + 1] = Transmogify.NewGlowEntry(part.object, part.mesh, target)
      end
    end
    return facts.owner, entries
  end

  -- The barber's edit model weapons. The hook checks the controller's equipment and the editor's apply and part-swap
  -- state on each write.
  local function BarberGlow()
    local facts = Transmogify.ReadBarber()
    if not facts.controller or not facts.barber or facts.no_equipment or not facts.model or not facts.objects or
      not facts.slot then return end
    local char_info = char_info_list[facts.slot + 1]
    local set_name = GetSetNameByCharInfo(char_info)
    if not CURRENT_SETTINGS.sets[set_name] or not Transmogify.HasWeaponGlow(set_name) or
      Transmogify.IsPreparingWeapons(Transmogify.WEAPON_CONTEXT.BARBER, facts.controller) or Transmogify.IsAppearanceBusy() or
      CURRENT_SETTINGS.hide_weapons_in_barber then return end
    local state = char_info.barber_glow
    if not state or state.controller ~= facts.controller or state.model ~= facts.model or
      state.needs_native_restore then return end
    if not facts.swapper then return end
    local main, off = Transmogify.GetWeaponDataFromFact(facts.main), Transmogify.GetWeaponDataFromFact(facts.off)
    local ids = facts.ids
    local barber = {controller = facts.controller, editor = facts.editor, swapper = facts.swapper}
    local entries = {}
    for _, part in ipairs(facts.objects) do
      local mesh = part and part.weapon and part.mesh
      if mesh then
        local weapon_id, is_left = part.id, part.left
        local slot
        if ids then
          if weapon_id == ids[3] then slot = "arrow"
          elseif weapon_id == ids[4] then slot = "quiver"
          elseif is_left and weapon_id == ids[2] then slot = "left"
          elseif weapon_id == ids[1] then slot = "right"
          elseif weapon_id == ids[2] then slot = "left" end
        end
        local equip_type, resources
        if slot and slot ~= "quiver" then
          if main and weapon_id == main._WeaponId then
            local hand = is_left and LEFT_HAND or RIGHT_HAND
            for _, candidate in ipairs(JOB_TO_WEAPON_EQUIP_INFO_TYPE_LIST[main:getJob()] or {}) do
              local info = EQUIPMENT_INFO[candidate]
              if info.slot == SLOT_MAIN_HAND and info.hand == hand then
                local appearance_id = GetTransmogId(GetSetTransmogValue(set_name, candidate)) or main._WeaponId
                local categories = ITEM_INFO_DIC[appearance_id]
                resources = categories and categories[main._EquipCategory]
                if resources then equip_type = candidate end
                break
              end
            end
          elseif off and weapon_id == off._WeaponId and off._EquipCategory == CAT_SHIELD then
            equip_type = EQUIPMENT_INFO_SHIELD
          elseif main and EquipmentIsBow(main) and facts.weared_job ~= 0 and ids and
            ids[2] == main._WeaponId and slot == "arrow" then
            for _, candidate in ipairs(JOB_TO_WEAPON_EQUIP_INFO_TYPE_LIST[main:getJob()] or {}) do
              if EQUIPMENT_INFO[candidate].slot == SLOT_MAIN_HAND then
                equip_type = candidate
                break
              end
            end
          end
        end
        local target
        if equip_type and GetSetTransmogValue(set_name, equip_type) ~= SET_VALUE_HIDE then
          target = {glow = Transmogify.GetWeaponGlowSettings(set_name, equip_type), resources = resources}
        end
        entries[#entries + 1] = Transmogify.NewGlowEntry(part.object, mesh, target, barber)
      end
    end
    return facts.model, entries
  end

  local function PublishWeaponGlow(party)
    Transmogify.glow_check_countdown = Transmogify.GLOW_CHECK.INTERVAL
    Transmogify.glow_check_requested = false
    world_glow_requests = {}
    local current = {}
    for i, char_info in ipairs(char_info_list) do
      local character = party[i]
      if character then
        PublishWorldCharacter(current, cm.getCharaID:call(character), character, false, char_info,
          GetSetNameByCharInfo(char_info))
      end
    end
    for key in pairs(CURRENT_SETTINGS.npcSets) do
      local id = tonumber(key)
      local set_name = id and Transmogify.GetNPCSetName(id)
      if id and not Transmogify.party_ids[id] and CURRENT_SETTINGS.sets[set_name] and Transmogify.HasWeaponGlow(set_name) then
        local character = Transmogify.GetNPCCharacter(id)
        if character then PublishWorldCharacter(current, id, character, true, nil, set_name) end
      end
    end
    -- Menu models are published while a menu pauses the game.
    if GuiManager:isPausedGUI() then
      for _, model in ipairs(YowaveUtils.menus.models()) do
        PublishGlowOwner(current, GuiGlow(model.builder, model.id))
      end
    end
    PublishGlowOwner(current, BarberGlow())
    for _, clone in ipairs(Transmogify.GetCinematicWeaponGlow() or {}) do
      PublishGlowOwner(current, clone.owner, clone.entries)
    end
    for key in pairs(glow_owners) do
      if not current[key] then
        native_glow.publish(key, {})
        glow_owners[key] = nil
      end
    end
  end

  local function PublishWorldGlowRequests()
    local requests = world_glow_requests
    world_glow_requests = {}
    for id in pairs(requests) do
      local character, npc, char_info, set_name = FindWorldCharacter(id)
      if character then PublishWorldCharacter(nil, id, character, npc, char_info, set_name) end
    end
  end

  -- Until the draw check applies a state, IsGlowSheathed follows the live draw state, which can flip between passes.
  local function CheckLiveDrawGlow()
    for id, watch in pairs(live_draw_glow) do
      local character, npc, char_info, set_name
      if glow_owners[watch.key] then character, npc, char_info, set_name = FindWorldCharacter(id) end
      if not character or npc ~= watch.npc then
        live_draw_glow[id] = nil
      elseif Transmogify.IsGlowSheathed(character, npc, char_info, set_name) ~= watch.sheathed then
        world_glow_requests[id] = true
      end
    end
  end

  -- The native glow hook's targets, reconciled from live state. At the start of an update everything is published again
  -- every GLOW_CHECK.INTERVAL updates, on request, and when the hook found a weapon it had no entry for under a published
  -- owner, such as one the game rebuilt; at its end, requests made during the update are published, a world
  -- character's alone. The end-of-update call returns the update's first glow failure, which the update raises last.
  function Transmogify.UpdateWeaponGlow(party, finishing)
    local reports, missing, failure = native_glow.poll()
    glow_failure = glow_failure or failure
    for _, key in ipairs(missing or {}) do Transmogify.ReportMissingGlow(key) end
    if not CURRENT_SETTINGS.enabled or not Transmogify.weapon_glow_in_use then
      Transmogify.ClearWeaponGlow()
    else
      if reports > 0 then Transmogify.RequestGlowCheck() end
      if not finishing then
        Transmogify.glow_check_countdown = Transmogify.glow_check_countdown - 1
        if Transmogify.glow_check_countdown <= 0 then Transmogify.RequestGlowCheck() end
        CheckLiveDrawGlow()
      end
      if Transmogify.glow_check_requested then
        PublishWeaponGlow(party)
      elseif next(world_glow_requests) then
        PublishWorldGlowRequests()
      end
    end
    if not finishing then return end
    failure, glow_failure = glow_failure, nil
    return failure
  end
end

sdk.hook(
  Transmogify.HOOKS.quiverSet,
  function(args)
    if not Transmogify.init_complete then
      return
    end
    local controller = sdk.to_managed_object(args[2])
    local character = controller.Chara
    if not character then
      return
    end

    local id = character:get_CharaID()
    local _, current_character = GetCharInfoById(id)
    if not current_character and Transmogify.IsNPCWeaponTarget(id) then current_character = Transmogify.GetNPCCharacter(id) end
    local human = GetCharacterHuman(character)
    if current_character ~= character or not human or human:get_QuiverController() ~= controller then
      return
    end

    local outgoing = controller.Quiver
    local incoming = sdk.to_managed_object(args[3])
    if not outgoing or not incoming or outgoing == incoming then
      return
    end

    local object = utils.GetGameObject(outgoing)
    if object then
      object:destroy(object)
    end
  end,
  function(retval)
    return retval
  end
)

sdk.hook(
  Transmogify.HOOKS.saveGameSaveData,
  function(args)
    for _, char_info in ipairs(char_info_list) do
      if char_info.settings_set ~= SETTINGS_SET_PLAYER then
        local character = char_info.character()
        if character then Transmogify.RestoreClothingForSave(character) end
      end
    end
    Transmogify.armor_check_countdown = Transmogify.ARMOR_CHECK.AFTER_SAVE
    if CURRENT_SETTINGS.pawn_shadow_ban_protection then
      local character = utils.GetMainPawn()
      TransmogArmors(character, SET_VALUE_NONE)
      Transmogify.RestoreWeaponsForSave(character)
      Transmogify.RequestWeaponCheck()
    end
  end,
  function(retval)
    return retval
  end
)

sdk.hook(
  Transmogify.HOOKS.loadGameSaveData,
  function(args)
  end,
  function(retval)
    Transmogify.game_loaded = true
    Transmogify.logic_warmup_frames = Transmogify.LOGIC_WARMUP_FRAMES
    return retval
  end
)

sdk.hook(
  Transmogify.HOOKS.checkDraconic,
  function(args)
  end,
  function(retval)
    if CURRENT_SETTINGS.hideDraconic then
      retval = false
    end
    return retval
  end
)

function Transmogify.HookWarfarerEquipment()
  local storage_type = sdk.find_type_definition("app.ItemDefine.StorageData")
  local BYREF_ADDRESS_MASK = 0x7fffffffffffffff

  local function FinishWarfarerEquipmentCheck(retval)
    local storage = thread.get_hook_storage()
    local eligible = storage.transmogify_warfarer_equipment_eligible
    storage.transmogify_warfarer_equipment_eligible = nil
    if eligible then return sdk.to_ptr(1) end
    return retval
  end

  for method, by_character in pairs({[Transmogify.HOOKS.isArisenEquipByCharacter] = true,
    [Transmogify.HOOKS.isArisenEquipById] = false}) do
    sdk.hook(method,
      function(args)
        local hook = thread.get_hook_storage()
        hook.transmogify_warfarer_equipment_eligible = false
        local player = utils.GetPlayer()
        if not IsWarfarer(player) then return end
        local player_id = player:get_CharaID()
        local item_storage = sdk.to_valuetype(sdk.to_int64(args[4]) & BYREF_ADDRESS_MASK, storage_type)
        if by_character then
          local character = sdk.to_managed_object(args[3])
          if utils.GetGameObject(character) then
            if character:get_CharaID() ~= player_id or not IsWarfarer(character) then return end
          elseif item_storage:call("get_CharaId()") ~= player_id then
            return
          end
        elseif (sdk.to_int64(args[3]) & 0xffffffff) ~= player_id then
          return
        end
        local item = item_storage:call("get_ItemData()")
        local weapon = item and item:get_WeaponParam()
        hook.transmogify_warfarer_equipment_eligible = weapon and
          (weapon._EquipCategory == CAT_WEAPON or weapon._EquipCategory == CAT_SHIELD)
      end,
      FinishWarfarerEquipmentCheck)
  end

  sdk.hook(Transmogify.HOOKS.isArisenAndSkillJob10,
    function(args)
      thread.get_hook_storage().transmogify_warfarer_equipment_eligible = IsWarfarer(utils.GetPlayer())
    end,
    FinishWarfarerEquipmentCheck)
end
Transmogify.HookWarfarerEquipment()

sdk.hook(
  Transmogify.HOOKS.setEquip,
  function(args)
  end,
  function(retval)
    ResetCharInfoListDraw()
    return retval
  end
)

local removeEquip_character = nil
sdk.hook(
  Transmogify.HOOKS.removeEquip,
  function(args)
    local character = sdk.to_managed_object(args[4])
    removeEquip_character = character
  end,
  function(retval)
    if removeEquip_character then
      local character = removeEquip_character
      removeEquip_character = nil
      local human = GetCharacterHuman(character)
      if not human then return retval end
      human:forceChangeDrawingWeapon(false)
      DestroyCharWeapons(character)

      if IsWarfarer(character) then
        local warfarer_manager = human:get_Job10WeaponManager()
        warfarer_manager:destroyWeapon()
      end
    end
    return retval
  end
)

sdk.hook(
  Transmogify.HOOKS.onChangeArisenEquip,
  function(args)
    if not Transmogify.init_complete then
      return
    end

    local character = utils.GetPlayer()
    local manager = sdk.to_managed_object(args[2])
    local human = manager and manager.Human
    local character_object = utils.GetGameObject(character)
    local human_object = utils.GetGameObject(human)
    if not character_object or not human_object or sdk.to_ptr(character_object) ~= sdk.to_ptr(human_object) or
      human:get_Job10WeaponManager() ~= manager then
      return
    end

    for _, holder in pairs({manager.WeaponHolder, manager.SameWeaponHolder}) do
      local slots = holder.Additionals
      if slots then
        local stale_ids = {}
        local protected_ids = {}
        local slots_values, slots_count = utils.GetLuaArray(slots)
        for i = 0, slots_count - 1 do
          local slot = slots_values[i + 1]
          local weapon_id = slot:get_WeaponID()
          if slot.IsStartPrepare or slot:call("isPreparing()") then
            protected_ids[weapon_id] = true
            protected_ids[slot:get_PreparingWeaponID()] = true
          elseif weapon_id ~= 0 then
            if utils.GetGameObject(slot:get_Weapon()) then
              protected_ids[weapon_id] = true
            else
              stale_ids[weapon_id] = true
            end
          end
        end

        for weapon_id in pairs(stale_ids) do
          if not protected_ids[weapon_id] then
            manager:call("removeWeapon(app.WeaponAndItemHolder, app.WeaponID)", holder, weapon_id)
          end
        end
      end
    end
  end,
  function(retval)
    return retval
  end
)

do
  local PROVIDER_ID = 50
  local DATA_CONTAINER_ID = 0
  local BODY_EFFECT_ID = 0
  local FOLLOW_PARENT = 0
  local CREATE_EFFECT_METHOD = "createEffectAutoDestroy(via.effect.script.EffectManager.CreateEffectParam)"

  local function CreateWarfarerEffect(oem, target, element_id)
    local object = utils.GetGameObject(target)
    local creator = utils.GetGameObject(oem)
    if not object or not creator then return end
    local data = oem:call("getStandardData(System.UInt32, System.Int32, System.Boolean)",
      PROVIDER_ID, DATA_CONTAINER_ID, false)
    if not utils.GetGameObject(data) then return end
    local manager = sdk.find_type_definition("via.effect.script.EffectSingleton`1<via.effect.script.EffectManager>")
      :get_method("get_Instance"):call(nil)
    if not utils.GetGameObject(manager) then return end
    local element
    for index = 0, data:getElementCount() - 1 do
      local candidate = data:getElement(index)
      if candidate and candidate:get_id() == element_id then element = candidate end
    end
    if not element then return end
    local rotation = element:get_rotation()
    if element.RelationType ~= FOLLOW_PARENT or element.ParentDegree ~= 0 or
      rotation.x ~= 0 or rotation.y ~= 0 or rotation.z ~= 0 then
      error("Warfarer effect has unsupported placement: " .. element_id)
    end
    local values, count = utils.GetLuaArray(element.ExternParameters)
    local externs = sdk.create_managed_array(sdk.find_type_definition("via.effect.ExternParameter"), count):add_ref()
    for index = 1, count do externs[index - 1] = values[index] end
    local parameters = sdk.create_instance("via.effect.script.EffectManager.CreateEffectParam"):add_ref()
    parameters:call(".ctor()")
    parameters.creator = creator
    parameters.effectData = element
    parameters.followTarget = object
    parameters.followJoint = element:get_jointName()
    parameters.externParams = externs
    parameters.pos = element:get_offset()
    parameters.rotation = sdk.find_type_definition("via.Quaternion"):get_field("Identity"):get_data(nil)
    parameters.materialId = 0xffffffff
    local success, container = pcall(manager.call, manager, CREATE_EFFECT_METHOD, parameters)
    if not success then
      utils.Log("[" .. modname .. "] Warfarer effect creation failed: " .. tostring(container))
      return
    end
    return container and container:add_ref()
  end

  sdk.hook(Transmogify.HOOKS.generateEffect,
    function(args)
      local controller = sdk.to_managed_object(args[2])
      local weapon = sdk.to_managed_object(args[3])
      local element_id = sdk.to_int64(args[4]) & 0xFFFFFFFF
      controller:set_Effect(CreateWarfarerEffect(controller.OEM, weapon, element_id))
      controller.IsForceEnd = false
      return sdk.PreHookResult.SKIP_ORIGINAL
    end,
    function(retval) return retval end
  )

  sdk.hook(Transmogify.HOOKS.generateBodyEffect,
    function(args)
      local oem = sdk.to_managed_object(args[2]).OEM
      local target = oem and (oem.DefaultFollowGameObject or utils.GetGameObject(oem))
      CreateWarfarerEffect(oem, target, BODY_EFFECT_ID)
      return sdk.PreHookResult.SKIP_ORIGINAL
    end,
    function(retval) return retval end
  )
end

-- Warfarer Rearmament
function Transmogify_Finished_Rearm()
  return finished_rearm
end

function Transmogify_Set_Finished_Rearm()
  finished_rearm = false
end

sdk.hook(
  Transmogify.HOOKS.requestJob10CustomSkill,
  function(args)
    local player_char_info = char_info_list[CHAR_INFO_PLAYER_INDEX]
    local character = utils.GetPlayer()
    local human = GetCharacterHuman(character)
    if not human then return sdk.PreHookResult.CALL_ORIGINAL end
    if not Transmogify.HasWorldWeaponPreparation(character) and not warfarer_rearm_pending and
      not (Transmogify_Warfarer and Transmogify_Warfarer.rearm_character) then
      warfarer_rearm_pending = true
      weapon_drawed_on_rearm = character:get_IsDrawedWeapon()
      if Transmogify_Warfarer_Started then
        Transmogify_Warfarer_Weapon_Drawed(weapon_drawed_on_rearm, character)
      end
      character:get_HumanActionSelector():cancelUpperBodyAction()
      local QuiverController = human:get_QuiverController()

      DestroyCharWeapons(character)

      local warfarer_manager = human:get_Job10WeaponManager()
      warfarer_manager:disappearWeapon(character:get_RightWeapon())
      warfarer_manager:disappearWeapon(character:get_LeftWeapon())
      warfarer_manager:disappearWeapon(QuiverController.Quiver)
      warfarer_manager:destroyWeapon()

      cm.setNextArisenWeapon(ItemManager)
      human:get_ExSkillChecker():updateExSkillsWithInventory()
      human.EquipmentAbility:updateWithInventory()
      RequestWeaponTransmog(player_char_info, character)

      warfarer_manager:generateBodyEffect()
      if not Transmogify_Warfarer_Started then
        human:get_Job10ActionCtrl():consumeStaminaAndStartReduceStaminaRecover()
        human:forceChangeDrawingWeapon(false)
      end

      finished_rearm = true
      player_char_info.draw_state = nil
      Transmogify.draw_check_countdown = Transmogify.DRAW_CHECK.AFTER_REARM
    end
    return sdk.PreHookResult.SKIP_ORIGINAL
  end,
  function(retval)
    if finished_rearm then
      if not Transmogify_Warfarer_Started then
        finished_rearm = false
      end
      local character = utils.GetPlayer()
      if not character then
        return retval
      end
      local player_char_info = char_info_list[CHAR_INFO_PLAYER_INDEX]
      if not Transmogify.HasWorldWeaponPreparation(character) then
        RequestWeaponTransmog(player_char_info, character)
      end
    end

    return retval
  end
)

sdk.hook(
  Transmogify.HOOKS.charaEditChangeEquip,
  nil,
  function(retval)
    if Transmogify.init_complete then
      RefreshBarberTransmog()
    end
    return retval
  end
)

sdk.hook(
  Transmogify.HOOKS.charaEditInstantiateWeapon,
  nil,
  function(retval)
    if Transmogify.init_complete then
      RefreshBarberTransmog()
    end
    return retval
  end
)

-- GUI clone weapon
sdk.hook(
  Transmogify.HOOKS.reqEquipWeapon,
  function(args)
    local mBuilder = sdk.to_managed_object(args[2])
    if not mBuilder then
      return
    end
    local part_swapper = utils.GetObjectComponent(mBuilder, "app.PartSwapper")
    local char_info = nil
    local character = nil

    if part_swapper then
      local char_id = part_swapper:get_CharacterID()
      char_info, character = GetCharInfoById(char_id)
    end

    if char_info then Transmogify.RequestGUICheck() end

    if character and CURRENT_SETTINGS.hideDraconic then
      args[4] = false
    end
  end,
  function(retval)
    return retval
  end
)

sdk.hook(
  Transmogify.HOOKS.menuFaceSetupEquip,
  function(args)
    local request = Transmogify.menu_face_refresh_request
    if not request or request.stage ~= "queued" then
      return
    end

    if not Transmogify.IsMenuFaceRefreshRequestCurrent(request) then
      request.retry = true
      return
    end

    local menu_face = sdk.to_managed_object(args[2])
    if sdk.to_ptr(menu_face) ~= sdk.to_ptr(request.menu_face) then
      return
    end

    local capture_data = menu_face and menu_face:get_field("CaptureData")
    if not capture_data or capture_data:get_field("CharaId") ~= request.chara_id then
      return
    end

    local model = capture_data:get_field("Model")
    local mock_builder = model and model:get_field("Builder")
    if not mock_builder then
      request.retry = true
      return
    end

    request.mock_builder = mock_builder
    request.stage = "setup"
  end,
  function(retval)
    local request = Transmogify.menu_face_refresh_request
    if not request or request.stage ~= "setup" then
      return retval
    end

    if not Transmogify.IsMenuFaceRefreshRequestCurrent(request) then
      request.retry = true
    end

    for equip_category, _ in pairs(request.target_params) do
      if not request.replaced[equip_category] then
        request.retry = true
        break
      end
    end
    request.stage = "waiting_for_capture"
    return retval
  end
)

sdk.hook(
  Transmogify.HOOKS.reqEquipArmor,
  function(args)
    local storage = thread.get_hook_storage()
    storage.transmogify_gui_armor = nil
    local mock_builder = sdk.to_managed_object(args[2])
    if not mock_builder then return end
    local builder_part_swapper = mock_builder:get_PartSwapper()
    local armor_param = sdk.to_managed_object(args[3])
    local menu_face_request = Transmogify.menu_face_refresh_request
    if armor_param and menu_face_request and menu_face_request.stage == "setup" then
      if not Transmogify.IsMenuFaceRefreshRequestCurrent(menu_face_request) then
        menu_face_request.retry = true
      elseif sdk.to_ptr(mock_builder) == sdk.to_ptr(menu_face_request.mock_builder) then
        local equip_category = armor_param._EquipCategory
        local target_param = menu_face_request.target_params[equip_category]
        if target_param and not menu_face_request.replaced[equip_category] then
          args[3] = sdk.to_ptr(target_param)
          menu_face_request.replaced[equip_category] = true
        end
      end
    end
    local char_info, character
    if builder_part_swapper then
      char_info, character = GetCharInfoById(builder_part_swapper:get_CharacterID())
    end
    if character then
      storage.transmogify_gui_armor = {builder = mock_builder, character = character, set_name = GetSetNameByCharInfo(char_info)}
      if CURRENT_SETTINGS.hideDraconic then args[4] = false end
    end
  end,
  function(retval)
    local storage = thread.get_hook_storage()
    local request = storage.transmogify_gui_armor
    storage.transmogify_gui_armor = nil
    if request then Transmogify.ApplyGUIArmor(request.builder, request.character, request.set_name) end
    return retval
  end
)

sdk.hook(
  Transmogify.HOOKS.mockupRemoveEquip,
  function(args)
    local storage = thread.get_hook_storage()
    storage.transmogify_gui_remove_armor = nil
    local builder = sdk.to_managed_object(args[2])
    local swapper = builder and builder:get_PartSwapper()
    local char_info, character
    if swapper then char_info, character = GetCharInfoById(swapper:get_CharacterID()) end
    if character then
      storage.transmogify_gui_remove_armor = {builder = builder, character = character, set_name = GetSetNameByCharInfo(char_info)}
    end
  end,
  function(retval)
    local storage = thread.get_hook_storage()
    local request = storage.transmogify_gui_remove_armor
    storage.transmogify_gui_remove_armor = nil
    if request then Transmogify.ApplyGUIArmor(request.builder, request.character, request.set_name) end
    return retval
  end
)

-- this code runs when the user is in control
-- as such one can use it to check if the game is paused or the menu is open
sdk.hook(
  Transmogify.HOOKS.setAxisL,
  function(args)
    isPaused = false
  end,
  function(retval)
    return retval
  end
)

utils.Log("[" .. modname .. "] " .. version .. " script loaded")

