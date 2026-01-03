#pragma semicolon 1
#include <sourcemod>
#include <topmenus>

#define MAXPRESTIGE 10

TopMenu g_hRPGTopMenu;

TopMenuObject g_TopMenuUpgrades;
TopMenuObject g_TopMenuSell;
TopMenuObject g_TopMenuUpgradeSettings;
TopMenuObject g_TopMenuStats;
TopMenuObject g_TopMenuSettings;
TopMenuObject g_TopMenuHelp;

Menu g_hConfirmResetStatsMenu;

Handle g_hfwdOnRPGMenuCreated;
Handle g_hfwdOnRPGMenuReady;
ArrayList g_hPrestigeUpgrades[MAXPRESTIGE] = {null, ...};

int g_iSelectedSettingsUpgrade[MAXPLAYERS+1] = {-1,...};

enum struct PrestigeUpgradeInfo
{
    int requiredLevel;
    char shortName[MAX_UPGRADE_SHORTNAME_LENGTH];
}

/**
 * Setup functions to create the topmenu and API.
 */
void RegisterTopMenu()
{
	g_hRPGTopMenu = new TopMenu(TopMenu_DefaultCategoryHandler);
	g_hRPGTopMenu.CacheTitles = false;
	
	g_TopMenuUpgrades = g_hRPGTopMenu.AddCategory(RPGMENU_UPGRADES, TopMenu_DefaultCategoryHandler);
	g_TopMenuSell = g_hRPGTopMenu.AddCategory(RPGMENU_SELL, TopMenu_DefaultCategoryHandler);
	g_TopMenuUpgradeSettings = g_hRPGTopMenu.AddCategory(RPGMENU_UPGRADESETTINGS, TopMenu_DefaultCategoryHandler);
	g_TopMenuStats = g_hRPGTopMenu.AddCategory(RPGMENU_STATS, TopMenu_DefaultCategoryHandler);
	g_TopMenuSettings = g_hRPGTopMenu.AddCategory(RPGMENU_SETTINGS, TopMenu_DefaultCategoryHandler);
	g_TopMenuHelp = g_hRPGTopMenu.AddCategory(RPGMENU_HELP, TopMenu_DefaultCategoryHandler);
}

public Action Cmd_DebugPrestige(int client, int args)
{
    if (!client)
    {
        ReplyToCommand(client, "This command must be run in-game");
        return Plugin_Handled;
    }
    
    int iPrestige = SMRPG_GetClientPrestigeLevel(client);
    int iLevel = SMRPG_GetClientLevel(client);
    
    PrintToChat(client, "========== PRESTIGE DEBUG ==========");
    PrintToChat(client, "Your Prestige: %d | Level: %d", iPrestige, iLevel);
    
    // Check if prestige upgrades are loaded
    if (g_hPrestigeUpgrades[iPrestige] == null)
    {
        PrintToChat(client, "[ERROR] Prestige %d config is NULL!", iPrestige);
        PrintToChat(client, "Attempting to reload...");
        
        LoadPrestigeUpgrades();
        
        if (g_hPrestigeUpgrades[iPrestige] == null)
        {
            PrintToChat(client, "[ERROR] Still NULL after reload!");
            PrintToChat(client, "Check server console for errors");
            return Plugin_Handled;
        }
    }
    
    int iConfiguredCount = g_hPrestigeUpgrades[iPrestige].Length;
    PrintToChat(client, "Prestige %d has %d upgrades configured", iPrestige, iConfiguredCount);
    
    if (iConfiguredCount == 0)
    {
        PrintToChat(client, "[WARNING] No upgrades configured for prestige %d!", iPrestige);
        return Plugin_Handled;
    }
    
    PrintToChat(client, "---------- Configured Upgrades ----------");
    
    // List configured upgrades for this prestige
    PrestigeUpgradeInfo upgradeInfo;
    for (int i = 0; i < iConfiguredCount; i++)
    {
        g_hPrestigeUpgrades[iPrestige].GetArray(i, upgradeInfo);
        
        char status[32];
        if (iLevel >= upgradeInfo.requiredLevel)
            Format(status, sizeof(status), "AVAILABLE");
        else
            Format(status, sizeof(status), "LOCKED (need lvl %d)", upgradeInfo.requiredLevel);
        
        PrintToChat(client, "%d. %s - %s", i+1, upgradeInfo.shortName, status);
    }
    
    PrintToChat(client, "---------- System Check ----------");
    
    // Check total upgrades in system
    int iTotalUpgrades = GetUpgradeCount();
    PrintToChat(client, "Total upgrades in system: %d", iTotalUpgrades);
    
    // Check how many are available vs restricted
    int availableCount = 0;
    int restrictedCount = 0;
    int purchasedCount = 0;
    
    InternalUpgradeInfo upgrade;
    for (int i = 0; i < iTotalUpgrades; i++)
    {
        if (!GetUpgradeByIndex(i, upgrade) || !IsValidUpgrade(upgrade))
            continue;
        
        int purchased = GetClientPurchasedUpgradeLevel(client, i);
        if (purchased > 0)
        {
            purchasedCount++;
            continue; // Skip - already owned
        }
        
        if (IsUpgradeAvailableForPlayer(client, i))
            availableCount++;
        else
            restrictedCount++;
    }
    
    PrintToChat(client, "Available to buy: %d", availableCount);
    PrintToChat(client, "Restricted: %d", restrictedCount);
    PrintToChat(client, "Already purchased: %d", purchasedCount);
    
    PrintToChat(client, "---------- Sample Upgrades ----------");
    
    // Show first 5 valid upgrades and their status
    int checked = 0;
    for (int i = 0; i < iTotalUpgrades && checked < 5; i++)
    {
        if (!GetUpgradeByIndex(i, upgrade) || !IsValidUpgrade(upgrade))
            continue;
        
        int purchased = GetClientPurchasedUpgradeLevel(client, i);
        bool available = IsUpgradeAvailableForPlayer(client, i);
        
        char status[64];
        if (purchased > 0)
            Format(status, sizeof(status), "OWNED (lvl %d)", purchased);
        else if (available)
            Format(status, sizeof(status), "AVAILABLE");
        else
            Format(status, sizeof(status), "RESTRICTED");
        
        PrintToChat(client, "%s: %s", upgrade.shortName, status);
        checked++;
    }
    
    PrintToChat(client, "====================================");
    
    return Plugin_Handled;
}

