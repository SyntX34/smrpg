#pragma semicolon 1
#include <sourcemod>
#include <smrpg>
#include <sdkhooks>
#include <multicolors>

#pragma newdecls required

#define MAX_PRESTIGE 8
#define MAX_UPGRADE_SLOTS 10
#define CONFIG_PATH "configs/smrpg/prestige.cfg"
ConVar g_cvPrestigeEnabled;
ConVar g_cvPrestigeRequiredLevel;
ConVar g_cvPrestigeMaxLevel;
KeyValues g_kvPrestigeConfig;
enum struct UpgradeRestriction
{
    int minLevel;
    char upgradeName[32];
}

ArrayList g_hUpgradeRestrictions[MAX_PRESTIGE + 1];
bool g_bPrestigeDeclined[MAXPLAYERS + 1];

float g_fClientXPMultiplier[MAXPLAYERS + 1];
float g_fClientCreditMultiplier[MAXPLAYERS + 1];

public Plugin myinfo = 
{
    name = "SM:RPG Prestige System",
    author = "+SyntX",
    description = "Advanced prestige system for SM:RPG",
    version = "1.0.0",
    url = ""
};

public void OnPluginStart()
{
    for(int i = 0; i <= MaxClients; i++)
    {
        g_fClientXPMultiplier[i] = 1.0;
        g_fClientCreditMultiplier[i] = 1.0;
    }
    RegConsoleCmd("sm_prestige", Command_Prestige, "Check your prestige status or prestige");
    RegConsoleCmd("sm_prestigestatus", Command_PrestigeStatus, "Check your prestige status");
    RegAdminCmd("sm_setprestige", Command_SetPrestige, ADMFLAG_ROOT, "Set a player's prestige level");
    g_cvPrestigeEnabled = CreateConVar("smrpg_prestige_enabled", "1", "Enable prestige system", FCVAR_NOTIFY);
    g_cvPrestigeRequiredLevel = CreateConVar("smrpg_prestige_required_level", "1500", "Level required to prestige", FCVAR_NOTIFY);
    g_cvPrestigeMaxLevel = CreateConVar("smrpg_prestige_max_level", "1500", "Max level for each prestige", FCVAR_NOTIFY);
    for(int i = 0; i <= MAX_PRESTIGE; i++)
    {
        g_hUpgradeRestrictions[i] = new ArrayList(sizeof(UpgradeRestriction));
    }
    LoadPrestigeConfig();
    AutoExecConfig(true, "smrpg_prestige");
    HookEvent("player_spawn", Event_PlayerSpawn);
    AddCommandListener(CommandListener_Say, "say");
    AddCommandListener(CommandListener_Say, "say2");
}

public void OnClientPutInServer(int client)
{
    g_bPrestigeDeclined[client] = false;
    g_fClientXPMultiplier[client] = 1.0;
    g_fClientCreditMultiplier[client] = 1.0;
}

void LoadPrestigeConfig()
{
    char configPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configPath, sizeof(configPath), CONFIG_PATH);
    
    g_kvPrestigeConfig = new KeyValues("Prestige");
    
    if(!g_kvPrestigeConfig.ImportFromFile(configPath))
    {
        LogError("Could not load prestige configuration from %s", configPath);
        LogMessage("Please create a configuration file at %s", configPath);
        return;
    }
    ParseUpgradeRestrictions();
    
    LogMessage("Loaded prestige configuration from %s", configPath);
}

void ParseUpgradeRestrictions()
{
    for(int prestige = 0; prestige <= MAX_PRESTIGE; prestige++)
    {
        char prestigeKey[4];
        IntToString(prestige, prestigeKey, sizeof(prestigeKey));
        
        g_kvPrestigeConfig.Rewind();
        if(g_kvPrestigeConfig.JumpToKey(prestigeKey))
        {
            g_hUpgradeRestrictions[prestige].Clear();
            
            if(g_kvPrestigeConfig.JumpToKey("upgrades"))
            {
                if(g_kvPrestigeConfig.GotoFirstSubKey(false))
                {
                    do
                    {
                        char levelKey[32];
                        g_kvPrestigeConfig.GetSectionName(levelKey, sizeof(levelKey));
                        int minLevel = StringToInt(levelKey);
                        
                        char upgradeList[256];
                        g_kvPrestigeConfig.GetString(NULL_STRING, upgradeList, sizeof(upgradeList));
                        
                        char upgrades[32][32];
                        int upgradeCount = ExplodeString(upgradeList, ",", upgrades, sizeof(upgrades), sizeof(upgrades[]));
                        
                        for(int i = 0; i < upgradeCount; i++)
                        {
                            TrimString(upgrades[i]);
                            if(strlen(upgrades[i]) > 0)
                            {
                                UpgradeRestriction restriction;
                                restriction.minLevel = minLevel;
                                strcopy(restriction.upgradeName, sizeof(restriction.upgradeName), upgrades[i]);
                                g_hUpgradeRestrictions[prestige].PushArray(restriction);
                            }
                        }
                    } while(g_kvPrestigeConfig.GotoNextKey(false));
                    
                    g_kvPrestigeConfig.GoBack();
                }
                g_kvPrestigeConfig.GoBack();
            }
            g_kvPrestigeConfig.GoBack();
        }
    }
}

