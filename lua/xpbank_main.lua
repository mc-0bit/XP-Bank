--[[
  TODO
  1. Run through various levels to see if everything works
  2. Check if max_int works properly
]]

dofile(ModPath .. 'lua/xpbank_code.lua')

XPBankMod               = XPBankMod or {}
XPBankMod._save_path    = SavePath .. 'xp_bank_mod.txt'
XPBankMod._loc_path     = ModPath .. 'loc/'
XPBankMod._menu_path    = ModPath .. 'menu.txt'
XPBankMod._data         = {
  stored = 0,
  xpb_multiplier_value = 0.7
}    

function XPBankMod.chat(msg)
  managers.chat:_receive_message(
    1,
    XPBankMod.text("xpb_menu_title"),
    tostring(msg),
    Color.yellow
  )
end

function XPBankMod.load()
  local file = io.open(XPBankMod._save_path, 'r')

  if file then
    local data = json.decode(file:read())

    for k, v in pairs(data) do
      XPBankMod._data[k] = tonumber(XPBankMod.base64.decode(v))
    end

    file:close()
  end
end

function XPBankMod.save()
  local file = io.open(XPBankMod._save_path, 'w')

  if file then
    local temp = {}

    for k, v in pairs(XPBankMod._data) do
      temp[k] = XPBankMod.base64.encode(tostring(v))
    end

    local data = json.encode(temp)

    file:write(data)
    file:close()
  end
end

function XPBankMod.get_loc_file()
  if BLT and BLT.Localization then
    local lang = BLT.Localization:get_language().language
    local file = XPBankMod._loc_path .. lang .. ".txt"

    if io.file_is_readable(file) then
      return file
    end
  end
  return XPBankMod._loc_path .. 'en.txt'
end

function XPBankMod.load_loc()
  Hooks:Add('LocalizationManagerPostInit', 'xpbank_load_loc_id',
    function (self, ...)
      local loc_file = XPBankMod.get_loc_file()
      self:load_localization_file(loc_file, false)
    end
  )
end

function XPBankMod.exp_prehook()
  Hooks:PreHook(ExperienceManager, "give_experience", "xpbank_give_exp_id",
    function (self, xp, force_or_debug)
      local current_level           = managers.experience:current_level()
      local level_cap               = managers.experience:level_cap()
      local deposit_amt             = 0

      if current_level == level_cap then
        deposit_amt = xp * XPBankMod._data.xpb_multiplier_value
      else
        local max_level, max_level_xp = XPBankMod.get_max_level_up(xp)

        if current_level + max_level == level_cap then
          deposit_amt = (xp - max_level_xp) * XPBankMod._data.xpb_multiplier_value
        end
      end

      deposit_amt = XPBankMod.round_to_int(deposit_amt)

      local max_int       = 99999999999999
      local is_over_limit = deposit_amt + XPBankMod._data.stored > max_int

      if is_over_limit then
        deposit_amt = max_int - XPBankMod._data.stored
      end

      if deposit_amt > 0 or is_over_limit then
        local stored            = XPBankMod._data.stored
        local deposited_str     = XPBankMod.format(deposit_amt)
        XPBankMod._data.stored  = stored + deposit_amt
        local total_str         = XPBankMod.format(XPBankMod._data.stored)
        local msg               = ""

        if not is_over_limit then
          msg = string.format(
            XPBankMod.text("xpb_game_deposited"),
            deposited_str,
            total_str
          )
        else
          msg = string.format(
            XPBankMod.text("xpb_game_limit_reached"),
            total_str
          )
        end

        XPBankMod.save()
        XPBankMod.chat(msg)
      end
    end
  )
end

XPBankMod.load()
XPBankMod.load_loc()