void RegisterTopMenuForwards()
{
	g_hfwdOnRPGMenuCreated = CreateGlobalForward("SMRPG_OnRPGMenuCreated", ET_Ignore, Param_Cell);
	g_hfwdOnRPGMenuReady = CreateGlobalForward("SMRPG_OnRPGMenuReady", ET_Ignore, Param_Cell);
}

void RegisterTopMenuNatives()
{
	CreateNative("SMRPG_GetTopMenu", Native_GetTopMenu);
}

void LoadPrestigeUpgrades()
{
    // Clear existing cache
    for (int i = 0; i < MAXPRESTIGE; i++)
    {
        if (g_hPrestigeUpgrades[i] != null)
        {
            delete g_hPrestigeUpgrades[i];
            g_hPrestigeUpgrades[i] = null;
        }
    }
    
    // Load the prestige config
    char sConfigPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sConfigPath, sizeof(sConfigPath), "configs/smrpg/prestige.cfg");
    
    if (!FileExists(sConfigPath))
    {
        LogError("[PRESTIGE] Config file not found: %s", sConfigPath);
        return;
    }
    
    KeyValues kv = new KeyValues("Prestige");
    if (!kv.ImportFromFile(sConfigPath))
    {
        delete kv;
        LogError("[PRESTIGE] Failed to load prestige config: %s", sConfigPath);
        return;
    }
    
    LogMessage("[PRESTIGE] Loading prestige configuration...");
    
    // Load each prestige level
    if (!kv.GotoFirstSubKey(false))
    {
        delete kv;
        LogError("[PRESTIGE] No prestige levels found in config!");
        return;
    }
    
    do
    {
        char sPrestigeKey[12];
        kv.GetSectionName(sPrestigeKey, sizeof(sPrestigeKey));
        
        int iPrestige = StringToInt(sPrestigeKey);
        if (iPrestige < 0 || iPrestige >= MAXPRESTIGE)
        {
            LogError("[PRESTIGE] Invalid prestige level: %d (must be 0-%d)", iPrestige, MAXPRESTIGE-1);
            continue;
        }
        
        LogMessage("[PRESTIGE] Loading prestige level %d...", iPrestige);
        
        // Create ArrayList for this prestige
        g_hPrestigeUpgrades[iPrestige] = new ArrayList(sizeof(PrestigeUpgradeInfo));
        
        // Load upgrades for this prestige
        if (kv.JumpToKey("upgrades", false))
        {
            if (kv.GotoFirstSubKey(false))
            {
                PrestigeUpgradeInfo upgradeInfo;
                
                do
                {
                    char sLevelStr[12];
                    kv.GetSectionName(sLevelStr, sizeof(sLevelStr));
                    
                    upgradeInfo.requiredLevel = StringToInt(sLevelStr);
                    
                    char sUpgradeList[256];
                    kv.GetString(NULL_STRING, sUpgradeList, sizeof(sUpgradeList));
                    
                    // Parse comma-separated upgrade names
                    char sUpgrades[32][MAX_UPGRADE_SHORTNAME_LENGTH];
                    int upgradeCount = ExplodeString(sUpgradeList, ",", sUpgrades, sizeof(sUpgrades), sizeof(sUpgrades[]));
                    
                    for (int i = 0; i < upgradeCount; i++)
                    {
                        TrimString(sUpgrades[i]);
                        
                        if (strlen(sUpgrades[i]) > 0)
                        {
                            strcopy(upgradeInfo.shortName, sizeof(upgradeInfo.shortName), sUpgrades[i]);
                            g_hPrestigeUpgrades[iPrestige].PushArray(upgradeInfo);
                            
                            LogMessage("[PRESTIGE] P%d: Added '%s' (unlock at level %d)", 
                                iPrestige, upgradeInfo.shortName, upgradeInfo.requiredLevel);
                        }
                    }
                    
                } while (kv.GotoNextKey(false));
                
                kv.GoBack(); // Back from subsections
            }
            else
            {
                LogError("[PRESTIGE] Prestige %d has 'upgrades' section but no entries!", iPrestige);
            }
            
            kv.GoBack(); // Back from "upgrades"
        }
        else
        {
            LogError("[PRESTIGE] Prestige %d has no 'upgrades' section!", iPrestige);
        }
        
        LogMessage("[PRESTIGE] Prestige %d loaded with %d upgrades", 
            iPrestige, g_hPrestigeUpgrades[iPrestige].Length);
        
        kv.GoBack(); // Back to root to check next prestige level
        
    } while (kv.GotoNextKey(false));
    
    delete kv;
    LogMessage("[PRESTIGE] Prestige configuration loaded successfully");
}