public void OnClientPostAdminCheck(int client)
{
    if(IsFakeClient(client)) return;
    
    ApplyPrestigeConfig(client);
}

void ApplyPrestigeConfig(int client)
{
    int prestigeLevel = SMRPG_GetClientPrestigeLevel(client);
    char prestigeKey[4];
    IntToString(prestigeLevel, prestigeKey, sizeof(prestigeKey));
    
    g_kvPrestigeConfig.Rewind();
    
    if(g_kvPrestigeConfig.JumpToKey(prestigeKey))
    {
        int maxLevel = g_kvPrestigeConfig.GetNum("max_level", g_cvPrestigeMaxLevel.IntValue);
        SMRPG_SetClientPrestigeMaxLevel(client, maxLevel);
        
        float xpMultiplier = g_kvPrestigeConfig.GetFloat("xp_multiplier", 1.0);
        
        if(GetFeatureStatus(FeatureType_Native, "SMRPG_SetClientPrestigeXPMultiplier") == FeatureStatus_Available)
        {
            SMRPG_SetClientPrestigeXPMultiplier(client, xpMultiplier);
        }
        else
        {
            g_fClientXPMultiplier[client] = xpMultiplier;
        }
        
        float creditMultiplier = g_kvPrestigeConfig.GetFloat("credit_multiplier", 1.0);
        
        if(GetFeatureStatus(FeatureType_Native, "SMRPG_SetClientPrestigeCreditMultiplier") == FeatureStatus_Available)
        {
            SMRPG_SetClientPrestigeCreditMultiplier(client, creditMultiplier);
        }
        else
        {
            g_fClientCreditMultiplier[client] = creditMultiplier;
        }
    }
}

public void OnClientLevel(int client, int oldlevel, int newlevel)
{
    if(!g_cvPrestigeEnabled.BoolValue)
        return;
    
    int requiredLevel = g_cvPrestigeRequiredLevel.IntValue;
    int prestigeLevel = SMRPG_GetClientPrestigeLevel(client);
    
    if(newlevel >= requiredLevel && oldlevel < requiredLevel && 
       prestigeLevel < MAX_PRESTIGE && !g_bPrestigeDeclined[client])
    {
        ShowPrestigeOffer(client);
    }
}

void ShowPrestigeOffer(int client)
{
    Menu menu = new Menu(MenuHandler_PrestigeOffer);
    
    char title[256];
    int currentPrestige = SMRPG_GetClientPrestigeLevel(client);
    int nextPrestige = currentPrestige + 1;
    
    Format(title, sizeof(title), "Prestige Opportunity!\n \nYou've reached level %d!\n \nCurrent: Prestige %d\nNext: Prestige %d\n \nBenefits of Prestige %d:", 
        g_cvPrestigeRequiredLevel.IntValue,
        currentPrestige,
        nextPrestige,
        nextPrestige);
    
    menu.SetTitle(title);
    
    char prestigeKey[4];
    IntToString(nextPrestige, prestigeKey, sizeof(prestigeKey));
    
    char buffer[128];
    g_kvPrestigeConfig.Rewind();
    if(g_kvPrestigeConfig.JumpToKey(prestigeKey))
    {
        float xpMultiplier = g_kvPrestigeConfig.GetFloat("xp_multiplier", 1.0);
        Format(buffer, sizeof(buffer), "• XP Rate: %.0f percent", xpMultiplier * 100);
        menu.AddItem("", buffer, ITEMDRAW_DISABLED);
        
        float creditMultiplier = g_kvPrestigeConfig.GetFloat("credit_multiplier", 1.0);
        Format(buffer, sizeof(buffer), "• Credit Bonus: +%.0f percent", (creditMultiplier - 1.0) * 100);
        menu.AddItem("", buffer, ITEMDRAW_DISABLED);
        
        Format(buffer, sizeof(buffer), "• New upgrades unlocked");
        menu.AddItem("", buffer, ITEMDRAW_DISABLED);
        
        g_kvPrestigeConfig.GoBack();
    }
    
    Format(buffer, sizeof(buffer), "\nNote: Prestiging will reset you to level 1");
    menu.AddItem("", buffer, ITEMDRAW_DISABLED);
    
    menu.AddItem("", "", ITEMDRAW_SPACER);
    menu.AddItem("yes", "Yes, prestige now!");
    menu.AddItem("no", "Not right now");
    menu.AddItem("info", "More information");
    
    menu.ExitButton = false;
    menu.Display(client, 30);
}