function XPBankMod.get_info()
  local level     = managers.experience:current_level()
  local level_cap = managers.experience:level_cap()
  local balance   = XPBankMod.format(XPBankMod._data.stored)
  local action    = ''

  if level == level_cap then
    -- Player at level 100 message
    action = XPBankMod.text('xpb_menu_desc_100')
  else
    local max_level, max_level_xp,_ = XPBankMod.get_max_level_up()
    if max_level == 0 then
      -- Player balance too low
      action = XPBankMod.text('xpb_menu_desc_low_bal')
    else
      -- Max level up
      local max_lvl_xp_fmt = managers.experience:experience_string(max_level_xp)
      action = string.format(
        XPBankMod.text('xpb_menu_desc_lvl_up'),
        level + max_level,
        max_lvl_xp_fmt
      )
    end
  end

  local level_text    = string.format(
    XPBankMod.text("xpb_menu_desc_level"),
    level
  )
  local balance_text  = string.format(
    XPBankMod.text("xpb_menu_desc_balance"),
    balance
  )
  local msg = level_text .. balance_text .. action

  return msg
end

function XPBankMod.get_menu_options()
  local options                     = {}
  local level                       = managers.experience:current_level()
  local level_cap                   = managers.experience:level_cap()
  local max_level_up, _, level_data = XPBankMod.get_max_level_up()

  if level < level_cap and max_level_up ~= 0 then
    -- Level <max>
    options[#options + 1] = {
      text = string.format(managers.localization:text("xpb_menu_level"), level + max_level_up),
      callback = function() XPBankMod.choose_level(level_data[1]) end
    }
    if max_level_up > 1 then
      -- Choose Level
      options[#options + 1] = {
        text = managers.localization:text("xpb_menu_picker"),
        callback = XPBankMod.choose_level_menu
      }
    end
  end

  options[#options + 1] = {text = 'Cancel',is_cancel_button = true}

  return options
end


function XPBankMod.choose_level_menu(page)
  local options         = {}
  local level           = managers.experience:current_level()
  local _,_,level_table = XPBankMod.get_max_level_up()
  page                  = page or 0
  local start_index     = 1 + page * 10
  local end_index       = math.min(start_index + 9, #level_table)
  local items_per_page  = 10
  local max_page        = math.ceil(#level_table/items_per_page) - 1

  for i = start_index, end_index do
    local level_item = string.format(
      XPBankMod.text('xpb_menu_level'),
      level_table[i].level + level
    )
    options[#options + 1] = {
      text      = level_item,
      callback  = function() XPBankMod.choose_level(level_table[i]) end
    }
  end

  options[#options + 1] = {no_text = true,is_cancel_button = true}

  local is_higher = page > 0
  local is_lower  = page < max_page

  if is_higher then
    options[#options + 1] = {
      text      = XPBankMod.text("xpb_menu_page_higher"),
      callback  = function() XPBankMod.choose_level_menu(page - 1) end
    }
  end

  if is_lower then
    options[#options + 1] = {
      text      = XPBankMod.text("xpb_menu_page_lower"),
      callback  = function() XPBankMod.choose_level_menu(page + 1) end
    }
  end

  local menu_title  = XPBankMod.text("xpb_menu_title")
  local menu_desc   = XPBankMod.text("xpb_menu_picker")

  options[#options + 1]    = {text = 'Cancel',is_cancel_button = true}

  local menu = QuickMenu:new(menu_title, menu_desc, options)
  menu:Show()
end

function XPBankMod.choose_level(level_data)
  local level = XPBankMod.submit(level_data)

  local chosen_level = string.format(
    XPBankMod.text("xpb_menu_chosen_level"), level
  )
  local chosen_level_xp = string.format(
    XPBankMod.text("xpb_menu_xp_deducted"),
    XPBankMod.format(level_data.xp_req)
  )
  local balance = string.format(
    XPBankMod.text("xpb_menu_xp_balance"),
    XPBankMod.format(XPBankMod._data.stored)
  )
  local msg = chosen_level .. chosen_level_xp .. balance

  local menu = XPBankMod.create_quick_menu(
    XPBankMod.text("xpb_menu_title"),
    msg,
    nil,
    true,
    XPBankMod.text("xpb_menu_confirm")
  )
  menu:Show()
end

function XPBankMod.submit(level_data)
  if managers and managers.experience then
    managers.experience:add_points(level_data.xp_req, false, true)

    local balance           = XPBankMod._data.stored - level_data.xp_req
    XPBankMod._data.stored  = balance

    XPBankMod.save()

    return managers.experience:current_level()
  end
end

function XPBankMod.create_quick_menu(title ,desc, options, is_cancel, cancel_text)
  options = options or {}

  if is_cancel then
    cancel_text = cancel_text and cancel_text or XPBankMod.text("xpb_menu_cancel")
    options[#options + 1] = {
      text              = cancel_text,
      is_cancel_button  = true
    }
  end

  return QuickMenu:new(title,desc,options,is_cancel)
end

function XPBankMod.get_max_level_up(xp)
  local exp_mgr       = managers.experience
  local current_level = exp_mgr:current_level()
  local next_level_xp = XPBankMod.get_next_level_xp()
  local max_level     = 0
  local max_level_xp  = 0
  local level_arr     = tweak_data.experience_manager.levels
  local level_table   = {}
  local stored        = xp and xp or XPBankMod._data.stored

  if next_level_xp > stored then
    return 0,0,0
  else
    stored        = stored - next_level_xp
    max_level     = max_level + 1
    max_level_xp  = next_level_xp
    table.insert(
      level_table,
      {level = max_level,xp_req = max_level_xp}
    )
  end

  for i = (current_level + max_level + 1), #level_arr do
    next_level_xp = Application:digest_value(level_arr[i].points, false)

    local temp = max_level_xp + next_level_xp

    if next_level_xp <= stored then
      stored        = stored - next_level_xp
      max_level     = max_level + 1
      max_level_xp  = temp
      table.insert(
        level_table,
        {
          level   = max_level,
          xp_req  = max_level_xp
        }
      )
    else
      break
    end
  end

  table.sort(level_table,
    function(a, b)
      return a.level > b.level
    end
  )

  return max_level, max_level_xp, level_table
end

function XPBankMod.get_next_level_xp()
  local exp_mgr       = managers.experience
  local next_level_xp = exp_mgr:next_level_data_points() - exp_mgr:next_level_data_current_points()

  return next_level_xp
end

function XPBankMod.text(loc_key)
  return managers.localization:text(loc_key)
end

function XPBankMod.format(number)
  return managers.experience:experience_string(number)
end

function XPBankMod.round_to_int(x)
  local result = x + 0.5 - (x + 0.5) % 1
  return math.floor(result)
end

function XPBankMod.crimespree_prehook()
  Hooks:PreHook(CrimeSpreeManager, "on_spree_complete", "xpbank_crimespree_id",
    function()
      Hooks:RemovePreHook("xpbank_give_exp_id")
      Hooks:RemovePreHook("xpbank_crimespree_id")
    end
  )
end

function XPBankMod.add_options_menu()
  Hooks:Add("MenuManagerInitialize", 'xpbank_mmi_id',
    function(menu_manager)
      MenuHelper:LoadFromJsonFile(XPBankMod._menu_path, XPBankMod, XPBankMod._data)
    end
  )
end

function XPBankMod.add_slider_callback()
  MenuCallbackHandler.xpb_multiplier_slider_clbk = function(self, item)
    local value = tonumber(item:value())

    XPBankMod._data.xpb_multiplier_value = value
    XPBankMod.save()
  end
end    

if RequiredScript == "lib/managers/experiencemanager" then
  XPBankMod.exp_prehook()
elseif RequiredScript == "lib/managers/crimespreemanager" then
  XPBankMod.crimespree_prehook()
elseif RequiredScript == "lib/managers/menumanager" then
  XPBankMod.add_options_menu()
  XPBankMod.add_slider_callback()
end    