void InitMenu()
{
	// Add any already loaded upgrades to the menus
	int iSize = GetUpgradeCount();
	InternalUpgradeInfo upgrade;
	char sBuffer[MAX_UPGRADE_SHORTNAME_LENGTH+20];
	for(int i=0;i<iSize;i++)
	{
		GetUpgradeByIndex(i, upgrade);
		
		if(upgrade.topmenuUpgrades == INVALID_TOPMENUOBJECT)
		{
			Format(sBuffer, sizeof(sBuffer), "rpgupgrade_%s", upgrade.shortName);
			upgrade.topmenuUpgrades = g_hRPGTopMenu.AddItem(sBuffer, TopMenu_HandleUpgrades, g_TopMenuUpgrades);
		}
		if(upgrade.topmenuSell == INVALID_TOPMENUOBJECT)
		{
			Format(sBuffer, sizeof(sBuffer), "rpgsell_%s", upgrade.shortName);
			upgrade.topmenuSell = g_hRPGTopMenu.AddItem(sBuffer, TopMenu_HandleSell, g_TopMenuSell);
		}
		if(upgrade.topmenuUpgradeSettings == INVALID_TOPMENUOBJECT)
		{
			Format(sBuffer, sizeof(sBuffer), "rpgupgrsettings_%s", upgrade.shortName);
			upgrade.topmenuUpgradeSettings = g_hRPGTopMenu.AddItem(sBuffer, TopMenu_HandleUpgradeSettings, g_TopMenuUpgradeSettings);
		}
		if(upgrade.topmenuHelp == INVALID_TOPMENUOBJECT)
		{
			Format(sBuffer, sizeof(sBuffer), "rpghelp_%s", upgrade.shortName);
			upgrade.topmenuHelp = g_hRPGTopMenu.AddItem(sBuffer, TopMenu_HandleHelp, g_TopMenuHelp);
		}
		SaveUpgradeConfig(upgrade);
	}
	
	// Stats Menu
	g_hRPGTopMenu.AddItem("level", TopMenu_HandleStats, g_TopMenuStats);
	g_hRPGTopMenu.AddItem("exp", TopMenu_HandleStats, g_TopMenuStats);
	g_hRPGTopMenu.AddItem("credits", TopMenu_HandleStats, g_TopMenuStats);
	g_hRPGTopMenu.AddItem("rank", TopMenu_HandleStats, g_TopMenuStats);
	g_hRPGTopMenu.AddItem("lastexp", TopMenu_HandleStats, g_TopMenuStats);
	
	// Settings Menu
	g_hRPGTopMenu.AddItem("resetstats", TopMenu_HandleSettings, g_TopMenuSettings);
	g_hRPGTopMenu.AddItem("toggleautoshow", TopMenu_HandleSettings, g_TopMenuSettings);
	g_hRPGTopMenu.AddItem("togglefade", TopMenu_HandleSettings, g_TopMenuSettings);
	
	// Reset Stats Confirmation
	g_hConfirmResetStatsMenu = new Menu(Menu_ConfirmResetStats, MENU_ACTIONS_DEFAULT|MenuAction_Display|MenuAction_DisplayItem);
	g_hConfirmResetStatsMenu.ExitBackButton = true;

	g_hConfirmResetStatsMenu.SetTitle("credits_display");
	
	g_hConfirmResetStatsMenu.AddItem("yes", "Yes");
	g_hConfirmResetStatsMenu.AddItem("no", "No");
	
	Call_StartForward(g_hfwdOnRPGMenuCreated);
	Call_PushCell(g_hRPGTopMenu);
	Call_Finish();
	
	Call_StartForward(g_hfwdOnRPGMenuReady);
	Call_PushCell(g_hRPGTopMenu);
	Call_Finish();
}

void ResetPlayerMenu(int client)
{
	g_iSelectedSettingsUpgrade[client] = -1;
}

/**
 * Native callbacks
 */
public int Native_GetTopMenu(Handle plugin, int numParams)
{
	return view_as<int>(g_hRPGTopMenu);
}

void DisplayMainMenu(int client)
{
	g_hRPGTopMenu.Display(client, TopMenuPosition_Start);
}

void DisplayUpgradesMenu(int client)
{
	g_hRPGTopMenu.DisplayCategory(g_TopMenuUpgrades, client);
}

/**
 * TopMenu callback handlers
 */
// Print the default categories correctly.
public void TopMenu_DefaultCategoryHandler(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayTitle:
		{
			if(object_id == g_TopMenuUpgrades)
				Format(buffer, maxlength, "SM:RPG %T", "Upgrades", param);
			else if(object_id == g_TopMenuSell)
				Format(buffer, maxlength, "SM:RPG %T", "Sell", param);
			else if(object_id == g_TopMenuUpgradeSettings)
				Format(buffer, maxlength, "SM:RPG %T", "Upgrade Settings", param);
			else if(object_id == g_TopMenuStats)
				Format(buffer, maxlength, "SM:RPG %T", "Stats", param);
			else if(object_id == g_TopMenuSettings)
				Format(buffer, maxlength, "SM:RPG %T", "Settings", param);
			else if(object_id == g_TopMenuHelp)
				Format(buffer, maxlength, "SM:RPG %T", "Help", param);
			else
				Format(buffer, maxlength, "SM:RPG %T", "Menu", param);
			
			// Always display the current credits in the title
			Format(buffer, maxlength, "%s\n%T\n-----\n", buffer, "Credits", param, GetClientCredits(param));
		}
		case TopMenuAction_DisplayOption:
		{
			if(object_id == g_TopMenuUpgrades)
				Format(buffer, maxlength, "%T", "Upgrades", param);
			else if(object_id == g_TopMenuSell)
				Format(buffer, maxlength, "%T", "Sell", param);
			else if(object_id == g_TopMenuUpgradeSettings)
				Format(buffer, maxlength, "%T", "Upgrade Settings", param);
			else if(object_id == g_TopMenuStats)
				Format(buffer, maxlength, "%T", "Stats", param);
			else if(object_id == g_TopMenuSettings)
				Format(buffer, maxlength, "%T", "Settings", param);
			else if(object_id == g_TopMenuHelp)
				Format(buffer, maxlength, "%T", "Help", param);
		}
	}
}