public int MenuHandler_PrestigeOffer(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrEqual(info, "yes"))
        {
            PerformPrestige(client);
        }
        else if(StrEqual(info, "no"))
        {
            HandlePrestigeDecline(client);
        }
        else if(StrEqual(info, "info"))
        {
            ShowPrestigeInfo(client);
        }
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
}

void HandlePrestigeDecline(int client)
{
    g_bPrestigeDeclined[client] = true;
    
    int currentPrestige = SMRPG_GetClientPrestigeLevel(client);
    int nextPrestige = currentPrestige + 1;
    
    CPrintToChat(client, "{green}[Prestige]{default} You have chosen to stay at {green}Prestige %d{default}.", currentPrestige);
    CPrintToChat(client, "{green}[Prestige]{default} You can continue leveling up, but you will not receive benefits from Prestige %d.", nextPrestige);
    CPrintToChat(client, "{green}[Prestige]{default} Type {lightgreen}!prestige{default} at any time to prestige.");
    
    char prestigeKey[4];
    IntToString(nextPrestige, prestigeKey, sizeof(prestigeKey));
    
    g_kvPrestigeConfig.Rewind();
    if(g_kvPrestigeConfig.JumpToKey(prestigeKey))
    {
        float xpMultiplier = g_kvPrestigeConfig.GetFloat("xp_multiplier", 1.0);
        float creditMultiplier = g_kvPrestigeConfig.GetFloat("credit_multiplier", 1.0);
        
        CPrintToChat(client, "{green}[Prestige]{default} You're missing: {lightgreen}%.0f percent XP{default} and {lightgreen}+%.0f percent credits{default}",
            xpMultiplier * 100, (creditMultiplier - 1.0) * 100);
    }
}

void ShowPrestigeInfo(int client)
{
    Menu menu = new Menu(MenuHandler_PrestigeInfo);
    
    char title[256];
    int nextPrestige = SMRPG_GetClientPrestigeLevel(client) + 1;
    Format(title, sizeof(title), "Prestige Information\n \nPrestige Level %d Benefits:\n", nextPrestige);
    
    menu.SetTitle(title);
    
    char buffer[256];
    
    char prestigeKey[4];
    IntToString(nextPrestige, prestigeKey, sizeof(prestigeKey));
    
    g_kvPrestigeConfig.Rewind();
    if(g_kvPrestigeConfig.JumpToKey(prestigeKey))
    {
        float xpMultiplier = g_kvPrestigeConfig.GetFloat("xp_multiplier", 1.0);
        Format(buffer, sizeof(buffer), "XP Rate: %.0f percent", xpMultiplier * 100);
        menu.AddItem("", buffer, ITEMDRAW_DISABLED);
        
        float creditMultiplier = g_kvPrestigeConfig.GetFloat("credit_multiplier", 1.0);
        Format(buffer, sizeof(buffer), "Credit Bonus: +%.0f percent", (creditMultiplier - 1.0) * 100);
        menu.AddItem("", buffer, ITEMDRAW_DISABLED);
        
        int maxLevel = g_kvPrestigeConfig.GetNum("max_level", 1500);
        Format(buffer, sizeof(buffer), "Max Level: %d", maxLevel);
        menu.AddItem("", buffer, ITEMDRAW_DISABLED);
        
        if(g_kvPrestigeConfig.JumpToKey("upgrades"))
        {
            if(g_kvPrestigeConfig.GotoFirstSubKey(false))
            {
                char levelKey[32];
                g_kvPrestigeConfig.GetSectionName(levelKey, sizeof(levelKey));
                
                char upgradeList[256];
                g_kvPrestigeConfig.GetString(NULL_STRING, upgradeList, sizeof(upgradeList));
                
                char upgrades[32][32];
                int upgradeCount = ExplodeString(upgradeList, ",", upgrades, sizeof(upgrades), sizeof(upgrades[]));
                
                if(upgradeCount > 0)
                {
                    Format(buffer, sizeof(buffer), "Unlocks at Lvl %s: %s", levelKey, upgrades[0]);
                    if(upgradeCount > 1)
                    {
                        Format(buffer, sizeof(buffer), "%s, %s", buffer, upgrades[1]);
                    }
                    if(upgradeCount > 2)
                    {
                        Format(buffer, sizeof(buffer), "%s, ...", buffer);
                    }
                    menu.AddItem("", buffer, ITEMDRAW_DISABLED);
                }
                
                g_kvPrestigeConfig.GoBack();
            }
            g_kvPrestigeConfig.GoBack();
        }
    }
    
    menu.AddItem("", "", ITEMDRAW_SPACER);
    menu.AddItem("back", "Back to Prestige Offer");
    menu.AddItem("prestige", "Prestige Now!");
    
    menu.Display(client, 30);
}

