local NATIVE_NULL = "_*nil*_"

local function Log(...)
  local message = ""
  for i = 1, select("#", ...) do
    message = message .. tostring(select(i, ...))
  end
  log.info(message)
end

local function LogD(...)
  local message = ""
  for i = 1, select("#", ...) do
    message = message .. tostring(select(i, ...))
  end
  log.debug(message)
end

local function ToFloat(value)
  return value + 0.0
end

local function SetWeaponScale(weapon, scale)
  weapon:set_Scale(ToFloat(scale))
end

local function GetSize(size, min, max, step)
  if size < min then size = min end
  if size > max then size = max end

  return math.floor(size / step) * step
end

-- Colon calls run the object's own get_Valid and get_GameObject: some components redeclare get_Valid, and non-component
-- game types declare both.
local function IsInvalidObject(object)
  return not object:get_Valid()
end

local function GameObjectOfObject(object)
  return object:get_GameObject()
end

local function GetGameObject(component)
  local result = nil

  if component then
    if component:get_type_definition():get_name() == "GameObject" then
      result = component
    else
      local valid_success, invalid = pcall(IsInvalidObject, component)
      if valid_success and invalid then
        return nil
      end

      local success, game_object = pcall(GameObjectOfObject, component)
      if success then
        result = game_object
      end
    end
  end

  return result
end

local component_definition = sdk.find_type_definition("via.Component")
local component_valid = component_definition:get_method("get_Valid")
local component_game_object = component_definition:get_method("get_GameObject")
local game_object_component = sdk.find_type_definition("via.GameObject"):get_method("getComponent(System.Type)")
assert(component_valid and component_game_object and game_object_component,
  "via.Component.get_Valid/get_GameObject or via.GameObject.getComponent is missing")

local function IsInvalidComponent(component)
  return not component_valid:call(component)
end

local function ComponentGameObjectOf(component)
  return component and component_game_object:call(component)
end

-- GetGameObject through via.Component's methods looked up once, only for components whose type does not redeclare
-- get_Valid, such as app.Character, app.Human, app.Weapon, via.render.Mesh and via.Transform; pass anything else to
-- GetGameObject.
local function ComponentGameObject(component)
  if not component then return nil end
  local checked, invalid = pcall(IsInvalidComponent, component)
  if checked and invalid then return nil end
  local found, object = pcall(ComponentGameObjectOf, component)
  if found then return object end
  return nil
end

local function GetTypeName(object)
  local type = object:get_type_definition();
  return type:get_full_name()
end

local function GetTypeInfo(typeName)
  local RETypeDefinition = sdk.find_type_definition(typeName)
  local info = ""
  if RETypeDefinition ~= nil then
    info = "\r\n=== " .. RETypeDefinition:get_full_name() .. " Methods" .. " ===\r\n"
    local methods = RETypeDefinition:get_methods()
    for i, REMethodDefinition in pairs(methods) do
      local methodReturnType = REMethodDefinition:get_return_type()
      local methodReturnTypeName = ""
      if methodReturnType ~= nil then
        methodReturnTypeName = methodReturnType:get_name()
      end
      local methodName = REMethodDefinition:get_name()
      local methodSig = i .. ": " .. methodReturnTypeName .. " " .. methodName

      local methodParamTypes = REMethodDefinition:get_param_types()
      local methodParamNames = REMethodDefinition:get_param_names()

      local methodParams = ""
      for j, paramName in ipairs(methodParamNames) do
        if methodParams ~= "" then
          methodParams = methodParams .. ","
        end
        methodParams = methodParams .. methodParamTypes[j]:get_full_name() .. " " .. paramName
      end

      methodSig = methodSig .. "(" .. methodParams .. ")"

      info = info .. methodSig .. "\r\n"
    end

    info = info .. "\r\n"
    info = info .. "--- " .. RETypeDefinition:get_full_name() .. " Fields" .. " ---\r\n"
    local fields = RETypeDefinition:get_fields()

    if fields then
      for i, field in ipairs(fields) do
        info = info .. i .. ": " .. field:get_type():get_full_name() .. " " .. field:get_name() .. "\r\n"
      end
    end
  end

  return info
end