public void TopMenu_HandleUpgrades(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH+20];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			InternalUpgradeInfo upgrade;
			if(!GetUpgradeByShortname(sShortname[11], upgrade))
				return;
			
			if(!IsValidUpgrade(upgrade) || !upgrade.enabled)
				return;
			
			// Show the team this upgrade is locked to, if it is.
			char sTeamlock[128];
			if((!IsClientInLockedTeam(param, upgrade) || upgrade.teamlock > 1 && g_hCVShowTeamlockNoticeOwnTeam.BoolValue) && upgrade.teamlock < GetTeamCount())
			{
				GetTeamName(upgrade.teamlock, sTeamlock, sizeof(sTeamlock));
				Format(sTeamlock, sizeof(sTeamlock), " (%T)", "Is teamlocked", param, sTeamlock);
			}
			
			char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
			GetUpgradeTranslatedName(param, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
			
			int iCurrentLevel = GetClientPurchasedUpgradeLevel(param, upgrade.index);
			
			if(iCurrentLevel >= upgrade.maxLevel)
			{
				Format(buffer, maxlength, "%T", "RPG menu buy upgrade entry max level", param, sTranslatedName, iCurrentLevel, "Cost", sTeamlock);
			}
			// Optionally show the maxlevel of the upgrade
			else if (g_hCVShowMaxLevelInMenu.BoolValue)
			{
				Format(buffer, maxlength, "%T", "RPG menu buy upgrade entry show max", param, sTranslatedName, iCurrentLevel+1, upgrade.maxLevel, "Cost", GetUpgradeCost(upgrade.index, iCurrentLevel+1), sTeamlock);
			}
			else
			{
				Format(buffer, maxlength, "%T", "RPG menu buy upgrade entry", param, sTranslatedName, iCurrentLevel+1, "Cost", GetUpgradeCost(upgrade.index, iCurrentLevel+1), sTeamlock);
			}
		}
		case TopMenuAction_DrawOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH+20];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			InternalUpgradeInfo upgrade;
			// Don't show invalid upgrades at all in the menu.
			if(!GetUpgradeByShortname(sShortname[11], upgrade) || !IsValidUpgrade(upgrade) || !upgrade.enabled || !HasAccessToUpgrade(param, upgrade))
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			// PRESTIGE CHECK: Only check if upgrade is available if player hasn't purchased it yet
			int iLevel = GetClientPurchasedUpgradeLevel(param, upgrade.index);
			if (iLevel <= 0 && !IsUpgradeAvailableForPlayer(param, upgrade.index))
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			// The upgrade is teamlocked and the client is in the wrong team.
			if(!IsClientInLockedTeam(param, upgrade))
			{
				buffer[0] |= GetItemDrawFlagsForTeamlock(iLevel, true);
			}
			
			// Don't let players buy upgrades they already maxed out.
			if(iLevel >= upgrade.maxLevel)
				buffer[0] |= ITEMDRAW_DISABLED;
		}
		case TopMenuAction_SelectOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH+20];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			InternalUpgradeInfo upgrade;
			
			// Bad upgrade?
			if(!GetUpgradeByShortname(sShortname[11], upgrade) || !IsValidUpgrade(upgrade) || !upgrade.enabled || !HasAccessToUpgrade(param, upgrade))
			{
				g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
				return;
			}
			
			int iItemIndex = upgrade.index;
			int iItemLevel = GetClientPurchasedUpgradeLevel(param, iItemIndex);
			int iCost = GetUpgradeCost(iItemIndex, iItemLevel+1);
			
			char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
			GetUpgradeTranslatedName(param, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
			
			if(iItemLevel >= upgrade.maxLevel)
				Client_PrintToChat(param, false, "%t", "Maximum level reached");
			else if(GetClientCredits(param) < iCost)
				Client_PrintToChat(param, false, "%t", "Not enough credits", sTranslatedName, iItemLevel+1, iCost);
			else
			{
				if(BuyClientUpgrade(param, iItemIndex))
				{
					Client_PrintToChat(param, false, "%t", "Upgrade bought", sTranslatedName, iItemLevel+1);
					if(g_hCVShowUpgradePurchase.BoolValue)
					{
						for(int i=1;i<=MaxClients;i++)
						{
							if(i != param && IsClientInGame(i) && !IsFakeClient(i))
							{
								GetUpgradeTranslatedName(i, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
								Client_PrintToChat(i, false, "%t", "Upgrade purchase notification", param, sTranslatedName, iItemLevel+1);
							}
						}
					}
				}
			}
			
			g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
		}
	}
}

public void TopMenu_HandleSell(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH+20];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			InternalUpgradeInfo upgrade;
			if(!GetUpgradeByShortname(sShortname[8], upgrade))
				return;
			
			if(!IsValidUpgrade(upgrade))
				return;

			// Don't show the upgrade if it is disabled and players are not allowed to sell disabled upgrades.
			if(!upgrade.enabled && (!g_hCVAllowSellDisabled.BoolValue || GetClientPurchasedUpgradeLevel(param, upgrade.index) <= 0))
				return;
			
			// Show the team this upgrade is locked to, if it is.
			char sTeamlock[128];
			if((!IsClientInLockedTeam(param, upgrade) || upgrade.teamlock > 1 && g_hCVShowTeamlockNoticeOwnTeam.BoolValue) && upgrade.teamlock < GetTeamCount())
			{
				GetTeamName(upgrade.teamlock, sTeamlock, sizeof(sTeamlock));
				Format(sTeamlock, sizeof(sTeamlock), " (%T)", "Is teamlocked", param, sTeamlock);
			}
			
			char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
			GetUpgradeTranslatedName(param, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
			
			// Optionally show the maxlevel of the upgrade
			if (g_hCVShowMaxLevelInMenu.BoolValue)
			{
				Format(buffer, maxlength, "%T", "RPG menu sell upgrade entry show max", param, sTranslatedName, GetClientPurchasedUpgradeLevel(param, upgrade.index), upgrade.maxLevel, "Sale", GetUpgradeSale(upgrade.index, GetClientPurchasedUpgradeLevel(param, upgrade.index)), sTeamlock);
			}
			else
			{
				Format(buffer, maxlength, "%T", "RPG menu sell upgrade entry", param, sTranslatedName, GetClientPurchasedUpgradeLevel(param, upgrade.index), "Sale", GetUpgradeSale(upgrade.index, GetClientPurchasedUpgradeLevel(param, upgrade.index)), sTeamlock);
			}
		}
		case TopMenuAction_DrawOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			InternalUpgradeInfo upgrade;
			// Don't show invalid upgrades at all in the menu.
			if(!GetUpgradeByShortname(sShortname[8], upgrade) || !IsValidUpgrade(upgrade))
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			int iCurrentLevel = GetClientPurchasedUpgradeLevel(param, upgrade.index);
			
			// PRESTIGE CHECK: Always show purchased upgrades, regardless of prestige restrictions
			// Only hide if never purchased AND not available for current prestige/level
			if (iCurrentLevel <= 0 && !IsUpgradeAvailableForPlayer(param, upgrade.index))
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}

			// Don't show the upgrade if it is disabled and players are not allowed to sell disabled upgrades.
			if(!upgrade.enabled && (!g_hCVAllowSellDisabled.BoolValue || iCurrentLevel <= 0))
				return;
			
			// Allow clients to sell upgrades they no longer have access to, but don't show them, if they never bought it.
			if(!HasAccessToUpgrade(param, upgrade) && iCurrentLevel <= 0)
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			// The upgrade is teamlocked and the client is in the wrong team.
			if(!IsClientInLockedTeam(param, upgrade))
			{
				buffer[0] |= GetItemDrawFlagsForTeamlock(iCurrentLevel, false);
			}
			
			// There is nothing to sell..
			if(iCurrentLevel <= 0)
				buffer[0] |= ITEMDRAW_DISABLED;
		}
		case TopMenuAction_SelectOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			InternalUpgradeInfo upgrade;
			
			// Bad upgrade?
			if(!GetUpgradeByShortname(sShortname[8], upgrade) || !IsValidUpgrade(upgrade))
			{
				g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
				return;
			}

			// Don't allow selling the upgrade if it is disabled and players are not allowed to sell disabled upgrades.
			if(!upgrade.enabled && (!g_hCVAllowSellDisabled.BoolValue || GetClientPurchasedUpgradeLevel(param, upgrade.index) <= 0))
				return;
			
			Menu hMenu = new Menu(Menu_ConfirmSell, MENU_ACTIONS_DEFAULT|MenuAction_Display|MenuAction_DisplayItem);
			hMenu.ExitBackButton = true;
		
			hMenu.SetTitle("credits_display");
			
			char sIndex[10];
			IntToString(upgrade.index, sIndex, sizeof(sIndex));
			hMenu.AddItem(sIndex, "Yes");
			hMenu.AddItem("no", "No");
			
			hMenu.Display(param, MENU_TIME_FOREVER);
		}
	}
}