public int MenuHandler_PrestigeInfo(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrEqual(info, "back"))
        {
            ShowPrestigeOffer(client);
        }
        else if(StrEqual(info, "prestige"))
        {
            PerformPrestige(client);
        }
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
}

void PerformPrestige(int client)
{
    int currentPrestige = SMRPG_GetClientPrestigeLevel(client);
    int newPrestige = currentPrestige + 1;
    
    if(newPrestige > MAX_PRESTIGE)
    {
        CPrintToChat(client, "{green}[Prestige]{default} You've already reached the maximum prestige level!");
        return;
    }
    
    if(SMRPG_ResetClientToPrestige(client, newPrestige))
    {
        g_bPrestigeDeclined[client] = false;
        ApplyPrestigeConfig(client);
        CPrintToChat(client, "{green}[Prestige]{default} Congratulations! You are now {green}Prestige %d{default}!", newPrestige);
        CPrintToChat(client, "{green}[Prestige]{default} Your stats have been reset. New journey begins!");
        UpdateUpgradeVisibility(client);
    }
    else
    {
        CPrintToChat(client, "{green}[Prestige]{default} Prestige failed. Please try again.");
    }
}

public Action Command_Prestige(int client, int args)
{
    if(!client)
        return Plugin_Handled;
    
    if(!g_cvPrestigeEnabled.BoolValue)
    {
        ReplyToCommand(client, "Prestige system is disabled.");
        return Plugin_Handled;
    }
    
    if(args == 0)
    {
        int currentLevel = SMRPG_GetClientLevel(client);
        int requiredLevel = g_cvPrestigeRequiredLevel.IntValue;
        int prestigeLevel = SMRPG_GetClientPrestigeLevel(client);
        
        if(currentLevel >= requiredLevel && prestigeLevel < MAX_PRESTIGE)
        {
            ShowPrestigeOffer(client);
        }
        else
        {
            ShowPrestigeStatus(client);
        }
        return Plugin_Handled;
    }
    if(CheckCommandAccess(client, "sm_setprestige", ADMFLAG_ROOT))
    {
        char arg[32];
        GetCmdArg(1, arg, sizeof(arg));
        
        int target = FindTarget(client, arg, true, false);
        if(target == -1)
            return Plugin_Handled;
        
        if(args > 1)
        {
            char levelStr[4];
            GetCmdArg(2, levelStr, sizeof(levelStr));
            int level = StringToInt(levelStr);
            
            if(level < 0 || level > MAX_PRESTIGE)
            {
                ReplyToCommand(client, "Invalid prestige level. Must be 0-%d.", MAX_PRESTIGE);
                return Plugin_Handled;
            }
            
            SMRPG_SetClientPrestigeLevel(target, level);
            ApplyPrestigeConfig(target);
            UpdateUpgradeVisibility(target);
            g_bPrestigeDeclined[target] = false;
            
            ReplyToCommand(client, "Set %N's prestige to level %d.", target, level);
            CPrintToChat(target, "{green}[Prestige]{default} Your prestige level has been set to {green}%d{default} by an admin.", level);
        }
        else
        {
            PerformPrestige(target);
        }
    }
    
    return Plugin_Handled;
}

public Action Command_PrestigeStatus(int client, int args)
{
    if(!client)
        return Plugin_Handled;
    
    ShowPrestigeStatus(client);
    return Plugin_Handled;
}

