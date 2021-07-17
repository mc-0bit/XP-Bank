local menu_title    = XPBankMod.text('xpb_menu_title')
local menu_message  = XPBankMod.get_info()
local menu_options  = XPBankMod.get_menu_options()
local menu          = QuickMenu:new(menu_title, menu_message, menu_options)

menu:Show()