public int Menu_ConfirmSell(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "no"))
			return 0;
		
		int iItemIndex = StringToInt(sInfo);
		InternalUpgradeInfo upgrade;
		GetUpgradeByIndex(iItemIndex, upgrade);
		char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
		GetUpgradeTranslatedName(param1, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
		
		if (SellClientUpgrade(param1, iItemIndex))
			Client_PrintToChat(param1, false, "%t", "Upgrade sold", sTranslatedName, GetClientPurchasedUpgradeLevel(param1, iItemIndex));
		
		g_hRPGTopMenu.Display(param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_Display)
	{
		// Change the title
		Panel hPanel = view_as<Panel>(param2);
		
		// Display the current credits in the title
		char sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T\n-----\n%T\n", "Credits", param1, GetClientCredits(param1), "Are you sure?", param1);
		
		hPanel.SetTitle(sBuffer);
	}
	else if(action == MenuAction_DisplayItem)
	{
		/* Get the display string, we'll use it as a translation phrase */
		char sDisplay[64];
		menu.GetItem(param2, "", 0, _, sDisplay, sizeof(sDisplay));

		/* Translate the string to the client's language */
		char sBuffer[255];
		Format(sBuffer, sizeof(sBuffer), "%T", sDisplay, param1);

		/* Override the text */
		return RedrawMenuItem(sBuffer);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			g_hRPGTopMenu.Display(param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

public void TopMenu_HandleUpgradeSettings(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			InternalUpgradeInfo upgrade;
			if(!GetUpgradeByShortname(sShortname[16], upgrade))
				return;
			
			if(!IsValidUpgrade(upgrade) || !upgrade.enabled)
				return;
			
			// Show the team this upgrade is locked to, if it is.
			char sTeamlock[128];
			if((!IsClientInLockedTeam(param, upgrade) || upgrade.teamlock > 1 && g_hCVShowTeamlockNoticeOwnTeam.BoolValue) && upgrade.teamlock < GetTeamCount())
			{
				GetTeamName(upgrade.teamlock, sTeamlock, sizeof(sTeamlock));
				Format(sTeamlock, sizeof(sTeamlock), " (%T)", "Is teamlocked", param, sTeamlock);
			}
			
			int iPurchasedLevel = GetClientPurchasedUpgradeLevel(param, upgrade.index);
			int iSelectedLevel = GetClientSelectedUpgradeLevel(param, upgrade.index);
			
			char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
			GetUpgradeTranslatedName(param, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
			
			char sBuffer[128];
			if(!g_hCVDisableLevelSelection.BoolValue)
				Format(sBuffer, sizeof(sBuffer), "%T", "RPG menu upgrade settings entry level selection", param, sTranslatedName, iSelectedLevel, iPurchasedLevel, IsClientUpgradeEnabled(param, upgrade.index)?"On":"Off", sTeamlock);
			else
				Format(sBuffer, sizeof(sBuffer), "%T", "RPG menu upgrade settings entry", param, sTranslatedName, iSelectedLevel, IsClientUpgradeEnabled(param, upgrade.index)?"On":"Off", sTeamlock);
			strcopy(buffer, maxlength, sBuffer);
		}
		case TopMenuAction_DrawOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			InternalUpgradeInfo upgrade;
			// Don't show invalid upgrades at all in the menu.
			if(!GetUpgradeByShortname(sShortname[16], upgrade) || !IsValidUpgrade(upgrade) || !upgrade.enabled)
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			int iCurrentLevel = GetClientPurchasedUpgradeLevel(param, upgrade.index);
			
			// PRESTIGE CHECK: Always show purchased upgrades
			if (iCurrentLevel <= 0 && !IsUpgradeAvailableForPlayer(param, upgrade.index))
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			// Allow clients to view upgrades they no longer have access to, but don't show them, if they never bought it.
			if(!HasAccessToUpgrade(param, upgrade) && iCurrentLevel <= 0)
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			// Don't show the upgrade, if it's teamlocked, the client is in the wrong team and didn't buy it before.
			// Make sure to show it, if we're set to show all.
			if(!IsClientInLockedTeam(param, upgrade))
			{
				buffer[0] |= GetItemDrawFlagsForTeamlock(iCurrentLevel, false);
				return;
			}
		}
		case TopMenuAction_SelectOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			InternalUpgradeInfo upgrade;
			
			// Bad upgrade?
			if(!GetUpgradeByShortname(sShortname[16], upgrade) || !IsValidUpgrade(upgrade) || !upgrade.enabled)
			{
				g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
				return;
			}
			
			DisplayUpgradeSettingsMenu(param, upgrade.index);
		}
	}
}