void ShowPrestigeStatus(int client)
{
    int prestigeLevel = SMRPG_GetClientPrestigeLevel(client);
    int currentLevel = SMRPG_GetClientLevel(client);
    int maxLevel = SMRPG_GetClientPrestigeMaxLevel(client);
    
    Panel panel = new Panel();
    
    char buffer[256];
    Format(buffer, sizeof(buffer), "Prestige Status - %N", client);
    panel.SetTitle(buffer);
    
    panel.DrawText(" ");
    Format(buffer, sizeof(buffer), "Current Level: %d", currentLevel);
    panel.DrawText(buffer);
    
    Format(buffer, sizeof(buffer), "Prestige Level: %d/%d", prestigeLevel, MAX_PRESTIGE);
    panel.DrawText(buffer);
    
    panel.DrawText(" ");
    
    if(prestigeLevel < MAX_PRESTIGE)
    {
        if(maxLevel > 0)
        {
            Format(buffer, sizeof(buffer), "Next Prestige at: Level %d", maxLevel);
            panel.DrawText(buffer);
            
            int progress = currentLevel * 100 / maxLevel;
            Format(buffer, sizeof(buffer), "Progress: %d percent (%d/%d)", progress, currentLevel, maxLevel);
            panel.DrawText(buffer);
            
            if(currentLevel >= maxLevel)
            {
                panel.DrawText(" ");
                panel.DrawText("You can prestige now!");
                panel.DrawText("Type !prestige to begin");
            }
        }
    }
    else
    {
        panel.DrawText("MAX PRESTIGE ACHIEVED!");
        panel.DrawText("You have reached the highest");
        panel.DrawText("prestige level possible!");
    }
    
    panel.DrawText(" ");
    panel.DrawItem("Close");
    
    panel.Send(client, MenuHandler_PrestigeStatus, 30);
    delete panel;
}

public int MenuHandler_PrestigeStatus(Menu menu, MenuAction action, int client, int param2)
{
    return 0;
}

public Action Command_SetPrestige(int client, int args)
{
    if(!CheckCommandAccess(client, "sm_setprestige", ADMFLAG_ROOT))
    {
        ReplyToCommand(client, "You do not have access to this command.");
        return Plugin_Handled;
    }
    
    if(args < 2)
    {
        ReplyToCommand(client, "Usage: sm_setprestige <player> <level 0-8>");
        return Plugin_Handled;
    }
    
    char targetName[MAX_TARGET_LENGTH];
    char arg1[32], arg2[4];
    
    GetCmdArg(1, arg1, sizeof(arg1));
    GetCmdArg(2, arg2, sizeof(arg2));
    
    int target = FindTarget(client, arg1, true, false);
    if(target == -1)
        return Plugin_Handled;
    
    int level = StringToInt(arg2);
    if(level < 0 || level > MAX_PRESTIGE)
    {
        ReplyToCommand(client, "Invalid prestige level. Must be 0-%d.", MAX_PRESTIGE);
        return Plugin_Handled;
    }
    
    SMRPG_SetClientPrestigeLevel(target, level);
    ApplyPrestigeConfig(target);
    UpdateUpgradeVisibility(target);
    
    ReplyToCommand(client, "Set %N's prestige to level %d.", target, level);
    CPrintToChat(target, "{green}[Prestige]{default} Your prestige level has been set to {green}%d{default} by an admin.", level);
    
    return Plugin_Handled;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if(!IsValidClient(client) || IsFakeClient(client))
        return;
    
    UpdateUpgradeVisibility(client);
}

public Action CommandListener_Say(int client, const char[] command, int argc)
{
    if(!IsValidClient(client))
        return Plugin_Continue;
    
    char text[192];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);
    TrimString(text);
    
    if(StrEqual(text, "!upgrades", false) || StrEqual(text, "!items", false) || 
       StrEqual(text, "/upgrades", false) || StrEqual(text, "/items", false))
    {
        ShowRestrictedUpgradesMenu(client);
        return Plugin_Handled;
    }
    
    return Plugin_Continue;
}