local function GetObjectFields(REManagedObject, definition)
  local t = definition or REManagedObject:get_type_definition()
  local info = "\r\n=== " .. t:get_full_name() .. " ===\r\n"
  local fields = t:get_fields()
  local errors = {}
  for i, field in ipairs(fields) do
    if field then
      local name = field:get_name()
      local type_name = field:get_type():get_full_name()
      local success, raw_value = pcall(function() return field:get_data(REManagedObject) end)
      if not success then
        errors[#errors + 1] = {field = name, type = type_name, error = tostring(raw_value)}
        raw_value = "<unreadable: " .. tostring(raw_value) .. ">"
      end
      info = info ..
        i .. ": " .. type_name .. " " .. name .. " = " .. tostring(raw_value) .. "\r\n"
    end
  end
  return info, errors
end

local function GetTypeFields(typeName)
  local info = ""
  local t = sdk.find_type_definition(typeName)
  info = info .. "\r\n=== " .. t:get_full_name() .. " ===\r\n"
  if not t then return {} end

  local fields = t:get_fields()
  local enum = {}

  for i, field in ipairs(fields) do
    local name = field:get_name()
    local raw_value = field:get_data(nil)

    info = info ..
      i .. ": " .. field:get_type():get_full_name() .. " " .. name .. " = " .. tostring(raw_value) .. "\r\n"

    enum[name] = raw_value
  end

  return info
end

local function GetObjectInfo(REManagedObject)
  return GetTypeInfo(REManagedObject:get_type_definition():get_full_name())
end

local function GetMethod(obj, methodSig)
  return obj:get_type_definition():get_method(methodSig)
end

local function GetEnumDic(typeName)
  local t = sdk.find_type_definition(typeName)
  if not t then return {} end

  local fields = t:get_fields()
  local key_value_dic = {}
  local value_key_dic = {}
  local key_list = {}
  for i, field in ipairs(fields) do
    if field then
      local key = tostring(field:get_name())
      local value = field:get_data(nil)
      key_value_dic[key] = value
      if value then
        value_key_dic[value] = key
      end
      table.insert(key_list, key)
    end
  end

  return key_value_dic, value_key_dic, key_list
end

local function GetEnumVal(typeName, _fieldName)
  local t = sdk.find_type_definition(typeName)
  if not t then return {} end

  local fields = t:get_fields()
  local result = nil
  for i, field in ipairs(fields) do
    if field then
      local fieldName = field:get_name()
      if fieldName == _fieldName then
        result = field:get_data(nil)
        break
      end
    end
  end

  return result
end

local function CreateResource(resource_type, resource_path)
  local new_resource = resource_path and sdk.create_resource(resource_type, resource_path)
  if not new_resource then return end
  new_resource = new_resource:add_ref()
  return new_resource:create_holder(resource_type .. "Holder"):add_ref()
end

local function GetCurrentScene()
  local manager = sdk.get_native_singleton("via.SceneManager")
  if not manager then return nil end
  return sdk.call_native_func(manager, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
end

local function ReadSlotStorage(equip_data, slot)
  return equip_data:call("get(app.EquipData.SlotEnum)", slot)
end

local function GetSlotStorageData(equip_data, slot)
  if not equip_data then return nil end
  local success, storage_data = pcall(ReadSlotStorage, equip_data, slot)
  if not success or not storage_data or storage_data._StorageId == 0 or not storage_data._ItemData then
    return nil
  end
  return storage_data
end

local function GetSlotItemData(equip_data, slot)
  local storage_data = GetSlotStorageData(equip_data, slot)
  return storage_data and storage_data._ItemData
end

local function GetWeaponParam(equip_data, slot)
  local storage_data = GetSlotStorageData(equip_data, slot)
  local item_data = storage_data and storage_data._ItemData
  return item_data and item_data:get_WeaponParam() or nil, storage_data
end

local function GetWeaponItemData(equip_data, slot)
  local weapon_item_data, storage_data = GetWeaponParam(equip_data, slot)
  if not weapon_item_data then
    return nil, storage_data, nil
  end
  local weapon_element = weapon_item_data._Element
  local temp_element = storage_data._TempElement
  if temp_element and temp_element:get_field("_HasValue") then
    weapon_element = temp_element:get_field("_Value")
  end
  return weapon_item_data, storage_data, weapon_element
end

-- The game's hash of names such as material variables and prebake keys: MurmurHash3 x86_32 of the UTF-16LE text with
-- seed 0xffffffff.
local function MurmurHash(text)
  local bytes = {}
  for index = 1, #text do
    bytes[#bytes + 1] = text:byte(index)
    bytes[#bytes + 1] = 0
  end
  local hash, blocks = 0xFFFFFFFF, #bytes // 4
  for block = 0, blocks do
    local first, k = block * 4, 0
    for offset = math.min(3, #bytes - first - 1), 0, -1 do k = (k << 8) | bytes[first + offset + 1] end
    if block < blocks or #bytes % 4 > 0 then
      k = (k * 0xcc9e2d51) & 0xFFFFFFFF
      k = ((k << 15) | (k >> 17)) & 0xFFFFFFFF
      hash = hash ~ ((k * 0x1b873593) & 0xFFFFFFFF)
      if block < blocks then
        hash = ((hash << 13) | (hash >> 19)) & 0xFFFFFFFF
        hash = (hash * 5 + 0xe6546b64) & 0xFFFFFFFF
      end
    end
  end
  hash = hash ~ #bytes
  hash = ((hash ~ (hash >> 16)) * 0x85ebca6b) & 0xFFFFFFFF
  hash = ((hash ~ (hash >> 13)) * 0xc2b2ae35) & 0xFFFFFFFF
  return hash ~ (hash >> 16)
end

local MATERIAL_FLOAT, MATERIAL_FLOAT4 = 1, 4
local MISSING_MATERIAL_VARIABLE = 0xFF
local mesh_definition = sdk.find_type_definition("via.render.Mesh")
local material_calls = {
  count = mesh_definition:get_method("get_MaterialNum"),
  variable_count = mesh_definition:get_method("getMaterialVariableNum"),
  variable_index = mesh_definition:get_method("getMaterialVariableIndex(System.UInt32, System.UInt32)"),
  variable_type = mesh_definition:get_method("getMaterialVariableType"),
}
assert(material_calls.count and material_calls.variable_count and material_calls.variable_index and
  material_calls.variable_type, "via.render.Mesh material variable methods are missing")

-- The variable's index in a material below get_MaterialNum when it exists with the expected type, else nil. The game's
-- lookup covers at most 255 variables and variable_count (getMaterialVariableNum) is the low byte of the real count, so
-- an oversized material can only miss variables here, never yield an index past its table.
local function FindMaterialVariable(mesh, material, variable_count, hash, kind)
  local variable = material_calls.variable_index:call(mesh, material, hash)
  if variable == MISSING_MATERIAL_VARIABLE or variable >= variable_count or
    material_calls.variable_type:call(mesh, material, variable) ~= kind then return nil end
  return variable
end

local WEAPON_GLOW = {
  INTENSITY = "Enchant_Emissive_Intensity", COLOR1 = "Enchant_Color1", COLOR2 = "Enchant_Color2",
}
local WEAPON_GLOW_VARIABLES = {
  {name = WEAPON_GLOW.INTENSITY, kind = MATERIAL_FLOAT},
  {name = WEAPON_GLOW.COLOR1, kind = MATERIAL_FLOAT4},
  {name = WEAPON_GLOW.COLOR2, kind = MATERIAL_FLOAT4},
}
for _, glow in ipairs(WEAPON_GLOW_VARIABLES) do glow.hash = MurmurHash(glow.name) end

-- Every weapon glow variable with its expected type, by material: {material, variable, name, kind}.
local function GetGlowVariables(mesh)
  local found = {}
  for material = 0, material_calls.count:call(mesh) - 1 do
    local variable_count = material_calls.variable_count:call(mesh, material)
    for _, glow in ipairs(WEAPON_GLOW_VARIABLES) do
      local variable = FindMaterialVariable(mesh, material, variable_count, glow.hash, glow.kind)
      if variable then found[#found + 1] = {material = material, variable = variable, name = glow.name, kind = glow.kind} end
    end
  end
  return found
end

local function GetMeshGlow(mesh)
  return YowaveUtils.glow.get(mesh:get_address(), WEAPON_GLOW_VARIABLES)
end

local function SetMeshGlow(mesh, glow_info)
  YowaveUtils.glow.set(mesh:get_address(), WEAPON_GLOW_VARIABLES, glow_info)
end

-- Weapon.start binds blood to the material and variable indices of the mesh it has at that moment, and nothing rebinds
-- them after a mesh or material change; stale indices send the native blood write past the mesh's material tables.
local function RefreshWeaponBlood(weapon)
  return YowaveUtils.weapons.refresh_blood(weapon:get_address())
end

local component_types = {}

local function GetObjectComponent(obj, ComponentType)
  local component_type = component_types[ComponentType]
  if not component_type then
    component_type = sdk.typeof(ComponentType)
    if component_type then
      component_type = component_type:add_ref()
      component_types[ComponentType] = component_type
    end
  end
  local GameObject = GetGameObject(obj)
  local result = nil
  if GameObject and component_type then
    result = game_object_component:call(GameObject, component_type)
  end
  return result
end

-- via.Transform.find returns the first descendant with that name, searched depth-first, in one native call.
local function FindChild(obj, name)
  local GameObject = GetGameObject(obj)
  local child = GameObject and GameObject:get_Transform():find(name)
  return child and GetGameObject(child)
end

local function GetLuaArray(collection)
  local array = {}
  local iterator = collection:GetEnumerator()
  local index = 1
  while iterator:call("MoveNext") do
    array[index] = iterator:call("get_Current")
    index = index + 1
  end
  return array, index - 1
end

local function GetLuaEnumArray(collection)
  local array, count = GetLuaArray(collection)
  for i = 1, count do
    if type(array[i]) ~= "number" then array[i] = array[i]:get_field("value__") end
  end
  return array, count
end

local function GetObjectComponents(obj)
  local GameObject = GetGameObject(obj)
  if not GameObject then return {}, 0 end
  return GetLuaArray(GameObject:get_Components())
end

local function LogObjectCompontents(GameObject)
  local components, count = GetObjectComponents(GameObject)
  for i = 1, count do
    if components[i] then
      Log(GetObjectInfo(components[i]))
    end
  end
end

local function GetLuaDic(managed_dic)
  local lua_dic = {}
  local iterator = managed_dic:GetEnumerator()
  while iterator:call("MoveNext") do
    local entry = iterator:call("get_Current")
    local value = entry:call("get_Value")
    if value == nil then value = NATIVE_NULL end
    lua_dic[entry:call("get_Key")] = value
  end

  return lua_dic
end

local NPC_TIER_S = assert(GetEnumDic("app.CharacterData.UniqueNPCDefine").S, "Missing NPC tier S in app.CharacterData.UniqueNPCDefine")

-- NPC-pawn records are pawns except at tier S, which holds story companions such as Dark Arisen's Eir.
local function GetNpcCatalogIdentity(id, entry)
  if not entry or entry == NATIVE_NULL then return nil, 0 end
  local normal = entry:get_Normal()
  if not normal then return nil, 0 end
  local records, count = GetLuaArray(normal)
  local names, seen, variants = {}, {}, {}
  local pawn_count = 0
  for index = 1, count do
    local record = records[index]
    if record then
      if record:get__NameIsMyPawn() or (record:get_isNPCPawn() and record.Unique ~= NPC_TIER_S) then
        pawn_count = pawn_count + 1
      else
        local name = record:get_Name() or ""
        if name ~= "" and not seen[name] then names[#names + 1], seen[name] = name, true end
        variants[#variants + 1] = {id = record.ID, name = name, tier = record.Unique, sub_npc = record._SubNPC,
          appearance = record:get_AppearanceID(), costume = record:get_CostumeID()}
      end
    end
  end
  if #variants == 0 then return nil, pawn_count end
  table.sort(names)
  return {id = id, names = names, variants = variants}, pawn_count
end

local function Explode(str, seperator)
  local string_list = {}
  local tmp = "";
  for i = 1, #str do
    local c = str:sub(i, i)
    if (c == seperator and tmp ~= "") then
      table.insert(string_list, tmp)
      tmp = "";
    else
      tmp = tmp .. c;
      if i == #str then
        table.insert(string_list, tmp)
      end
    end
  end

  return string_list;
end

-- trim string
local function Trim(str)
  str = tostring(str)
  local str_start = 0
  local str_end = 0

  for i = 0, #str do
    local c = str:sub(i, i)
    if c ~= " " and c ~= "" then
      str_start = i
      break
    end
  end

  for i = #str, 1, -1 do
    local c = str:sub(i, i)
    if c ~= " " and c ~= "" then
      str_end = i
      break
    end
  end

  return str:sub(str_start, str_end)
end

-- Item and skill names can hold message tags that the game's menus expand: <REF key> stands for the text of the message
-- named key, and <EQABI gender_number> marks where an appraised Relic item's ability adjective goes, which an item type
-- without an appraisal has none of.
local MESSAGE_TAG = {REF = "<REF ", ABILITY = "<EQABI ", CLOSE = ">", MAX_DEPTH = 8}
local message_type = assert(sdk.find_type_definition("via.gui.message"), "Missing via.gui.message")
local message_methods = {
  get_guid = assert(message_type:get_method("getGuidByName(System.String)"), "Missing via.gui.message.getGuidByName"),
  has_guid = assert(message_type:get_method("isExistGuid(System.Guid)"), "Missing via.gui.message.isExistGuid"),
  get_text = assert(message_type:get_method("get(System.Guid)"), "Missing via.gui.message.get"),
}

local function ExpandMessageRefs(text, depth)
  if depth > MESSAGE_TAG.MAX_DEPTH then return nil end
  local parts, position = {}, 1
  while true do
    local start = string.find(text, MESSAGE_TAG.REF, position, true)
    local close = start and string.find(text, MESSAGE_TAG.CLOSE, start + #MESSAGE_TAG.REF, true)
    if not close then break end
    local guid = message_methods.get_guid:call(nil, string.sub(text, start + #MESSAGE_TAG.REF, close - 1))
    if not message_methods.has_guid:call(nil, guid) then return nil end
    local referenced = ExpandMessageRefs(message_methods.get_text:call(nil, guid) or "", depth + 1)
    if not referenced then return nil end
    parts[#parts + 1] = string.sub(text, position, start - 1)
    parts[#parts + 1] = referenced
    position = close + 1
  end
  parts[#parts + 1] = string.sub(text, position)
  return table.concat(parts)
end

-- The text with every <REF key> replaced by its message in the current language and the ability tags removed; nil when
-- a referenced message is missing, references nest deeper than MESSAGE_TAG.MAX_DEPTH or no text remains.
local function ExpandMessageTags(text)
  local expanded = ExpandMessageRefs(text, 0)
  if not expanded then return nil end
  while true do
    local start = string.find(expanded, MESSAGE_TAG.ABILITY, 1, true)
    local close = start and string.find(expanded, MESSAGE_TAG.CLOSE, start + #MESSAGE_TAG.ABILITY, true)
    if not close then break end
    local after = close + 1
    if string.sub(expanded, start - 1, start - 1) == " " and string.sub(expanded, after, after) == " " then after = after + 1 end
    expanded = string.sub(expanded, 1, start - 1) .. string.sub(expanded, after)
  end
  expanded = Trim(expanded)
  if expanded == "" then return nil end
  return expanded
end

local function NormalizeFileName(name, max_length)
  if type(name) ~= "string" then return nil end
  name = Trim(name)
  if name == "" or #name > (max_length or 255) or name:sub(-1) == "." or name:find("..", 1, true) then return nil end
  local forbidden = '<>:"/\\|?*'
  for index = 1, #name do
    if name:byte(index) < 32 or forbidden:find(name:sub(index, index), 1, true) then return nil end
  end
  local stem = name:upper()
  local dot = stem:find(".", 1, true)
  if dot then stem = stem:sub(1, dot - 1) end
  if stem == "CON" or stem == "PRN" or stem == "AUX" or stem == "NUL" or
    (stem:sub(1, 3) == "COM" or stem:sub(1, 3) == "LPT") and
    #stem == 4 and stem:sub(4) >= "1" and stem:sub(4) <= "9" then return nil end
  return name
end

local function FileOperation(operation, ...)
  local paths = {...}
  for index = 1, select("#", ...) do
    local path = paths[index]
    assert(type(path) == "string" and path ~= "", "Expected a path relative to reframework/data.")
    path = path:gsub("\\", "/")
    if path:sub(-1) == "/" then path = path:sub(1, -2) end
    assert(path ~= "" and path:sub(1, 1) ~= "/" and not path:find("//", 1, true), "Expected a path relative to reframework/data.")
    for _, component in ipairs(Explode(path, "/")) do
      assert(NormalizeFileName(component) == component, "Invalid file path component: " .. component)
    end
    paths[index] = path
  end
  local result, failure = YowaveUtils.files[operation](table.unpack(paths))
  assert(result ~= nil, failure)
  return result
end

local function FileExists(path)
  return FileOperation("exists", path)
end

local function RenameFile(source, destination)
  return FileOperation("rename", source, destination)
end

local function DeleteFile(path)
  return FileOperation("delete", path)
end

local function OpenFolder(path)
  return FileOperation("open_folder", path)
end

local function PadLeft(str, pad, length)
  str = tostring(str);
  pad = tostring(pad);
  if #str < length then
    while #str < length do
      str = pad .. str;
    end
  end
  return str;
end

local function PadRight(str, pad, length)
  str = tostring(str);
  pad = tostring(pad);
  if #str < length then
    for i = (length - #str), length - 1 do
      str = str .. pad;
    end
  end
  return str;
end

-- shallow copy of tables
local function ShallowCopy(t)
  local newT = {};
  for k, v in pairs(t) do
    newT[k] = v;
  end
  return newT;
end

-- string.find uses patterns to find using raw use the below
local function StringFindRaw(str, search)
  return string.find(str, search, 1, true);
end

-- return table ordered by keys
local function PairsByKeys(dic, sort_func)
  local key_list = {}
  for key, value in pairs(dic) do table.insert(key_list, key) end
  table.sort(key_list, sort_func)
  local i = 0          -- iterator variable
  local iter = function() -- iterator function
    i = i + 1
    if key_list[i] == nil then
      return nil
    else
      return key_list[i], dic[key_list[i]]
    end
  end
  return iter
end

local function Round(number, places)
  if not places then
    places = 2
  end
  places = tostring(places)
  return tonumber(string.format("%." .. places .. "f", number))
end

-- dump value
local function Dump(o)
  if type(o) == 'table' then
    local s = ''
    for k, v in pairs(o) do
      if type(k) ~= 'number' then k = '"' .. k .. '"' end
      if s ~= "" then
        s = s .. ',\r\n'
      end
      s = s .. '[' .. k .. '] = ' .. Dump(v)
    end
    return '\r\n{\r\n' .. s .. '\r\n}\r\n'
  else
    return tostring(o)
  end
end

local function DumpOrdered(o)
  if type(o) == 'table' then
    local s = ''
    for k, v in PairsByKeys(o) do
      if type(k) ~= 'number' then k = '"' .. k .. '"' end
      if s ~= "" then
        s = s .. ',\r\n'
      end
      s = s .. '[' .. k .. '] = ' .. Dump(v)
    end
    return '\r\n{\r\n' .. s .. '\r\n}\r\n'
  else
    return tostring(o)
  end
end

local function ExtractNumber(str, to_number)
  local number_string = ""
  for i = 1, #str do
    local c = str:sub(i, i)
    if tonumber(c) then
      number_string = number_string .. c
    end
  end

  if to_number then
    number_string = tonumber(number_string)
  end

  return number_string
end

local function GetIndexByVal(list, val)
  local index = 0
  for k, v in pairs(list) do
    if val == v then
      index = k
      break
    end
  end
  return index
end

local utils = {
  Log = Log,
  LogD = LogD,
  ToFloat = ToFloat,
  SetWeaponScale = SetWeaponScale,
  ExtractNumber = ExtractNumber,
  GetSize = GetSize,
  Round = Round,
  Dump = Dump,
  DumpOrdered = DumpOrdered,
  ShallowCopy = ShallowCopy,
  PairsByKeys = PairsByKeys,
  StringFindRaw = StringFindRaw,
  Trim = Trim,
  ExpandMessageTags = ExpandMessageTags,
  NormalizeFileName = NormalizeFileName,
  FileExists = FileExists,
  RenameFile = RenameFile,
  DeleteFile = DeleteFile,
  OpenFolder = OpenFolder,
  Explode = Explode,
  PadLeft = PadLeft,
  PadRight = PadRight,
  GetTypeName = GetTypeName,
  GetTypeInfo = GetTypeInfo,
  GetGameObject = GetGameObject,
  ComponentGameObject = ComponentGameObject,
  GetObjectInfo = GetObjectInfo,
  GetObjectFields = GetObjectFields,
  GetTypeFields = GetTypeFields,
  GetMethod = GetMethod,
  GetEnumDic = GetEnumDic,
  GetEnumVal = GetEnumVal,
  CreateResource = CreateResource,
  GetCurrentScene = GetCurrentScene,
  GetSlotStorageData = GetSlotStorageData,
  GetSlotItemData = GetSlotItemData,
  GetWeaponParam = GetWeaponParam,
  GetWeaponItemData = GetWeaponItemData,
  MurmurHash = MurmurHash,
  MATERIAL_FLOAT = MATERIAL_FLOAT,
  MATERIAL_FLOAT4 = MATERIAL_FLOAT4,
  FindMaterialVariable = FindMaterialVariable,
  WEAPON_GLOW = WEAPON_GLOW,
  WEAPON_GLOW_VARIABLES = WEAPON_GLOW_VARIABLES,
  GetGlowVariables = GetGlowVariables,
  GetMeshGlow = GetMeshGlow,
  SetMeshGlow = SetMeshGlow,
  RefreshWeaponBlood = RefreshWeaponBlood,
  GetObjectComponent = GetObjectComponent,
  FindChild = FindChild,
  GetObjectComponents = GetObjectComponents,
  LogObjectCompontents = LogObjectCompontents,
  NATIVE_NULL = NATIVE_NULL,
  GetLuaArray = GetLuaArray,
  GetLuaEnumArray = GetLuaEnumArray,
  GetLuaDic = GetLuaDic,
  GetNpcCatalogIdentity = GetNpcCatalogIdentity,
  GetIndexByVal = GetIndexByVal
}

do
  local MICROSECONDS_PER_SECOND = 1000000
  local CALIBRATION_SAMPLES = 256
  local Timer = {}
  Timer.__index = Timer
  local now, frequency = YowaveUtils.clock.now, YowaveUtils.clock.frequency
  local clock = {name = "YowaveUtils.clock.now", now = now, ticks_per_second = frequency,
    ticks_per_us = frequency / MICROSECONDS_PER_SECOND}

  -- Seconds on the DLL counter, a drop-in for os.clock: only differences between calls are meaningful.
  function utils.Seconds()
    return now() / frequency
  end

  function Timer:GetClock()
    if not self.clock then self.clock = ShallowCopy(clock) end
    return self.clock
  end

  function Timer:Start(name)
    assert(type(name) == "string" and name ~= "", "Expected a performance timer section name")
    local source = self.clock or self:GetClock()
    local depth = self.depth + 1
    local entry = self.stack[depth]
    if not entry then
      entry = {}
      self.stack[depth] = entry
    end
    entry.name, entry.children = name, 0
    entry.started = source.now()
    self.depth = depth
  end

  function Timer:End(name)
    local depth = self.depth
    local entry = self.stack[depth]
    if depth == 0 or entry.name ~= name then error("Unbalanced performance timer: " .. tostring(name)) end
    local elapsed = self.clock.now() - entry.started
    self.depth = depth - 1
    self.pending_ticks[name] = (self.pending_ticks[name] or 0) + elapsed - entry.children
    self.pending_counts[name] = (self.pending_counts[name] or 0) + 1
    if depth > 1 then
      local parent = self.stack[depth - 1]
      parent.children = parent.children + elapsed
    else
      for section, ticks in pairs(self.pending_ticks) do
        self.section_ticks[section] = (self.section_ticks[section] or 0) + ticks
        self.counts[section] = (self.counts[section] or 0) + self.pending_counts[section]
        self.pending_ticks[section], self.pending_counts[section] = nil, nil
      end
      self.total_ticks = self.total_ticks + elapsed
      self.samples = self.samples + 1
    end
    return elapsed / self.clock.ticks_per_us
  end

  function Timer:Discard()
    if self.depth == 0 then return end
    self.depth = 0
    self.pending_ticks, self.pending_counts = {}, {}
  end

  function Timer:Reset()
    self:Discard()
    self.section_ticks, self.counts = {}, {}
    self.total_ticks, self.samples = 0, 0
  end

  function Timer:GetResults()
    local source = self:GetClock()
    local result = {samples = self.samples, total_us = self.total_ticks / source.ticks_per_us, sections = {}, counts = {}}
    for name, ticks in pairs(self.section_ticks) do
      result.sections[name], result.counts[name] = ticks / source.ticks_per_us, self.counts[name]
    end
    return result
  end

  function Timer:Calibrate()
    local trial = utils.CreateTimer()
    trial:GetClock()
    trial:Start("calibration")
    trial:End("calibration")
    local values = {}
    for index = 1, CALIBRATION_SAMPLES do
      trial:Start("calibration")
      values[index] = trial:End("calibration")
    end
    table.sort(values)
    return {min = values[1], median = (values[CALIBRATION_SAMPLES / 2] + values[CALIBRATION_SAMPLES / 2 + 1]) / 2,
      p90 = values[math.floor(CALIBRATION_SAMPLES * 0.9 + 0.5)]}
  end

  function utils.CreateTimer()
    return setmetatable({depth = 0, stack = {}, pending_ticks = {}, pending_counts = {}, section_ticks = {}, counts = {},
      total_ticks = 0, samples = 0}, Timer)
  end
end

do
  -- YowaveUtils.party.read returns party slots as addresses, nil for an empty slot: 0 the Arisen, 1 the main pawn, 2 and
  -- 3 the hired pawns (the saved party in order without the main pawn; an unavailable pawn stays nil in its place). It
  -- reads only the slots asked for, so the Arisen and main pawn need no roster copy.
  local read_party = YowaveUtils.party.read
  local to_managed_object = sdk.to_managed_object
  local PARTY_INDICES = {[0] = true, [1] = true, [2] = true, [3] = true}

  local function WrapMember(address)
    if address then return to_managed_object(address) end
  end

  function utils.GetHiredPawns()
    local pawn2, pawn3 = read_party(2, 3)
    return WrapMember(pawn2), WrapMember(pawn3)
  end

  function utils.GetPartyMember(party_index)
    if not PARTY_INDICES[party_index] then return nil end
    return WrapMember(read_party(party_index))
  end

  -- The Arisen, the main pawn and the two hired pawns from one read, nil where a slot is empty.
  function utils.GetParty()
    local player, pawn, pawn2, pawn3 = read_party()
    return WrapMember(player), WrapMember(pawn), WrapMember(pawn2), WrapMember(pawn3)
  end

  function utils.GetPlayer()
    return utils.GetPartyMember(0)
  end

  function utils.GetMainPawn()
    return utils.GetPartyMember(1)
  end
end

do
  local IMGUI_COLOR_TEXT = 0
  local FONT_FILE = "NotoSansSC-Medium.ttf"
  local FONT_SIZE_OFFSET, FONT_SIZE_MIN, FONT_SIZE_MAX = 3, 19, 40
  local FRAME_HOST_TYPE, FRAME_HOST_METHOD = "app.HitManager", "afterHitCollisionCheck"
  local font, font_size

  utils.FRAME_HOST_TYPE, utils.FRAME_HOST_METHOD = FRAME_HOST_TYPE, FRAME_HOST_METHOD

  -- REFramework passes text_colored and set_tooltip text to ImGui as a printf format; a % in it terminates the game.
  function utils.TextColored(text, color)
    imgui.push_style_color(IMGUI_COLOR_TEXT, color)
    imgui.text(text)
    imgui.pop_style_color(1)
  end

  function utils.SetTooltip(text)
    imgui.set_tooltip((tostring(text):gsub("%%", "%%%%")))
  end

  -- The Transmogify family's window font; returns the font and its pixel size.
  function utils.LoadFont()
    if not font then
      font_size = math.max(FONT_SIZE_MIN, math.min(FONT_SIZE_MAX, imgui.get_default_font_size() + FONT_SIZE_OFFSET))
      font = imgui.load_font(FONT_FILE, font_size, {0x0001, 0xFFFF, 0})
    end
    return font, font_size
  end

  -- Hooks the managed-call frame host that runs native work once per frame; see engine_character_models.md.
  function utils.HookFrameHost(pre, post)
    local definition = sdk.find_type_definition(FRAME_HOST_TYPE)
    local method = definition and definition:get_method(FRAME_HOST_METHOD)
    assert(method, "Frame host " .. FRAME_HOST_TYPE .. "." .. FRAME_HOST_METHOD .. " is missing")
    sdk.hook(method, pre, post or function(retval) return retval end)
  end
end

do
  local position_type = sdk.find_type_definition("via.vec3")
  local PrefabLoader = {}
  PrefabLoader.__index = PrefabLoader

  local function DestroyObject(object)
    object:destroy(object)
  end

  -- Releases the controller even when destroying the copy fails, then raises that failure.
  local function FinishLoad(entry)
    local object, controller = entry.object, entry.owned and entry.controller
    entry.object, entry.mesh, entry.owned = nil, nil, false
    local destroyed, failure = true, nil
    if object then destroyed, failure = pcall(DestroyObject, object) end
    if controller then controller:call("release()") end
    if not destroyed then error(failure, 0) end
  end

  -- Loads weapon prefabs and hands each live weapon mesh to on_ready. Each entry holds an app.PrefabController in
  -- controller: it is referenced, waited on until its prefab is ready, instantiated, waited on until its app.Weapon mesh
  -- and material are ready, passed to on_ready(entry, mesh) (with nil for a prefab without a weapon mesh), then destroyed
  -- and released, with up to limit loading at once and no timeout; entry.started is when its load began. Run Step from
  -- the frame host once per update until it returns true; Cleanup ends the loads in progress.
  function utils.NewPrefabLoader(entries, limit, on_ready)
    return setmetatable({entries = entries, limit = limit, on_ready = on_ready, queued = 1, in_flight = 0, done = 0,
      active = {}}, PrefabLoader)
  end

  function PrefabLoader:Step()
    while self.in_flight < self.limit and self.queued <= #self.entries do
      local entry = self.entries[self.queued]
      self.queued = self.queued + 1
      entry.controller:addRef()
      entry.owned, entry.started = true, utils.Seconds()
      self.active[entry] = true
      self.in_flight = self.in_flight + 1
    end
    for entry in pairs(self.active) do
      if not entry.object and entry.controller:get_Ready() then
        local position = ValueType.new(position_type)
        position.x, position.y, position.z = 0, 0, 0
        entry.object = entry.controller:get_Item():call("instantiate(via.Position)", position)
        if not entry.object then error("Weapon prefab instantiation failed: " .. tostring(entry.controller:get_ResourcePath())) end
        local weapon = utils.GetObjectComponent(entry.object, "app.Weapon")
        entry.mesh = weapon and weapon.Mesh or false
      end
      local mesh = entry.mesh
      if mesh == false or (mesh and mesh:get_MeshReady() and mesh:get_MaterialReady()) then
        self.on_ready(entry, mesh or nil)
        FinishLoad(entry)
        self.active[entry] = nil
        self.in_flight = self.in_flight - 1
        self.done = self.done + 1
      end
    end
    return self.done == #self.entries
  end

  -- The loads in progress, for a progress or stuck report.
  function PrefabLoader:Active()
    return pairs(self.active)
  end

  function PrefabLoader:Cleanup()
    local failure
    for entry in pairs(self.active) do
      local success, reason = pcall(FinishLoad, entry)
      if not success and not failure then failure = reason end
    end
    self.active, self.in_flight = {}, 0
    if failure then error(failure) end
  end
end

return utils;