void DisplayUpgradeSettingsMenu(int client, int iUpgradeIndex)
{
	Menu hMenu = new Menu(Menu_HandleUpgradeSettings);
	hMenu.ExitBackButton = true;

	char sTranslatedName[MAX_UPGRADE_NAME_LENGTH];
	GetUpgradeTranslatedName(client, iUpgradeIndex, sTranslatedName, sizeof(sTranslatedName));
	hMenu.SetTitle("%T\n-----\n%s\n", "Credits", client, GetClientCredits(client), sTranslatedName);
	
	PlayerUpgradeInfo playerupgrade;
	GetPlayerUpgradeInfoByIndex(client, iUpgradeIndex, playerupgrade);
	
	char sBuffer[64];
	Format(sBuffer, sizeof(sBuffer), "%T: %T", "Enabled", client, playerupgrade.enabled?"On":"Off", client);
	hMenu.AddItem("enable", sBuffer);
	
	if(!g_hCVDisableLevelSelection.BoolValue)
	{
		Format(sBuffer, sizeof(sBuffer), "%T: %d/%d", "Selected level", client, playerupgrade.selectedlevel, playerupgrade.purchasedlevel);
		hMenu.AddItem("", sBuffer, ITEMDRAW_DISABLED);
		Format(sBuffer, sizeof(sBuffer), "%T", "Increase selected level", client);
		hMenu.AddItem("incselect", sBuffer, playerupgrade.selectedlevel<playerupgrade.purchasedlevel?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
		Format(sBuffer, sizeof(sBuffer), "%T", "Decrease selected level", client);
		hMenu.AddItem("decselect", sBuffer, playerupgrade.selectedlevel>0?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}
	
	InternalUpgradeInfo upgrade;
	GetUpgradeByIndex(iUpgradeIndex, upgrade);
	
	bool bHasVisuals = upgrade.visualsConvar != null && upgrade.enableVisuals;
	bool bHasSounds = upgrade.soundsConvar != null && upgrade.enableSounds;
	
	if(bHasVisuals || bHasSounds)
	{
		hMenu.AddItem("", "", ITEMDRAW_SPACER);
		if(bHasVisuals)
		{
			Format(sBuffer, sizeof(sBuffer), "%T: %T", "Visual effects", client, playerupgrade.visuals?"On":"Off", client);
			hMenu.AddItem("visuals", sBuffer);
		}
		if(bHasSounds)
		{
			Format(sBuffer, sizeof(sBuffer), "%T: %T", "Sound effects", client, playerupgrade.sounds?"On":"Off", client);
			hMenu.AddItem("sounds", sBuffer);
		}
	}
	
	g_iSelectedSettingsUpgrade[client] = iUpgradeIndex;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandleUpgradeSettings(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		PlayerUpgradeInfo playerupgrade;
		GetPlayerUpgradeInfoByIndex(param1, g_iSelectedSettingsUpgrade[param1], playerupgrade);
		
		if(StrEqual(sInfo, "enable"))
		{
			SetClientUpgradeEnabledStatus(param1, g_iSelectedSettingsUpgrade[param1], playerupgrade.enabled?false:true);
		}
		else if(StrEqual(sInfo, "incselect"))
		{
			if(!g_hCVDisableLevelSelection.BoolValue)
				SetClientSelectedUpgradeLevel(param1, g_iSelectedSettingsUpgrade[param1], playerupgrade.selectedlevel+1);
		}
		else if(StrEqual(sInfo, "decselect"))
		{
			if(playerupgrade.selectedlevel > 0 && !g_hCVDisableLevelSelection.BoolValue)
				SetClientSelectedUpgradeLevel(param1, g_iSelectedSettingsUpgrade[param1], playerupgrade.selectedlevel-1);
		}
		else if(StrEqual(sInfo, "visuals"))
		{
			playerupgrade.visuals = playerupgrade.visuals?false:true;
			SavePlayerUpgradeInfo(param1, g_iSelectedSettingsUpgrade[param1], playerupgrade);
		}
		else if(StrEqual(sInfo, "sounds"))
		{
			playerupgrade.sounds = playerupgrade.sounds?false:true;
			SavePlayerUpgradeInfo(param1, g_iSelectedSettingsUpgrade[param1], playerupgrade);
		}
		
		DisplayUpgradeSettingsMenu(param1, g_iSelectedSettingsUpgrade[param1]);
	}
	else if(action == MenuAction_Cancel)
	{
		g_iSelectedSettingsUpgrade[param1] = -1;
		if(param2 == MenuCancel_ExitBack)
			g_hRPGTopMenu.Display(param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

void DisplayStatsMenu(int client)
{
	g_hRPGTopMenu.DisplayCategory(g_TopMenuStats, client);
}

public void TopMenu_HandleStats(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			char sName[64];
			topmenu.GetObjName(object_id, sName, sizeof(sName));
			
			if(StrEqual(sName, "level"))
			{
				Format(buffer, maxlength, "%T", "Level", param, GetClientLevel(param));
			}
			else if(StrEqual(sName, "exp"))
			{
				Format(buffer, maxlength, "%T", "Experience short", param, GetClientExperience(param), Stats_LvlToExp(GetClientLevel(param)));
			}
			else if(StrEqual(sName, "credits"))
			{
				Format(buffer, maxlength, "%T", "Credits", param, GetClientCredits(param));
			}
			else if(StrEqual(sName, "rank"))
			{
				Format(buffer, maxlength, "%T", "Rank", param, GetClientRank(param), GetRankCount());
			}
			else if(StrEqual(sName, "lastexp"))
			{
				Format(buffer, maxlength, "%T", "Last Experience", param);
			}
		}
		case TopMenuAction_DrawOption:
		{
			char sName[64];
			topmenu.GetObjName(object_id, sName, sizeof(sName));
			
			// HACKHACK: Don't disable the lastexp one
			if(!StrEqual(sName, "lastexp"))
			{
				// This is an informational panel only. Draw all items as disabled.
				buffer[0] = ITEMDRAW_DISABLED;
			}
		}
		case TopMenuAction_SelectOption:
		{
			char sName[64];
			topmenu.GetObjName(object_id, sName, sizeof(sName));
			
			if(StrEqual(sName, "lastexp"))
			{
				DisplaySessionLastExperienceMenu(param, true);
			}
		}
	}
}

void DisplaySettingsMenu(int client)
{
	g_hRPGTopMenu.DisplayCategory(g_TopMenuSettings, client);
}

public void TopMenu_HandleSettings(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	char sName[64];
	topmenu.GetObjName(object_id, sName, sizeof(sName));
	
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			if(StrEqual(sName, "resetstats"))
			{
				Format(buffer, maxlength, "%T", "Reset Stats", param);
			}
			else if(StrEqual(sName, "toggleautoshow"))
			{
				Format(buffer, maxlength, "%T: %T", "Show menu on levelup", param, ShowMenuOnLevelUp(param)?"Yes":"No", param);
			}
			else if(StrEqual(sName, "togglefade"))
			{
				Format(buffer, maxlength, "%T: %T", "Fade screen on levelup", param, FadeScreenOnLevelUp(param)?"Yes":"No", param);
			}
		}
		case TopMenuAction_DrawOption:
		{
			if(StrEqual(sName, "resetstats"))
			{
				// Don't show the reset stats option, if disabled.
				if(!g_hCVAllowSelfReset.BoolValue)
					buffer[0] = ITEMDRAW_IGNORE;
			}
		}
		case TopMenuAction_SelectOption:
		{
			if(StrEqual(sName, "resetstats"))
			{
				g_hConfirmResetStatsMenu.Display(param, MENU_TIME_FOREVER);
			}
			else if(StrEqual(sName, "toggleautoshow"))
			{
				SetShowMenuOnLevelUp(param, !ShowMenuOnLevelUp(param));
				g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
			}
			else if(StrEqual(sName, "togglefade"))
			{
				SetFadeScreenOnLevelUp(param, !FadeScreenOnLevelUp(param));
				g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
			}
		}
	}
}

public int Menu_ConfirmResetStats(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		
		if(StrEqual(sInfo, "no"))
		{
			g_hRPGTopMenu.Display(param1, TopMenuPosition_LastCategory);
			return 0;
		}
		
		// Are players allowed to reset themselves?
		// Player might still had the menu open while this setting changed.
		if(g_hCVAllowSelfReset.BoolValue)
		{
			ResetStats(param1);
			SetPlayerLastReset(param1, GetTime());
			
			Client_PrintToChat(param1, false, "%t", "Stats have been reset");
			LogMessage("%L reset his own rpg stats on purpose.", param1);
		}
		
		DisplaySettingsMenu(param1);
	}
	else if(action == MenuAction_Display)
	{
		// Change the title
		Panel hPanel = view_as<Panel>(param2);
		
		// Display the current credits in the title
		char sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "%T\n-----\n%T\n", "Credits", param1, GetClientCredits(param1), "Confirm stats reset", param1);
		
		hPanel.SetTitle(sBuffer);
	}
	else if(action == MenuAction_DisplayItem)
	{
		/* Get the display string, we'll use it as a translation phrase */
		char sDisplay[64];
		menu.GetItem(param2, "", 0, _, sDisplay, sizeof(sDisplay));

		/* Translate the string to the client's language */
		char sBuffer[255];
		Format(sBuffer, sizeof(sBuffer), "%T", sDisplay, param1);

		/* Override the text */
		return RedrawMenuItem(sBuffer);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			g_hRPGTopMenu.Display(param1, TopMenuPosition_LastCategory);
	}
	return 0;
}