void ShowRestrictedUpgradesMenu(int client)
{
    int prestigeLevel = SMRPG_GetClientPrestigeLevel(client);
    int playerLevel = SMRPG_GetClientLevel(client);
    
    Menu menu = new Menu(MenuHandler_Upgrades);
    menu.SetTitle("Available Upgrades\nPrestige %d | Level %d\n ", prestigeLevel, playerLevel);
    ArrayList availableUpgrades = GetAvailableUpgrades(client);
    SortADTArray(availableUpgrades, Sort_Ascending, Sort_String);
    
    char upgradeName[32], display[64];
    for(int i = 0; i < availableUpgrades.Length; i++)
    {
        availableUpgrades.GetString(i, upgradeName, sizeof(upgradeName));
        int currentLevel = SMRPG_GetClientPurchasedUpgradeLevel(client, upgradeName);
        int maxLevel = GetUpgradeMaxLevel(upgradeName);
        
        Format(display, sizeof(display), "%s (Lvl %d/%d)", upgradeName, currentLevel, maxLevel);
        int unlockLevel = GetUpgradeUnlockLevel(client, upgradeName);
        if(playerLevel >= unlockLevel)
        {
            menu.AddItem(upgradeName, display);
        }
        else
        {
            Format(display, sizeof(display), "%s (Unlocks at Lvl %d)", upgradeName, unlockLevel);
            menu.AddItem("", display, ITEMDRAW_DISABLED);
        }
    }
    
    delete availableUpgrades;
    
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

ArrayList GetAvailableUpgrades(int client)
{
    int prestigeLevel = SMRPG_GetClientPrestigeLevel(client);
    int playerLevel = SMRPG_GetClientLevel(client);
    
    ArrayList upgrades = new ArrayList(ByteCountToCells(32));
    for(int i = 0; i < g_hUpgradeRestrictions[prestigeLevel].Length; i++)
    {
        UpgradeRestriction restriction;
        g_hUpgradeRestrictions[prestigeLevel].GetArray(i, restriction);
        if(playerLevel >= restriction.minLevel)
        {
            if(upgrades.FindString(restriction.upgradeName) == -1)
            {
                upgrades.PushString(restriction.upgradeName);
            }
        }
    }
    
    return upgrades;
}

int GetUpgradeUnlockLevel(int client, const char[] upgradeName)
{
    int prestigeLevel = SMRPG_GetClientPrestigeLevel(client);
    
    for(int i = 0; i < g_hUpgradeRestrictions[prestigeLevel].Length; i++)
    {
        UpgradeRestriction restriction;
        g_hUpgradeRestrictions[prestigeLevel].GetArray(i, restriction);
        
        if(StrEqual(restriction.upgradeName, upgradeName))
        {
            return restriction.minLevel;
        }
    }
    
    return 9999;
}

int GetUpgradeMaxLevel(const char[] upgradeName)
{
    return 10;
}

public int MenuHandler_Upgrades(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char upgradeName[32];
        menu.GetItem(param2, upgradeName, sizeof(upgradeName));
        
        ShowUpgradeInfo(client, upgradeName);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
}

void ShowUpgradeInfo(int client, const char[] upgradeName)
{
    int currentLevel = SMRPG_GetClientPurchasedUpgradeLevel(client, upgradeName);
    int maxLevel = GetUpgradeMaxLevel(upgradeName);
    int unlockLevel = GetUpgradeUnlockLevel(client, upgradeName);
    int playerLevel = SMRPG_GetClientLevel(client);
    
    Panel panel = new Panel();
    
    char buffer[256];
    Format(buffer, sizeof(buffer), "Upgrade: %s", upgradeName);
    panel.SetTitle(buffer);
    
    panel.DrawText(" ");
    Format(buffer, sizeof(buffer), "Current Level: %d/%d", currentLevel, maxLevel);
    panel.DrawText(buffer);
    
    if(playerLevel >= unlockLevel)
    {
        Format(buffer, sizeof(buffer), "Status: Available");
        panel.DrawText(buffer);
    }
    else
    {
        Format(buffer, sizeof(buffer), "Status: Unlocks at Level %d", unlockLevel);
        panel.DrawText(buffer);
    }
    
    panel.DrawText(" ");
    panel.DrawText("Description:");
    panel.DrawText("Upgrade description would go here");
    
    panel.DrawText(" ");
    panel.DrawItem("Back");
    panel.DrawItem("Close");
    
    panel.Send(client, MenuHandler_UpgradeInfo, 30);
    delete panel;
}

public int MenuHandler_UpgradeInfo(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        if(param2 == 1) // Back
        {
            ShowRestrictedUpgradesMenu(client);
        }
    }
}

void UpdateUpgradeVisibility(int client)
{
    ApplyPrestigeConfig(client);
}

bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

public void OnPluginEnd()
{
    if(g_kvPrestigeConfig != null)
    {
        delete g_kvPrestigeConfig;
    }
    
    for(int i = 0; i <= MAX_PRESTIGE; i++)
    {
        delete g_hUpgradeRestrictions[i];
    }
}