void DisplayHelpMenu(int client)
{
	g_hRPGTopMenu.DisplayCategory(g_TopMenuHelp, client);
}

public void TopMenu_HandleHelp(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			InternalUpgradeInfo upgrade;
			if(!GetUpgradeByShortname(sShortname[8], upgrade))
				return;
			
			if(!IsValidUpgrade(upgrade) || !upgrade.enabled)
				return;
			
			// Show the team this upgrade is locked to, if it is.
			char sTeamlock[128];
			if((!IsClientInLockedTeam(param, upgrade) || upgrade.teamlock > 1 && g_hCVShowTeamlockNoticeOwnTeam.BoolValue) && upgrade.teamlock < GetTeamCount())
			{
				GetTeamName(upgrade.teamlock, sTeamlock, sizeof(sTeamlock));
				Format(sTeamlock, sizeof(sTeamlock), " (%T)", "Is teamlocked", param, sTeamlock);
			}
			
			char sDescription[MAX_UPGRADE_DESCRIPTION_LENGTH];
			GetUpgradeTranslatedName(param, upgrade.index, sDescription, sizeof(sDescription));
			
			Format(buffer, maxlength, "%s%s", sDescription, sTeamlock);
		}
		case TopMenuAction_DrawOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			InternalUpgradeInfo upgrade;
			// Don't show invalid upgrades at all in the menu.
			if(!GetUpgradeByShortname(sShortname[8], upgrade) || !IsValidUpgrade(upgrade) || !upgrade.enabled)
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			int iCurrentLevel = GetClientPurchasedUpgradeLevel(param, upgrade.index);
			
			// NEW: Only show upgrades that are available for current prestige/level
			// OR upgrades that the player has already purchased
			if (!IsUpgradeAvailableForPlayer(param, upgrade.index) && iCurrentLevel <= 0)
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			// Allow clients to read help about upgrades they no longer have access to, but don't show them, if they never bought it.
			if(!HasAccessToUpgrade(param, upgrade) && iCurrentLevel <= 0)
			{
				buffer[0] = ITEMDRAW_IGNORE;
				return;
			}
			
			// Don't show the upgrade, if it's teamlocked, the client is in the wrong team and didn't buy the upgrade before.
			// Make sure to show it, if we're set to show all.
			if(!IsClientInLockedTeam(param, upgrade))
			{
				buffer[0] |= GetItemDrawFlagsForTeamlock(iCurrentLevel, false);
				return;
			}
		}
		case TopMenuAction_SelectOption:
		{
			char sShortname[MAX_UPGRADE_SHORTNAME_LENGTH];
			topmenu.GetObjName(object_id, sShortname, sizeof(sShortname));
			
			InternalUpgradeInfo upgrade;
			
			// Bad upgrade?
			if(!GetUpgradeByShortname(sShortname[8], upgrade) || !IsValidUpgrade(upgrade) || !upgrade.enabled)
			{
				g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
				return;
			}
			
			char sTranslatedName[MAX_UPGRADE_NAME_LENGTH], sTranslatedDescription[MAX_UPGRADE_DESCRIPTION_LENGTH];
			GetUpgradeTranslatedName(param, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
			GetUpgradeTranslatedDescription(param, upgrade.index, sTranslatedDescription, sizeof(sTranslatedDescription));
			
			Client_PrintToChat(param, false, "{OG}SM:RPG{N} > {G}%s{N}: %s", sTranslatedName, sTranslatedDescription);
			
			g_hRPGTopMenu.Display(param, TopMenuPosition_LastCategory);
		}
	}
}

void DisplayOtherUpgradesMenu(int client, int targetClient)
{
    Menu hMenu = new Menu(Menu_HandleOtherUpgrades);
    hMenu.ExitBackButton = true;
    
    hMenu.SetTitle("%N\n%T\n-----\n", targetClient, "Credits", client, GetClientCredits(targetClient));
    
    int iSize = GetUpgradeCount();
    InternalUpgradeInfo upgrade;
    int iCurrentLevel;
    char sTranslatedName[MAX_UPGRADE_NAME_LENGTH], sLine[128], sIndex[8];
    for(int i=0;i<iSize;i++)
    {
        iCurrentLevel = GetClientPurchasedUpgradeLevel(targetClient, i);
        GetUpgradeByIndex(i, upgrade);
        
        // Don't show disabled items in the menu.
        if(!IsValidUpgrade(upgrade) || !upgrade.enabled || !HasAccessToUpgrade(targetClient, upgrade) || !IsClientInLockedTeam(targetClient, upgrade))
            continue;
        
        // NEW: Check if upgrade is available for target's prestige/level
        if (!IsUpgradeAvailableForPlayer(targetClient, i) && iCurrentLevel <= 0)
            continue;
        
        GetUpgradeTranslatedName(client, upgrade.index, sTranslatedName, sizeof(sTranslatedName));
        
        if(iCurrentLevel >= upgrade.maxLevel)
        {
            Format(sLine, sizeof(sLine), "%T", "RPG menu other players upgrades entry max level", client, sTranslatedName, iCurrentLevel);
        }
        // Optionally show the maxlevel of the upgrade
        else if (g_hCVShowMaxLevelInMenu.BoolValue)
        {
            Format(sLine, sizeof(sLine), "%T", "RPG menu other players upgrades entry show max", client, sTranslatedName, iCurrentLevel, upgrade.maxLevel);
        }
        else
        {
            Format(sLine, sizeof(sLine), "%T", "RPG menu other players upgrades entry", client, sTranslatedName, iCurrentLevel);
        }

        IntToString(i, sIndex, sizeof(sIndex));
        hMenu.AddItem(sIndex, sLine, ITEMDRAW_DISABLED);
    }
    
    hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_HandleOtherUpgrades(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

// Helper functions to access those pubvars before they are declared..
TopMenu GetRPGTopMenu()
{
	return g_hRPGTopMenu;
}

TopMenuObject GetUpgradesCategory()
{
	return g_TopMenuUpgrades;
}

TopMenuObject GetSellCategory()
{
	return g_TopMenuSell;
}

TopMenuObject GetUpgradeSettingsCategory()
{
	return g_TopMenuUpgradeSettings;
}

TopMenuObject GetHelpCategory()
{
	return g_TopMenuHelp;
}

// Handle the logic of the smrpg_show_upgrades_teamlock convar.
int GetItemDrawFlagsForTeamlock(int iLevel, bool bBuyMenu)
{
	int iShowTeamlock = g_hCVShowUpgradesOfOtherTeam.IntValue;
	switch(iShowTeamlock)
	{
		case SHOW_TEAMLOCK_NONE:
		{
			return ITEMDRAW_IGNORE;
		}
		case SHOW_TEAMLOCK_BOUGHT:
		{
			// The client bought it while being in the other team.
			if(iLevel > 0)
			{
				// Show it, but don't let him buy it.
				if(bBuyMenu && !g_hCVBuyUpgradesOfOtherTeam.BoolValue)
				{
					return ITEMDRAW_DISABLED;
				}
				// else let him use it.
			}
			// The client doesn't have the upgrade. Don't show it.
			else
			{
				return ITEMDRAW_IGNORE;
			}
		}
		case SHOW_TEAMLOCK_ALL:
		{
			// Show it, but don't let him buy it.
			if(bBuyMenu && !g_hCVBuyUpgradesOfOtherTeam.BoolValue)
			{
				return ITEMDRAW_DISABLED;
			}
			// else let him use it.
		}
	}
	return 0;
}

bool IsUpgradeAvailableForPlayer(int client, int upgradeIndex)
{
    int iTotalUpgrades = GetUpgradeCount();
    if (upgradeIndex < 0 || upgradeIndex >= iTotalUpgrades)
    {
        return false;
    }
    
    InternalUpgradeInfo upgrade;
    if (!GetUpgradeByIndex(upgradeIndex, upgrade) || !IsValidUpgrade(upgrade))
    {
        return false;
    }
    int iPurchasedLevel = GetClientPurchasedUpgradeLevel(client, upgradeIndex);
    if (iPurchasedLevel > 0)
    {
        return true;
    }
    int iPrestige = SMRPG_GetClientPrestigeLevel(client);
    int iLevel = SMRPG_GetClientLevel(client);
    if (iPrestige < 0 || iPrestige >= MAXPRESTIGE)
    {
        return false;
    }
    
    if (g_hPrestigeUpgrades[iPrestige] == null)
    {
        LoadPrestigeUpgrades();
        
        if (g_hPrestigeUpgrades[iPrestige] == null)
        {
            return true;
        }
    }
    
    int iSize = g_hPrestigeUpgrades[iPrestige].Length;
    if (iSize == 0)
    {
        return true;
    }
    PrestigeUpgradeInfo upgradeInfo;
    bool foundInCurrentPrestige = false;
    
    for (int i = 0; i < iSize; i++)
    {
        g_hPrestigeUpgrades[iPrestige].GetArray(i, upgradeInfo);
        
        if (StrEqual(upgradeInfo.shortName, upgrade.shortName, false))
        {
            foundInCurrentPrestige = true;
            if (iLevel >= upgradeInfo.requiredLevel)
            {
                return true;
            }
            else
            {
                return false;
            }
        }
    }
    return false;
}