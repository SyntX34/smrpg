#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <smrpg>
#include <multicolors>
#include <clientprefs>
#include <discordWebhookAPI>

#if defined _zr_included
#include <zombiereloaded>
#else
#undef REQUIRE_PLUGIN
#tryinclude <zombiereloaded>
#define REQUIRE_PLUGIN
#endif

#if defined _zombieriot_included
#include <zriot>
#else
#undef REQUIRE_PLUGIN
#tryinclude <zombieriot>
#define REQUIRE_PLUGIN
#endif

#if defined _shop_included
#include <shop>
#else
#undef REQUIRE_PLUGIN
#tryinclude <shop>
#define REQUIRE_PLUGIN
#endif

#pragma newdecls required

#define CONFIG_PATH "configs/smrpg/prestige.cfg"
#define DOWNLOADS_PATH "configs/smrpg/prestige_downloads.txt"

#define MPS MAXPLAYERS+1
#define PMP PLATFORM_MAX_PATH

ConVar g_cvPrestigeEnabled;
ConVar g_cvPrestigeDebug;
ConVar g_cvPrestigeSounds;
ConVar g_cvPrestigeModels;
ConVar g_cvDiscordEnable;
ConVar g_cvDiscordWebhook;

KeyValues g_kvPrestigeConfig;

enum struct UpgradeRestriction
{
	int minLevel;
	char upgradeName[32];
}

enum struct PrestigeSound
{
	char name[64];
	char path[PMP];
}

enum struct PrestigeModel
{
	char name[64];
	char path[PMP];
	int team; // 0 = CT, 1 = T, 2 = Both
}

enum struct PrestigeInfo
{
	char name[64];
	int max_level;
	float xp_multiplier;
	float credit_multiplier;
}

PrestigeInfo g_PrestigeInfo[32];
ArrayList g_hUpgradeRestrictions[32];
ArrayList g_hPrestigeSounds[32];
ArrayList g_hPrestigeModels[32];

bool g_bPrestigeDeclined[MPS];
float g_fClientXPMultiplier[MPS];
float g_fClientCreditMultiplier[MPS];

char g_sClientEquippedModel[MPS][PMP];
int g_iClientEquippedPrestige[MPS] = {-1, ...};

Handle g_hCookieDisableMessages;
Handle g_hCookieDisableMenuPopup;
bool g_bDisableMessages[MPS];
bool g_bDisableMenuPopup[MPS];

CategoryId g_category_prestige_parent = INVALID_CATEGORY;
CategoryId g_category_prestige_zombies = INVALID_CATEGORY;
CategoryId g_category_prestige_humans = INVALID_CATEGORY;
bool g_bShopLoaded = false;
bool g_bZRAvailable = false;
bool g_bZRiotAvailable = false;

int g_iMaxPrestige = 0;

public Plugin myinfo = 
{
	name = "SM:RPG Prestige System",
	author = "+SyntX",
	description = "Advanced prestige system for SM:RPG with sounds, models and shop integration",
	version = "1.1",
	url = ""
};

public void OnPluginStart()
{
	for(int i = 0; i <= MaxClients; i++)
	{
		g_fClientXPMultiplier[i] = 1.0;
		g_fClientCreditMultiplier[i] = 1.0;
		g_iClientEquippedPrestige[i] = -1;
	}
	
	RegConsoleCmd("sm_prestige", Command_Prestige, "Check your prestige status or prestige");
	RegConsoleCmd("sm_prestigestatus", Command_PrestigeStatus, "Check your prestige status");
	RegConsoleCmd("sm_prestigemodels", Command_PrestigeModels, "Equip prestige models");
	RegAdminCmd("sm_setprestige", Command_SetPrestige, ADMFLAG_ROOT, "Set a player's prestige level");
	
	g_cvPrestigeEnabled = CreateConVar("smrpg_prestige_enabled", "1", "Enable prestige system", FCVAR_NOTIFY);
	g_cvPrestigeDebug = CreateConVar("smrpg_prestige_debug", "0", "Enable debug messages", FCVAR_NOTIFY);
	g_cvPrestigeSounds = CreateConVar("smrpg_prestige_sounds", "1", "Enable prestige sounds", FCVAR_NOTIFY);
	g_cvPrestigeModels = CreateConVar("smrpg_prestige_models", "1", "Enable prestige models", FCVAR_NOTIFY);
	g_cvDiscordEnable = CreateConVar("smrpg_prestige_discord", "1", "Enable Discord logging", FCVAR_NOTIFY);
	g_cvDiscordWebhook = CreateConVar("smrpg_prestige_discord_webhook", "", "Discord webhook URL for prestige logging", FCVAR_PROTECTED);
	
	g_hCookieDisableMessages = RegClientCookie("prestige_disable_messages", "Disable prestige messages", CookieAccess_Private);
	g_hCookieDisableMenuPopup = RegClientCookie("prestige_disable_menu_popup", "Disable prestige menu popup", CookieAccess_Private);
	g_bZRAvailable = LibraryExists("zombiereloaded");
	g_bZRiotAvailable = LibraryExists("zombieriot");
	g_bShopLoaded = LibraryExists("shop");
	
	LoadPrestigeConfig();
	LoadDownloadsConfig();
	
	AutoExecConfig(true, "smrpg_prestige");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", OnClientDeath);
	HookEvent("round_end", OnRoundEnd);
	
	#if defined _zr_included
	HookEvent("player_team", Event_PlayerTeam);
	#endif
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shop"))
	{
		g_bShopLoaded = true;
		#if defined _shop_included
		Shop_Started();
		#endif
	}
	else if(StrEqual(name, "zombiereloaded"))
		g_bZRAvailable = true;
	else if(StrEqual(name, "zombieriot"))
		g_bZRiotAvailable = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shop"))
		g_bShopLoaded = false;
	else if(StrEqual(name, "zombiereloaded"))
		g_bZRAvailable = false;
	else if(StrEqual(name, "zombieriot"))
		g_bZRiotAvailable = false;
}

public void OnPluginEnd()
{
	if(g_kvPrestigeConfig != null)
	{
		delete g_kvPrestigeConfig;
	}
	
	for(int i = 0; i <= g_iMaxPrestige; i++)
	{
		delete g_hUpgradeRestrictions[i];
		delete g_hPrestigeSounds[i];
		delete g_hPrestigeModels[i];
	}
	
	#if defined _shop_included
	if(g_bShopLoaded)
	{
		Shop_UnregisterMe();
	}
	#endif
}

public void OnMapStart()
{
	LoadDownloadsConfig();
}

public void OnClientPutInServer(int client)
{
	g_bPrestigeDeclined[client] = false;
	g_fClientXPMultiplier[client] = 1.0;
	g_fClientCreditMultiplier[client] = 1.0;
	g_sClientEquippedModel[client][0] = '\0';
	g_iClientEquippedPrestige[client] = -1;
}

public void OnClientCookiesCached(int client)
{
	char sValue[8];
	
	GetClientCookie(client, g_hCookieDisableMessages, sValue, sizeof(sValue));
	g_bDisableMessages[client] = (sValue[0] != '\0' && StringToInt(sValue) == 1);
	
	GetClientCookie(client, g_hCookieDisableMenuPopup, sValue, sizeof(sValue));
	g_bDisableMenuPopup[client] = (sValue[0] != '\0' && StringToInt(sValue) == 1);
}

public void OnClientDisconnect(int client)
{
	g_bPrestigeDeclined[client] = false;
	g_sClientEquippedModel[client][0] = '\0';
	g_iClientEquippedPrestige[client] = -1;
}

public void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if(!g_cvPrestigeEnabled.BoolValue)
		return;
	
	int winner = event.GetInt("winner");
	
	if(winner < 2)
		return;
	
	#if defined _shop_included
	if(!g_bShopLoaded)
		return;
	#endif
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) == winner)
		{
			int baseCredits = 2;
			
			#if defined _shop_included
			if(g_bShopLoaded)
			{
				AwardShopCredits(client, baseCredits);
			}
			#endif
		}
	}
}

public void OnClientDeath(Event event, const char[] name, bool dontBroadcast)
{
	if(!g_cvPrestigeEnabled.BoolValue)
		return;
	
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	
	if(!attacker || attacker == victim || !IsClientInGame(attacker))
		return;
	int baseCredits = 1;
	
	#if defined _shop_included
	if(g_bShopLoaded)
	{
		AwardShopCredits(attacker, baseCredits);
	}
	#endif
}

#if defined _shop_included
public void Shop_Started()
{
	if(g_cvPrestigeDebug.BoolValue)
		LogMessage("[Prestige Debug] Shop_Started() called");
	
	g_bShopLoaded = true;
	g_category_prestige_parent = INVALID_CATEGORY;
	g_category_prestige_zombies = INVALID_CATEGORY;
	g_category_prestige_humans = INVALID_CATEGORY;
	CreateTimer(1.0, Timer_InitializeShop, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_InitializeShop(Handle timer)
{
	if(!g_bShopLoaded)
	{
		if(g_cvPrestigeDebug.BoolValue)
			LogMessage("[Prestige Debug] Shop no longer loaded, aborting initialization");
		return Plugin_Stop;
	}
	
	if(g_cvPrestigeDebug.BoolValue)
		LogMessage("[Prestige Debug] Initializing shop categories...");
	
	bool success = RegisterShopCategories();
	
	if(success)
	{
		if(g_cvPrestigeDebug.BoolValue)
		{
			LogMessage("[Prestige Debug] Categories registered successfully!");
			LogMessage("[Prestige Debug] Zombies/T subcategory ID: %d", g_category_prestige_zombies);
			LogMessage("[Prestige Debug] Humans/CT subcategory ID: %d", g_category_prestige_humans);
		}
		CreateTimer(0.5, Timer_DelayedPopulation, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		if(g_cvPrestigeDebug.BoolValue)
			LogMessage("[Prestige Debug] Failed to register categories, retrying in 2 seconds...");
		CreateTimer(2.0, Timer_InitializeShop, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	return Plugin_Stop;
}

bool RegisterShopCategories()
{
	#if defined _zr_included || defined _zombieriot_included
	g_category_prestige_zombies = Shop_RegisterCategory("prestige_zombies", "Prestige - Zombie Models", 
		"Unlock prestige models for zombies", INVALID_FUNCTION, INVALID_FUNCTION, OnShouldDisplayCategory);
	g_category_prestige_humans = Shop_RegisterCategory("prestige_humans", "Prestige - Human Models", 
		"Unlock prestige models for humans", INVALID_FUNCTION, INVALID_FUNCTION, OnShouldDisplayCategory);
	#else
	g_category_prestige_zombies = Shop_RegisterCategory("prestige_terrorists", "Prestige - Terrorist Models", 
		"Unlock prestige models for terrorists", INVALID_FUNCTION, INVALID_FUNCTION, OnShouldDisplayCategory);
	g_category_prestige_humans = Shop_RegisterCategory("prestige_counterterrorists", "Prestige - Counter-Terrorist Models", 
		"Unlock prestige models for CT", INVALID_FUNCTION, INVALID_FUNCTION, OnShouldDisplayCategory);
	#endif
	
	if(g_category_prestige_zombies == INVALID_CATEGORY || g_category_prestige_humans == INVALID_CATEGORY)
	{
		LogError("[Prestige] Failed to register categories!");
		return false;
	}
	
	return true;
}

public bool OnShouldDisplayCategory(int client, CategoryId category_id, char[] category, ShopMenu menu)
{
	int prestigeLevel = SMRPG_GetClientPrestigeLevel(client);
	return (prestigeLevel >= 0);
}

public Action Timer_DelayedPopulation(Handle timer)
{
	if(!g_bShopLoaded)
	{
		if(g_cvPrestigeDebug.BoolValue)
			LogMessage("[Prestige Debug] Shop no longer loaded, skipping model population");
		return Plugin_Stop;
	}
	
	PopulateShopModels();
	
	if(g_cvPrestigeDebug.BoolValue)
		LogMessage("[Prestige Debug] Shop models populated");
	
	return Plugin_Stop;
}

void PopulateShopModels()
{
	if(!g_cvPrestigeModels.BoolValue)
		return;
	
	if(g_category_prestige_zombies == INVALID_CATEGORY || g_category_prestige_humans == INVALID_CATEGORY)
	{
		LogError("[Prestige] Cannot populate shop models - categories are not valid!");
		return;
	}
	
	if(!Shop_IsValidCategory(g_category_prestige_zombies) || !Shop_IsValidCategory(g_category_prestige_humans))
	{
		LogError("[Prestige] Cannot populate shop models - categories are not registered in shop!");
		return;
	}
	
	for(int prestige = 1; prestige <= g_iMaxPrestige; prestige++)
	{
		for(int i = 0; i < g_hPrestigeModels[prestige].Length; i++)
		{
			PrestigeModel model;
			g_hPrestigeModels[prestige].GetArray(i, model);
			
			char itemName[128];
			Format(itemName, sizeof(itemName), "[P%d] %s", prestige, model.name);
			
			char itemUnique[256];
			Format(itemUnique, sizeof(itemUnique), "prestige_%d_%s_%d", prestige, model.name, i);
			
			if(model.team == 1)
			{
				AddShopModel(g_category_prestige_zombies, itemUnique, itemName, model.path, prestige, i);
			}
			else if(model.team == 0)
			{
				AddShopModel(g_category_prestige_humans, itemUnique, itemName, model.path, prestige, i);
			}
			else
			{
				AddShopModel(g_category_prestige_zombies, itemUnique, itemName, model.path, prestige, i);
				AddShopModel(g_category_prestige_humans, itemUnique, itemName, model.path, prestige, i);
			}
		}
	}
}

public ShopAction OnShopModelSelected(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, bool isOn, bool elapsed)
{
	if(!isOn && !elapsed)
	{
		if(!g_cvPrestigeModels.BoolValue)
		{
			CPrintToChat(client, "{green}[Shop]{default} Prestige models are currently disabled.");
			return Shop_UseOff;
		}
		
		int requiredPrestige = Shop_GetItemCustomInfo(item_id, "prestige");
		int clientPrestige = SMRPG_GetClientPrestigeLevel(client);
		
		if(clientPrestige < requiredPrestige)
		{
			CPrintToChat(client, "{green}[Shop]{default} This model requires {green}Prestige %d{default}. You are currently {green}Prestige %d{default}.", requiredPrestige, clientPrestige);
			return Shop_UseOff;
		}
		char modelPath[PMP];
		Shop_GetItemCustomInfoString(item_id, "model", modelPath, sizeof(modelPath));
		
		if(StrEqual(g_sClientEquippedModel[client], modelPath))
		{
			g_sClientEquippedModel[client][0] = '\0';
			g_iClientEquippedPrestige[client] = -1;
			CPrintToChat(client, "{green}[Shop]{default} Prestige model unequipped.");
			return Shop_UseOff;
		}
		
		g_sClientEquippedModel[client][0] = '\0';
		g_iClientEquippedPrestige[client] = -1;
		
		strcopy(g_sClientEquippedModel[client], sizeof(g_sClientEquippedModel[]), modelPath);
		g_iClientEquippedPrestige[client] = requiredPrestige;
		
		Shop_ToggleClientCategoryOff(client, category_id);
		
		if(IsPlayerAlive(client))
			ApplyClientModel(client);
		
		CPrintToChat(client, "{green}[Shop]{default} Prestige model equipped: {lightgreen}%s{default} (Prestige %d)", item, requiredPrestige);
		return Shop_UseOn;
	}
	else if(isOn)
	{
		g_sClientEquippedModel[client][0] = '\0';
		g_iClientEquippedPrestige[client] = -1;
		CPrintToChat(client, "{green}[Shop]{default} Prestige model unequipped.");
		return Shop_UseOff;
	}
	
	return Shop_UseOff;
}

void AddShopModel(CategoryId category, const char[] itemId, const char[] name, const char[] modelPath, int prestigeLevel, int modelIndex)
{
	char path[PMP];
	strcopy(path, sizeof(path), modelPath);
	
	if(category == INVALID_CATEGORY)
		return;
	
	if(!Shop_IsValidCategory(category))
		return;
	
	ItemId existingItem = Shop_GetItemId(category, itemId);
	if(existingItem != INVALID_ITEM)
		return;
	
	Shop_StartItem(category, itemId);
	Shop_SetInfo(name, "Exclusive Prestige Model", 0, 0, Item_Togglable, -1);
	
	Shop_SetCallbacks(
		INVALID_FUNCTION,
		OnShopModelSelected,
		INVALID_FUNCTION,
		INVALID_FUNCTION,
		INVALID_FUNCTION,
		INVALID_FUNCTION
	);
	
	Shop_SetCustomInfoString("model", path);
	Shop_SetCustomInfo("prestige", prestigeLevel);
	Shop_SetCustomInfo("model_index", modelIndex);
	Shop_EndItem();
}

void RemoveOldPrestigeSkins(int client)
{
	if(!g_bShopLoaded)
		return;
	
	int clientPrestige = SMRPG_GetClientPrestigeLevel(client);
	
	if(g_iClientEquippedPrestige[client] > clientPrestige)
	{
		g_sClientEquippedModel[client][0] = '\0';
		g_iClientEquippedPrestige[client] = -1;
		
		if(!g_bDisableMessages[client])
			CPrintToChat(client, "{green}[Prestige]{default} Your equipped model has been unequipped as it requires a higher prestige level.");
	}
}
#endif

void LoadPrestigeConfig()
{
	char configPath[PMP];
	BuildPath(Path_SM, configPath, sizeof(configPath), CONFIG_PATH);
	
	g_kvPrestigeConfig = new KeyValues("Prestige");
	
	if(!g_kvPrestigeConfig.ImportFromFile(configPath))
	{
		LogError("Could not load prestige configuration from %s", configPath);
		LogMessage("Please create a configuration file at %s", configPath);
		return;
	}
	
	g_iMaxPrestige = FindMaxPrestigeLevel();
	
	for(int i = 0; i <= g_iMaxPrestige; i++)
	{
		g_hUpgradeRestrictions[i] = new ArrayList(sizeof(UpgradeRestriction));
		g_hPrestigeSounds[i] = new ArrayList(sizeof(PrestigeSound));
		g_hPrestigeModels[i] = new ArrayList(sizeof(PrestigeModel));
		
		strcopy(g_PrestigeInfo[i].name, sizeof(g_PrestigeInfo[].name), "");
		g_PrestigeInfo[i].max_level = 1750;
		g_PrestigeInfo[i].xp_multiplier = 1.0;
		g_PrestigeInfo[i].credit_multiplier = 1.0;
	}
	
	ParsePrestigeConfig();
	ParseUpgradeRestrictions();
	ParsePrestigeSounds();
	ParsePrestigeModels();
	
	LogMessage("Loaded prestige configuration from %s, Max Prestige: %d", configPath, g_iMaxPrestige);
}

int FindMaxPrestigeLevel()
{
	int maxLevel = 0;
	
	KeyValues kv = new KeyValues("Prestige");
	
	char configPath[PMP];
	BuildPath(Path_SM, configPath, sizeof(configPath), CONFIG_PATH);
	
	if(!kv.ImportFromFile(configPath))
	{
		delete kv;
		return 0;
	}
	
	if(kv.GotoFirstSubKey(false))
	{
		do
		{
			char sectionName[32];
			kv.GetSectionName(sectionName, sizeof(sectionName));
			
			int prestigeLevel = StringToInt(sectionName);
			if(prestigeLevel > maxLevel)
			{
				maxLevel = prestigeLevel;
			}
		}
		while(kv.GotoNextKey(false));
	}
	
	delete kv;
	return maxLevel;
}

void ParsePrestigeConfig()
{
	for(int prestige = 0; prestige <= g_iMaxPrestige; prestige++)
	{
		char prestigeKey[4];
		IntToString(prestige, prestigeKey, sizeof(prestigeKey));
		
		g_kvPrestigeConfig.Rewind();
		if(g_kvPrestigeConfig.JumpToKey(prestigeKey))
		{
			g_kvPrestigeConfig.GetString("name", g_PrestigeInfo[prestige].name, sizeof(g_PrestigeInfo[].name), "Unknown");
			g_PrestigeInfo[prestige].max_level = g_kvPrestigeConfig.GetNum("max_level", 1750);
			g_PrestigeInfo[prestige].xp_multiplier = g_kvPrestigeConfig.GetFloat("xp_multiplier", 1.0);
			g_PrestigeInfo[prestige].credit_multiplier = g_kvPrestigeConfig.GetFloat("credit_multiplier", 1.0);
			
			if(g_cvPrestigeDebug.BoolValue)
			{
				LogMessage("[Prestige Debug] Loaded prestige %d: %s, max_level: %d, xp_mult: %.2f, credit_mult: %.2f", 
					prestige, g_PrestigeInfo[prestige].name, g_PrestigeInfo[prestige].max_level, 
					g_PrestigeInfo[prestige].xp_multiplier, g_PrestigeInfo[prestige].credit_multiplier);
			}
			
			g_kvPrestigeConfig.GoBack();
		}
	}
}

void ParseUpgradeRestrictions()
{
    for(int prestige = 0; prestige <= g_iMaxPrestige; prestige++)
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
                        
                        char upgradeList[512];
                        g_kvPrestigeConfig.GetString(NULL_STRING, upgradeList, sizeof(upgradeList));
                        
                        char upgrades[32][64];
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

void ParsePrestigeSounds()
{
	for(int prestige = 0; prestige <= g_iMaxPrestige; prestige++)
	{
		char prestigeKey[4];
		IntToString(prestige, prestigeKey, sizeof(prestigeKey));
		
		g_kvPrestigeConfig.Rewind();
		if(g_kvPrestigeConfig.JumpToKey(prestigeKey))
		{
			g_hPrestigeSounds[prestige].Clear();
			
			if(g_kvPrestigeConfig.JumpToKey("sounds"))
			{
				if(g_kvPrestigeConfig.GotoFirstSubKey())
				{
					do
					{
						PrestigeSound sound;
						g_kvPrestigeConfig.GetSectionName(sound.name, sizeof(sound.name));
						g_kvPrestigeConfig.GetString("path", sound.path, sizeof(sound.path));
						
						if(sound.path[0] != '\0')
						{
							g_hPrestigeSounds[prestige].PushArray(sound);
							
							if(g_cvPrestigeDebug.BoolValue)
								LogMessage("[Prestige Debug] Added sound '%s' for prestige %d: %s", sound.name, prestige, sound.path);
						}
					}
					while(g_kvPrestigeConfig.GotoNextKey());
					
					g_kvPrestigeConfig.GoBack();
				}
				
				g_kvPrestigeConfig.GoBack();
			}
			
			g_kvPrestigeConfig.GoBack();
		}
	}
}

void ParsePrestigeModels()
{
	for(int prestige = 0; prestige <= g_iMaxPrestige; prestige++)
	{
		char prestigeKey[4];
		IntToString(prestige, prestigeKey, sizeof(prestigeKey));
		
		g_kvPrestigeConfig.Rewind();
		if(g_kvPrestigeConfig.JumpToKey(prestigeKey))
		{
			g_hPrestigeModels[prestige].Clear();
			
			if(g_kvPrestigeConfig.JumpToKey("models"))
			{
				if(g_kvPrestigeConfig.GotoFirstSubKey())
				{
					do
					{
						PrestigeModel model;
						g_kvPrestigeConfig.GetSectionName(model.name, sizeof(model.name));
						g_kvPrestigeConfig.GetString("path", model.path, sizeof(model.path));
						
						char teamStr[16];
						g_kvPrestigeConfig.GetString("team", teamStr, sizeof(teamStr), "2");
						
						if(StrEqual(teamStr, "zombie", false) || StrEqual(teamStr, "terrorist", false) || StrEqual(teamStr, "t", false))
							model.team = 1;
						else if(StrEqual(teamStr, "human", false) || StrEqual(teamStr, "ct", false) || StrEqual(teamStr, "counterterrorist", false))
							model.team = 0;
						else
							model.team = StringToInt(teamStr);
						
						if(model.path[0] != '\0')
						{
							g_hPrestigeModels[prestige].PushArray(model);
							
							if(g_cvPrestigeDebug.BoolValue)
								LogMessage("[Prestige Debug] Added model '%s' for prestige %d: %s (team: %d)", model.name, prestige, model.path, model.team);
						}
					}
					while(g_kvPrestigeConfig.GotoNextKey());
					
					g_kvPrestigeConfig.GoBack();
				}
				
				g_kvPrestigeConfig.GoBack();
			}
			
			g_kvPrestigeConfig.GoBack();
		}
	}
}

void LoadDownloadsConfig()
{
	char configPath[PMP];
	BuildPath(Path_SM, configPath, sizeof(configPath), DOWNLOADS_PATH);
	
	File file = OpenFile(configPath, "r");
	if(file == null)
	{
		LogError("Could not load downloads file: %s", configPath);
		return;
	}
	
	char buffer[PMP];
	while(!file.EndOfFile() && file.ReadLine(buffer, sizeof(buffer)))
	{
		TrimString(buffer);
		
		if(buffer[0] == '\0' || buffer[0] == '/' && buffer[1] == '/')
			continue;
		
		if(StrContains(buffer, ".mp3", false) != -1 || StrContains(buffer, ".wav", false) != -1)
		{
			PrecacheSound(buffer);
			
			char downloadPath[PMP];
			Format(downloadPath, sizeof(downloadPath), "sound/%s", buffer);
			AddFileToDownloadsTable(downloadPath);
			
			if(g_cvPrestigeDebug.BoolValue)
				LogMessage("[Prestige Debug] Precached sound: %s", buffer);
		}
		else if(StrContains(buffer, ".mdl", false) != -1)
		{
			PrecacheModel(buffer, true);
			AddFileToDownloadsTable(buffer);
			
			char path[PMP];
			strcopy(path, sizeof(path), buffer);
			
			ReplaceString(path, sizeof(path), ".mdl", ".vvd");
			if(FileExists(path))
				AddFileToDownloadsTable(path);
			
			ReplaceString(path, sizeof(path), ".vvd", ".dx90.vtx");
			if(FileExists(path))
				AddFileToDownloadsTable(path);
			
			ReplaceString(path, sizeof(path), ".dx90.vtx", ".phy");
			if(FileExists(path))
				AddFileToDownloadsTable(path);
			
			if(g_cvPrestigeDebug.BoolValue)
				LogMessage("[Prestige Debug] Precached model: %s", buffer);
		}
	}
	
	delete file;
}

public void OnClientPostAdminCheck(int client)
{
	if(IsFakeClient(client))
		return;
		
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
		int maxLevel = g_kvPrestigeConfig.GetNum("max_level", 1750);
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
	
	if(g_iClientEquippedPrestige[client] > prestigeLevel)
	{
		g_sClientEquippedModel[client][0] = '\0';
		g_iClientEquippedPrestige[client] = -1;
		
		if(!g_bDisableMessages[client])
			CPrintToChat(client, "{green}[Prestige]{default} Your equipped model has been unequipped as it requires a higher prestige level.");
	}
}

public void OnClientLevel(int client, int oldlevel, int newlevel)
{
	if(!g_cvPrestigeEnabled.BoolValue)
		return;
		
	int requiredLevel = g_PrestigeInfo[SMRPG_GetClientPrestigeLevel(client)].max_level;
	int prestigeLevel = SMRPG_GetClientPrestigeLevel(client);
	
	if(g_cvPrestigeSounds.BoolValue && newlevel > oldlevel)
	{
		PlayPrestigeSound(client, prestigeLevel);
	}
	if(newlevel > oldlevel)
	{
		int baseCredits = 1;
		int levelsGained = newlevel - oldlevel;
		
		#if defined _shop_included
		if(g_bShopLoaded)
		{
			AwardShopCredits(client, baseCredits * levelsGained);
		}
		#endif
	}
	
	if(newlevel >= requiredLevel && oldlevel < requiredLevel && prestigeLevel < g_iMaxPrestige && !g_bPrestigeDeclined[client])
	{
		if(!g_bDisableMenuPopup[client])
		{
			ShowPrestigeOffer(client);
		}
		else if(!g_bDisableMessages[client])
		{
			CPrintToChat(client, "{green}[Prestige]{default} You are eligible to prestige! Type {lightgreen}!prestige{default} to view details.");
		}
		
		if(!g_bDisableMessages[client] && g_cvPrestigeDebug.BoolValue)
		{
			char clientName[MAX_NAME_LENGTH];
			GetClientName(client, clientName, sizeof(clientName));
			CPrintToChatAll("{green}[Prestige]{default} {lightgreen}%s{default} has reached level %d and can now prestige to {lightgreen}%s{default}!", 
				clientName, requiredLevel, g_PrestigeInfo[prestigeLevel + 1].name);
		}
	}
}

void PlayPrestigeSound(int client, int prestigeLevel)
{
	if(g_hPrestigeSounds[prestigeLevel].Length == 0)
		return;
	
	int randomIndex = GetRandomInt(0, g_hPrestigeSounds[prestigeLevel].Length - 1);
	
	PrestigeSound sound;
	g_hPrestigeSounds[prestigeLevel].GetArray(randomIndex, sound);
	
	if(sound.path[0] != '\0')
	{
		EmitSoundToAll(sound.path);
		
		if(g_cvPrestigeDebug.BoolValue)
			LogMessage("[Prestige Debug] Played prestige sound to all players: %s (triggered by %N)", sound.path, client);
	}
}

void ShowPrestigeOffer(int client)
{
	Menu menu = new Menu(MenuHandler_PrestigeOffer);
	
	char title[512];
	int currentPrestige = SMRPG_GetClientPrestigeLevel(client);
	int nextPrestige = currentPrestige + 1;
	int requiredLevel = g_PrestigeInfo[currentPrestige].max_level;
	
	char newUpgrade[64];
	GetNewUpgradeForPrestige(nextPrestige, newUpgrade, sizeof(newUpgrade));
	
	char modelName[64];
	if(g_hPrestigeModels[nextPrestige].Length > 0)
	{
		PrestigeModel model;
		g_hPrestigeModels[nextPrestige].GetArray(0, model);
		strcopy(modelName, sizeof(modelName), model.name);
	}
	else
	{
		modelName[0] = '\0';
	}
	
	Format(title, sizeof(title), "Prestige Opportunity!\n \nYou've reached level %d!\n \nCurrent: %s\nNext: %s\n \nAre you ready to prestige?:", 
		requiredLevel, 
		g_PrestigeInfo[currentPrestige].name, 
		g_PrestigeInfo[nextPrestige].name);
	
	menu.SetTitle(title);
	
	char buffer[256];
	float xpMultiplier = g_PrestigeInfo[nextPrestige].xp_multiplier;
	float creditMult = g_PrestigeInfo[nextPrestige].credit_multiplier;
	
	Format(buffer, sizeof(buffer), "• XP Multiplier: +%.0f%%", (xpMultiplier - 1.0) * 100);
	menu.AddItem("", buffer, ITEMDRAW_DISABLED);
	
	Format(buffer, sizeof(buffer), "• Shop Credit Multiplier: +%.0f%%", (creditMult - 1.0) * 100);
	menu.AddItem("", buffer, ITEMDRAW_DISABLED);
	
	if(strlen(newUpgrade) > 0)
	{
		Format(buffer, sizeof(buffer), "• New RPG Upgrade: %s", newUpgrade);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
	}
	
	if(g_cvPrestigeModels.BoolValue && g_hPrestigeModels[nextPrestige].Length > 0)
	{
		char accessInfo[32];
		#if defined _shop_included
		if(g_bShopLoaded)
		{
			Format(accessInfo, sizeof(accessInfo), "(Available in !shop)");
		}
		else
		#endif
		{
			Format(accessInfo, sizeof(accessInfo), "(Available in !prestigemodels)");
		}
		
		if(strlen(modelName) > 0)
		{
			Format(buffer, sizeof(buffer), "• New Model: %s %s", modelName, accessInfo);
			menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		}
		else
		{
			Format(buffer, sizeof(buffer), "• New Models: %d %s", g_hPrestigeModels[nextPrestige].Length, accessInfo);
			menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		}
	}
	
	Format(buffer, sizeof(buffer), "\nNote: Prestige will reset all RPG Upgrades.");
	menu.AddItem("", buffer, ITEMDRAW_DISABLED);
	menu.AddItem("", "", ITEMDRAW_SPACER);
	
	menu.AddItem("yes", "Yes, prestige now!");
	menu.AddItem("no", "Not right now");
	menu.AddItem("info", "More information");
	
	menu.ExitButton = false;
	menu.Display(client, 30);
}

void GetNewUpgradeForPrestige(int prestige, char[] buffer, int maxlen)
{
	buffer[0] = '\0';
	
	char prestigeKey[4];
	IntToString(prestige, prestigeKey, sizeof(prestigeKey));
	
	g_kvPrestigeConfig.Rewind();
	if(g_kvPrestigeConfig.JumpToKey(prestigeKey))
	{
		if(g_kvPrestigeConfig.JumpToKey("upgrades"))
		{
			if(g_kvPrestigeConfig.GotoFirstSubKey(false))
			{
				char levelKey[32];
				g_kvPrestigeConfig.GetSectionName(levelKey, sizeof(levelKey));
				
				char upgradeList[512];
				g_kvPrestigeConfig.GetString(NULL_STRING, upgradeList, sizeof(upgradeList));
				
				char upgrades[32][64];
				int upgradeCount = ExplodeString(upgradeList, ",", upgrades, sizeof(upgrades), sizeof(upgrades[]));
				
				if(prestige > 0)
				{
					ArrayList prevUpgrades = new ArrayList(64);
					char prevPrestigeKey[4];
					IntToString(prestige-1, prevPrestigeKey, sizeof(prevPrestigeKey));
					
					g_kvPrestigeConfig.Rewind();
					if(g_kvPrestigeConfig.JumpToKey(prevPrestigeKey) && g_kvPrestigeConfig.JumpToKey("upgrades"))
					{
						if(g_kvPrestigeConfig.GotoFirstSubKey(false))
						{
							char prevUpgradeList[512];
							g_kvPrestigeConfig.GetString(NULL_STRING, prevUpgradeList, sizeof(prevUpgradeList));
							
							char prevUpgradeArray[32][64];
							int prevCount = ExplodeString(prevUpgradeList, ",", prevUpgradeArray, sizeof(prevUpgradeArray), sizeof(prevUpgradeArray[]));
							
							for(int i = 0; i < prevCount; i++)
							{
								TrimString(prevUpgradeArray[i]);
								prevUpgrades.PushString(prevUpgradeArray[i]);
							}
							
							g_kvPrestigeConfig.GoBack();
						}
						g_kvPrestigeConfig.GoBack();
					}
					
					for(int i = 0; i < upgradeCount; i++)
					{
						TrimString(upgrades[i]);
						if(strlen(upgrades[i]) > 0)
						{
							bool found = false;
							for(int j = 0; j < prevUpgrades.Length; j++)
							{
								char prevUpgrade[64];
								prevUpgrades.GetString(j, prevUpgrade, sizeof(prevUpgrade));
								if(StrEqual(upgrades[i], prevUpgrade, false))
								{
									found = true;
									break;
								}
							}
							
							if(!found)
							{
								strcopy(buffer, maxlen, upgrades[i]);
								break;
							}
						}
					}
					
					delete prevUpgrades;
				}
				else if(upgradeCount > 0)
				{
					strcopy(buffer, maxlen, upgrades[0]);
				}
			}
		}
	}
}

public int MenuHandler_PrestigeOffer(Menu menu, MenuAction action, int client, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		
		if(StrEqual(info, "yes"))
		{
			ShowPrestigeConfirmation(client);
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
	
	return 0;
}

void ShowPrestigeConfirmation(int client)
{
    Menu menu = new Menu(MenuHandler_PrestigeConfirmation);
    
    int currentPrestige = SMRPG_GetClientPrestigeLevel(client);
    int nextPrestige = currentPrestige + 1;
    
    char title[512];
    Format(title, sizeof(title), "Confirm Prestige\n \nPrestige will:\n• Reset all RPG Upgrades\n• Send you back to RPG Level 1\n• Progress Prestige\n \nYou Will gain:");
    menu.SetTitle(title);
    
    char buffer[256];
    
    float xpMult = g_PrestigeInfo[nextPrestige].xp_multiplier;
    float creditMult = g_PrestigeInfo[nextPrestige].credit_multiplier;
    
    float xpBonus = (xpMult - 1.0) * 100;
    Format(buffer, sizeof(buffer), "• XP Multiplier: +%.0f%%", xpBonus);
    menu.AddItem("", buffer, ITEMDRAW_DISABLED);
    
    Format(buffer, sizeof(buffer), "• Shop Credit Multiplier: +%.0f%%", (creditMult - 1.0) * 100);
    menu.AddItem("", buffer, ITEMDRAW_DISABLED);
    
    char newUpgrade[64];
    GetNewUpgradeForPrestige(nextPrestige, newUpgrade, sizeof(newUpgrade));
    if(strlen(newUpgrade) > 0)
    {
        Format(buffer, sizeof(buffer), "• New Upgrade: %s", newUpgrade);
        menu.AddItem("", buffer, ITEMDRAW_DISABLED);
    }
    
    if(g_hPrestigeModels[nextPrestige].Length > 0)
    {
        Format(buffer, sizeof(buffer), "• New Models: %d", g_hPrestigeModels[nextPrestige].Length);
        menu.AddItem("", buffer, ITEMDRAW_DISABLED);
        
        int modelsToShow = g_hPrestigeModels[nextPrestige].Length;
        if(modelsToShow > 3) modelsToShow = 3;
        
        for(int i = 0; i < modelsToShow; i++)
        {
            PrestigeModel model;
            g_hPrestigeModels[nextPrestige].GetArray(i, model);
            
            char teamName[16];
            if(model.team == 0) Format(teamName, sizeof(teamName), "CT");
            else if(model.team == 1) Format(teamName, sizeof(teamName), "T");
            else Format(teamName, sizeof(teamName), "Both");
            
            char modelDisplay[48];
            if(strlen(model.name) > 15)
            {
                strcopy(modelDisplay, sizeof(modelDisplay), model.name);
                modelDisplay[15] = '\0';
                Format(modelDisplay, sizeof(modelDisplay), "%s...", modelDisplay);
            }
            else
            {
                strcopy(modelDisplay, sizeof(modelDisplay), model.name);
            }
            
            Format(buffer, sizeof(buffer), "  - %s (%s)", modelDisplay, teamName);
            menu.AddItem("", buffer, ITEMDRAW_DISABLED);
        }
        
        if(g_hPrestigeModels[nextPrestige].Length > 3)
        {
            Format(buffer, sizeof(buffer), "  - ... and %d more", g_hPrestigeModels[nextPrestige].Length - 3);
            menu.AddItem("", buffer, ITEMDRAW_DISABLED);
        }
    }
    
    menu.AddItem("", "", ITEMDRAW_SPACER);
    
    menu.AddItem("yes", "Yes, I'm ready to prestige!");
    menu.AddItem("no", "No, take me back");
    
    menu.ExitButton = false;
    menu.Display(client, 30);
}

public int MenuHandler_PrestigeConfirmation(Menu menu, MenuAction action, int client, int param2)
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
			ShowPrestigeOffer(client);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

void HandlePrestigeDecline(int client)
{
    g_bPrestigeDeclined[client] = true;
    
    int currentPrestige = SMRPG_GetClientPrestigeLevel(client);
    int nextPrestige = currentPrestige + 1;
    
    if(!g_bDisableMessages[client])
    {
        CPrintToChat(client, "{green}[Prestige]{default} You have chosen to stay at {green}%s{default}.", g_PrestigeInfo[currentPrestige].name);
        CPrintToChat(client, "{green}[Prestige]{default} You can continue leveling up, but you will not receive benefits from %s.", g_PrestigeInfo[nextPrestige].name);
        CPrintToChat(client, "{green}[Prestige]{default} Type {lightgreen}!prestige{default} at any time to prestige.");
        
        float xpMult = g_PrestigeInfo[nextPrestige].xp_multiplier;
        float creditMult = g_PrestigeInfo[nextPrestige].credit_multiplier;
        
        float xpBonus = (xpMult - 1.0) * 100;
        float creditBonus = (creditMult - 1.0) * 100;
        
        CPrintToChat(client, "{green}[Prestige]{default} You're missing: {lightgreen}+%.0f%% XP{default} and {lightgreen}+%.0f%% credits{default}", 
            xpBonus, creditBonus);
    }
}

void ShowPrestigeInfo(int client)
{
    Menu menu = new Menu(MenuHandler_PrestigeInfo);
    
    char title[256];
    int nextPrestige = SMRPG_GetClientPrestigeLevel(client) + 1;
    
    Format(title, sizeof(title), "Prestige Information\n \n%s Benefits:\n", g_PrestigeInfo[nextPrestige].name);
    menu.SetTitle(title);
    
    char buffer[256];
    
    float xpMultiplier = g_PrestigeInfo[nextPrestige].xp_multiplier;
    float xpBonus = (xpMultiplier - 1.0) * 100;
    Format(buffer, sizeof(buffer), "XP Multiplier: +%.0f%%", xpBonus);
    menu.AddItem("", buffer, ITEMDRAW_DISABLED);
    
    float creditMultiplier = g_PrestigeInfo[nextPrestige].credit_multiplier;
    Format(buffer, sizeof(buffer), "Shop Credit Multiplier: +%.0f%%", (creditMultiplier - 1.0) * 100);
    menu.AddItem("", buffer, ITEMDRAW_DISABLED);
    
    char newUpgrade[64];
    GetNewUpgradeForPrestige(nextPrestige, newUpgrade, sizeof(newUpgrade));
    if(strlen(newUpgrade) > 0)
    {
        Format(buffer, sizeof(buffer), "New Upgrade: %s", newUpgrade);
        menu.AddItem("", buffer, ITEMDRAW_DISABLED);
    }
    
    if(g_hPrestigeModels[nextPrestige].Length > 0)
    {
        Format(buffer, sizeof(buffer), "New Models: %d", g_hPrestigeModels[nextPrestige].Length);
        menu.AddItem("", buffer, ITEMDRAW_DISABLED);
        
        #if defined _shop_included
        if(g_bShopLoaded)
        {
            Format(buffer, sizeof(buffer), "  (Access via !shop menu)");
        }
        else
        #endif
        {
            Format(buffer, sizeof(buffer), "  (Access via !prestigemodels)");
        }
        menu.AddItem("", buffer, ITEMDRAW_DISABLED);
        for(int i = 0; i < g_hPrestigeModels[nextPrestige].Length; i++)
        {
            PrestigeModel model;
            g_hPrestigeModels[nextPrestige].GetArray(i, model);
            
            char teamName[16];
            if(model.team == 0) Format(teamName, sizeof(teamName), "CT");
            else if(model.team == 1) Format(teamName, sizeof(teamName), "T");
            else Format(teamName, sizeof(teamName), "Both");
            char modelDisplay[64];
            if(strlen(model.name) > 20)
            {
                strcopy(modelDisplay, sizeof(modelDisplay), model.name);
                modelDisplay[20] = '\0';
                Format(modelDisplay, sizeof(modelDisplay), "%s...", modelDisplay);
            }
            else
            {
                strcopy(modelDisplay, sizeof(modelDisplay), model.name);
            }
            
            Format(buffer, sizeof(buffer), "  • %s (%s)", modelDisplay, teamName);
            menu.AddItem("", buffer, ITEMDRAW_DISABLED);
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
			ShowPrestigeConfirmation(client);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

void PerformPrestige(int client)
{
	int currentPrestige = SMRPG_GetClientPrestigeLevel(client);
	int newPrestige = currentPrestige + 1;
	
	if(newPrestige > g_iMaxPrestige)
	{
		CPrintToChat(client, "{green}[Prestige]{default} You've already reached the maximum prestige level!");
		return;
	}
	
	int playerLevelBefore = SMRPG_GetClientLevel(client);
	int playerXPBefore = SMRPG_GetClientExperience(client);
	
	if(SMRPG_ResetClientToPrestige(client, newPrestige))
	{
		g_bPrestigeDeclined[client] = false;
		
		if(g_iClientEquippedPrestige[client] > newPrestige)
		{
			g_sClientEquippedModel[client][0] = '\0';
			g_iClientEquippedPrestige[client] = -1;
			
			if(!g_bDisableMessages[client])
				CPrintToChat(client, "{green}[Prestige]{default} Your equipped model has been unequipped as it requires a higher prestige level.");
		}
		
		ApplyPrestigeConfig(client);
		SendPrestigeToDiscord(client, currentPrestige, newPrestige, playerLevelBefore, playerXPBefore);
		
		if(g_cvPrestigeSounds.BoolValue && g_hPrestigeSounds[newPrestige].Length > 0)
		{
			int randomIndex = GetRandomInt(0, g_hPrestigeSounds[newPrestige].Length - 1);
			PrestigeSound sound;
			g_hPrestigeSounds[newPrestige].GetArray(randomIndex, sound);
			
			if(sound.path[0] != '\0')
			{
				EmitSoundToAll(sound.path);
				
				if(g_cvPrestigeDebug.BoolValue)
					LogMessage("[Prestige Debug] Played prestige up sound to %N: %s", client, sound.path);
			}
		}
		
		char clientName[MAX_NAME_LENGTH];
		GetClientName(client, clientName, sizeof(clientName));
	
		CPrintToChatAll("{green}[Prestige]{default} {lightgreen}%s{default} has achieved {lightgreen}%s{default}!", 
			clientName, g_PrestigeInfo[newPrestige].name);
		char centerMessage[128];
		Format(centerMessage, sizeof(centerMessage), "%s\nhas achieved\n%s!", clientName, g_PrestigeInfo[newPrestige].name);
		
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsFakeClient(i))
			{
				PrintCenterText(i, centerMessage);
				DataPack pack = new DataPack();
				pack.WriteCell(GetClientUserId(i));
				pack.WriteString(centerMessage);
				CreateTimer(1.0, Timer_CenterText, pack, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
			}
		}
		
		if(!g_bDisableMessages[client])
		{
			CPrintToChat(client, "{green}[Prestige]{default} Congratulations! You are now {green}%s{default}!", g_PrestigeInfo[newPrestige].name);
			CPrintToChat(client, "{green}[Prestige]{default} Your stats have been reset. New journey begins!");

			float xpMult = g_PrestigeInfo[newPrestige].xp_multiplier;
			float creditMult = g_PrestigeInfo[newPrestige].credit_multiplier;
			
			CPrintToChat(client, "{green}[Prestige]{default} You gained: {lightgreen}+%.0f%% XP{default} and {lightgreen}+%.0f%% Shop Credits{default}", 
				(xpMult - 1.0) * 100, (creditMult - 1.0) * 100);
			
			#if defined _shop_included
			if(g_bShopLoaded && g_cvPrestigeModels.BoolValue)
			{
				CPrintToChat(client, "{green}[Prestige]{default} You've unlocked {green}new models{default} from Prestige %d!", newPrestige);
				CPrintToChat(client, "{green}[Prestige]{default} You keep all models from previous prestiges!");
				CPrintToChat(client, "{green}[Prestige]{default} You can equip them in the {lightgreen}!shop{default} menu.");
			}
			#endif
		}
		
		UpdateUpgradeVisibility(client);
	}
	else
	{
		CPrintToChat(client, "{green}[Prestige]{default} Prestige failed. Please try again.");
	}
}

public Action Timer_CenterText(Handle timer, DataPack pack)
{
	static int count[MAXPLAYERS+1] = {0, ...};
	
	pack.Reset();
	int userid = pack.ReadCell();
	char message[128];
	pack.ReadString(message, sizeof(message));
	
	int client = GetClientOfUserId(userid);
	
	if(client > 0 && IsClientInGame(client) && !IsFakeClient(client))
	{
		count[client]++;
		
		if(count[client] <= 5)
		{
			PrintCenterText(client, message);
			return Plugin_Continue;
		}
		else
		{
			count[client] = 0;
			PrintCenterText(client, "");
		}
	}
	else
	{
		count[client] = 0;
	}
	
	delete pack;
	return Plugin_Stop;
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
	
	ShowPrestigeMainMenu(client);
	
	return Plugin_Handled;
}

void ShowPrestigeMainMenu(int client)
{
	Menu menu = new Menu(MenuHandler_PrestigeMain);
	
	int prestigeLevel = SMRPG_GetClientPrestigeLevel(client);
	int currentLevel = SMRPG_GetClientLevel(client);
	int maxLevel = g_PrestigeInfo[prestigeLevel].max_level;
	
	char title[256];
	Format(title, sizeof(title), "Prestige Menu\n \n%s (%d/%d)\nLevel: %d/%d\n ", 
		g_PrestigeInfo[prestigeLevel].name, prestigeLevel, g_iMaxPrestige, currentLevel, maxLevel);
	menu.SetTitle(title);
	
	menu.AddItem("details", "View Details");
	
	if(currentLevel >= maxLevel && prestigeLevel < g_iMaxPrestige)
	{
		menu.AddItem("prestige", "Prestige Now!");
	}
	
	menu.AddItem("nextlevel", "See Next Level");
	
	if(g_cvPrestigeModels.BoolValue)
	{
		#if defined _shop_included
		if(!g_bShopLoaded)
		{
			menu.AddItem("models", "Equip Models");
		}
		#else
		menu.AddItem("models", "Equip Models");
		#endif
	}
	
	menu.AddItem("settings", "Settings");
	
	menu.ExitButton = true;
	menu.ExitBackButton = false;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_PrestigeMain(Menu menu, MenuAction action, int client, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		
		if(StrEqual(info, "details"))
		{
			ShowPrestigeStatus(client);
		}
		else if(StrEqual(info, "prestige"))
		{
			ShowPrestigeOffer(client);
		}
		else if(StrEqual(info, "nextlevel"))
		{
			ShowNextLevelInfo(client);
		}
		else if(StrEqual(info, "models"))
		{
			Command_PrestigeModels(client, 0);
		}
		else if(StrEqual(info, "settings"))
		{
			ShowPrestigeSettings(client);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

void ShowNextLevelInfo(int client)
{
    int currentPrestige = SMRPG_GetClientPrestigeLevel(client);
    int nextPrestige = currentPrestige + 1;
    
    if(nextPrestige > g_iMaxPrestige)
    {
        CPrintToChat(client, "{green}[Prestige]{default} You are at maximum prestige!");
        ShowPrestigeMainMenu(client);
        return;
    }
    
    Menu menu = new Menu(MenuHandler_NextLevel);
    
    char title[256];
    Format(title, sizeof(title), "Next Prestige: %s (%d)\n ", g_PrestigeInfo[nextPrestige].name, nextPrestige);
    menu.SetTitle(title);
    
    char buffer[256];
    
    char newUpgrade[64];
    GetNewUpgradeForPrestige(nextPrestige, newUpgrade, sizeof(newUpgrade));
    float xpMultiplier = g_PrestigeInfo[nextPrestige].xp_multiplier;
    float xpBonus = (xpMultiplier - 1.0) * 100;
    Format(buffer, sizeof(buffer), "XP Multiplier: +%.0f%%", xpBonus);
    menu.AddItem("", buffer, ITEMDRAW_DISABLED);
    
    float creditMultiplier = g_PrestigeInfo[nextPrestige].credit_multiplier;
    Format(buffer, sizeof(buffer), "Shop Credit Multiplier: +%.0f%%", (creditMultiplier - 1.0) * 100);
    menu.AddItem("", buffer, ITEMDRAW_DISABLED);
    
    if(strlen(newUpgrade) > 0)
    {
        Format(buffer, sizeof(buffer), "New Upgrade: %s", newUpgrade);
        menu.AddItem("", buffer, ITEMDRAW_DISABLED);
    }
    if(g_hPrestigeModels[nextPrestige].Length > 0)
    {
        Format(buffer, sizeof(buffer), "New Models: %d", g_hPrestigeModels[nextPrestige].Length);
        menu.AddItem("", buffer, ITEMDRAW_DISABLED);
        for(int i = 0; i < g_hPrestigeModels[nextPrestige].Length; i++)
        {
            PrestigeModel model;
            g_hPrestigeModels[nextPrestige].GetArray(i, model);
            
            char teamName[16];
            if(model.team == 0) Format(teamName, sizeof(teamName), "CT");
            else if(model.team == 1) Format(teamName, sizeof(teamName), "T");
            else Format(teamName, sizeof(teamName), "Both");
            char modelDisplay[64];
            if(strlen(model.name) > 20)
            {
                strcopy(modelDisplay, sizeof(modelDisplay), model.name);
                modelDisplay[20] = '\0';
                Format(modelDisplay, sizeof(modelDisplay), "%s...", modelDisplay);
            }
            else
            {
                strcopy(modelDisplay, sizeof(modelDisplay), model.name);
            }
            
            Format(buffer, sizeof(buffer), "  • %s (%s)", modelDisplay, teamName);
            menu.AddItem("", buffer, ITEMDRAW_DISABLED);
        }
    }
    
    menu.AddItem("", "", ITEMDRAW_SPACER);
    menu.AddItem("back", "Back to Main Menu");
    
    menu.ExitButton = true;
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_NextLevel(Menu menu, MenuAction action, int client, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		
		if(StrEqual(info, "back"))
		{
			ShowPrestigeMainMenu(client);
		}
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowPrestigeMainMenu(client);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

void ShowPrestigeSettings(int client)
{
	Menu menu = new Menu(MenuHandler_PrestigeSettings);
	menu.SetTitle("Prestige Settings\n ");
	
	char buffer[128];
	
	Format(buffer, sizeof(buffer), "Disable Messages: %s", g_bDisableMessages[client] ? "Yes" : "No");
	menu.AddItem("messages", buffer);
	
	Format(buffer, sizeof(buffer), "Disable Menu Popup: %s", g_bDisableMenuPopup[client] ? "Yes" : "No");
	menu.AddItem("popup", buffer);
	
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_PrestigeSettings(Menu menu, MenuAction action, int client, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		
		if(StrEqual(info, "messages"))
		{
			g_bDisableMessages[client] = !g_bDisableMessages[client];
			
			char sValue[2];
			IntToString(g_bDisableMessages[client] ? 1 : 0, sValue, sizeof(sValue));
			SetClientCookie(client, g_hCookieDisableMessages, sValue);
			
			CPrintToChat(client, "{green}[Prestige]{default} Messages %s.", g_bDisableMessages[client] ? "disabled" : "enabled");
			ShowPrestigeSettings(client);
		}
		else if(StrEqual(info, "popup"))
		{
			g_bDisableMenuPopup[client] = !g_bDisableMenuPopup[client];
			
			char sValue[2];
			IntToString(g_bDisableMenuPopup[client] ? 1 : 0, sValue, sizeof(sValue));
			SetClientCookie(client, g_hCookieDisableMenuPopup, sValue);
			
			CPrintToChat(client, "{green}[Prestige]{default} Menu popup %s.", g_bDisableMenuPopup[client] ? "disabled" : "enabled");
			ShowPrestigeSettings(client);
		}
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowPrestigeMainMenu(client);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
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
	int maxLevel = g_PrestigeInfo[prestigeLevel].max_level;
	
	Panel panel = new Panel();
	
	char buffer[256];
	Format(buffer, sizeof(buffer), "Prestige Status - %N", client);
	panel.SetTitle(buffer);
	
	panel.DrawText(" ");
	
	Format(buffer, sizeof(buffer), "Current Level: %d", currentLevel);
	panel.DrawText(buffer);
	
	Format(buffer, sizeof(buffer), "Prestige: %s (%d/%d)", g_PrestigeInfo[prestigeLevel].name, prestigeLevel, g_iMaxPrestige);
	panel.DrawText(buffer);
	
	Format(buffer, sizeof(buffer), "Required Level: %d", maxLevel);
	panel.DrawText(buffer);
	
	float xpMult = g_PrestigeInfo[prestigeLevel].xp_multiplier;
	float creditMult = g_PrestigeInfo[prestigeLevel].credit_multiplier;
	
	if(prestigeLevel == 0)
	{
		Format(buffer, sizeof(buffer), "XP Multiplier: +0%%");
		panel.DrawText(buffer);
		
		Format(buffer, sizeof(buffer), "Shop Credit Multiplier: +0%%");
		panel.DrawText(buffer);
	}
	else
	{
		Format(buffer, sizeof(buffer), "XP Multiplier: +%.0f%%", (xpMult - 1.0) * 100);
		panel.DrawText(buffer);
		
		Format(buffer, sizeof(buffer), "Shop Credit Multiplier: +%.0f%%", (creditMult - 1.0) * 100);
		panel.DrawText(buffer);
	}
	
	panel.DrawText(" ");
	
	if(prestigeLevel < g_iMaxPrestige)
	{
		int progress = currentLevel * 100 / maxLevel;
		Format(buffer, sizeof(buffer), "Progress to next prestige: %d%% (%d/%d)", progress, currentLevel, maxLevel);
		panel.DrawText(buffer);
		
		if(currentLevel >= maxLevel)
		{
			panel.DrawText(" ");
			panel.DrawText("You can prestige now!");
			panel.DrawText("Type !prestige to begin");
		}
	}
	else
	{
		panel.DrawText("MAX PRESTIGE ACHIEVED!");
		panel.DrawText("You have reached the highest");
		panel.DrawText("prestige level possible!");
	}
	
	panel.DrawText(" ");
	panel.DrawItem("Back", ITEMDRAW_DEFAULT);
	panel.DrawItem("Close", ITEMDRAW_DEFAULT);
	
	panel.Send(client, MenuHandler_PrestigeStatus, 30);
	delete panel;
}

public int MenuHandler_PrestigeStatus(Menu menu, MenuAction action, int client, int param2)
{
	if(action == MenuAction_Select)
	{
		if(param2 == 1)
		{
			ShowPrestigeMainMenu(client);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

public Action Command_PrestigeModels(int client, int args)
{
	if(!client)
		return Plugin_Handled;
		
	#if defined _shop_included
	if(g_bShopLoaded)
	{
		CPrintToChat(client, "{green}[Prestige]{default} Please use the Shop menu to equip prestige models!");
		return Plugin_Handled;
	}
	#endif
	
	if(!g_cvPrestigeModels.BoolValue)
	{
		CPrintToChat(client, "{green}[Prestige]{default} Prestige models are currently disabled.");
		return Plugin_Handled;
	}
	
	ShowPrestigeModelsMenu(client);
	
	return Plugin_Handled;
}

void ShowPrestigeModelsMenu(int client)
{
	Menu menu = new Menu(MenuHandler_PrestigeModels);
	menu.SetTitle("Prestige Models\n ");
	
	#if defined _zr_included || defined _zombieriot_included
	menu.AddItem("zombies", "Zombie Models");
	menu.AddItem("humans", "Human Models");
	#else
	menu.AddItem("terrorists", "Terrorist Models");
	menu.AddItem("ct", "Counter-Terrorist Models");
	#endif
	
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_PrestigeModels(Menu menu, MenuAction action, int client, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		
		if(StrEqual(info, "zombies") || StrEqual(info, "terrorists"))
		{
			ShowModelList(client, 1);
		}
		else if(StrEqual(info, "humans") || StrEqual(info, "ct"))
		{
			ShowModelList(client, 0);
		}
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowPrestigeMainMenu(client);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

void ShowModelList(int client, int team)
{
	Menu menu = new Menu(MenuHandler_ModelList);
	
	char teamName[32];
	if(team == 0)
	{
		#if defined _zr_included || defined _zombieriot_included
		strcopy(teamName, sizeof(teamName), "Human");
		#else
		strcopy(teamName, sizeof(teamName), "Counter-Terrorist");
		#endif
	}
	else if(team == 1)
	{
		#if defined _zr_included || defined _zombieriot_included
		strcopy(teamName, sizeof(teamName), "Zombie");
		#else
		strcopy(teamName, sizeof(teamName), "Terrorist");
		#endif
	}
	
	char title[128];
	Format(title, sizeof(title), "%s Models\n ", teamName);
	menu.SetTitle(title);
	
	int clientPrestige = SMRPG_GetClientPrestigeLevel(client);
	bool foundAny = false;
	
	for(int prestige = 0; prestige <= clientPrestige; prestige++)
	{
		for(int i = 0; i < g_hPrestigeModels[prestige].Length; i++)
		{
			PrestigeModel model;
			g_hPrestigeModels[prestige].GetArray(i, model);
			
			if(model.team == team || model.team == 2)
			{
				char itemText[128];
				Format(itemText, sizeof(itemText), "%s (P%d)", model.name, prestige);
				
				char itemData[256];
				Format(itemData, sizeof(itemData), "%d;%s", prestige, model.path);
				menu.AddItem(itemData, itemText);
				
				foundAny = true;
			}
		}
	}
	
	for(int prestige = clientPrestige + 1; prestige <= g_iMaxPrestige; prestige++)
	{
		for(int i = 0; i < g_hPrestigeModels[prestige].Length; i++)
		{
			PrestigeModel model;
			g_hPrestigeModels[prestige].GetArray(i, model);
			
			if(model.team == team || model.team == 2)
			{
				char itemText[128];
				Format(itemText, sizeof(itemText), "%s [Prestige %d Required]", model.name, prestige);
				menu.AddItem("", itemText, ITEMDRAW_DISABLED);
				
				foundAny = true;
			}
		}
	}
	
	if(!foundAny)
	{
		menu.AddItem("", "No models available for this team", ITEMDRAW_DISABLED);
	}
	
	menu.AddItem("", "", ITEMDRAW_SPACER);
	if(g_sClientEquippedModel[client][0] != '\0')
	{
		char currentModel[128];
		bool foundCurrent = false;
		for(int prestige = 0; prestige <= clientPrestige; prestige++)
		{
			for(int i = 0; i < g_hPrestigeModels[prestige].Length; i++)
			{
				PrestigeModel model;
				g_hPrestigeModels[prestige].GetArray(i, model);
				
				if(StrEqual(model.path, g_sClientEquippedModel[client]))
				{
					Format(currentModel, sizeof(currentModel), "Currently: %s (P%d)", model.name, prestige);
					foundCurrent = true;
					break;
				}
			}
			if(foundCurrent) break;
		}
		
		if(foundCurrent)
		{
			menu.AddItem("", currentModel, ITEMDRAW_DISABLED);
		}
		
		menu.AddItem("unequip", "Unequip Current Model");
	}
	else
	{
		menu.AddItem("", "No model currently equipped", ITEMDRAW_DISABLED);
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ModelList(Menu menu, MenuAction action, int client, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[256];
		menu.GetItem(param2, info, sizeof(info));
		
		if(StrEqual(info, "unequip"))
		{
			g_sClientEquippedModel[client][0] = '\0';
			g_iClientEquippedPrestige[client] = -1;
			CPrintToChat(client, "{green}[Prestige]{default} Model unequipped.");
		}
		else
		{
			char parts[2][128];
			ExplodeString(info, ";", parts, sizeof(parts), sizeof(parts[]));
			
			int prestige = StringToInt(parts[0]);
			
			g_sClientEquippedModel[client][0] = '\0';
			g_iClientEquippedPrestige[client] = -1;
			
			strcopy(g_sClientEquippedModel[client], sizeof(g_sClientEquippedModel[]), parts[1]);
			g_iClientEquippedPrestige[client] = prestige;
			
			CPrintToChat(client, "{green}[Prestige]{default} Model equipped! It will be applied on your next spawn.");
			
			if(IsPlayerAlive(client))
			{
				ApplyClientModel(client);
			}
		}
		
		ShowPrestigeModelsMenu(client);
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowPrestigeModelsMenu(client);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
	
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
		ReplyToCommand(client, "Usage: sm_setprestige <player> <level>");
		return Plugin_Handled;
	}
	
	char arg1[32], arg2[4];
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	int target = FindTarget(client, arg1, true, false);
	if(target == -1)
		return Plugin_Handled;
		
	int level = StringToInt(arg2);
	
	if(level < 0 || level > g_iMaxPrestige)
	{
		ReplyToCommand(client, "Invalid prestige level. Must be 0-%d.", g_iMaxPrestige);
		return Plugin_Handled;
	}
	
	int oldPrestige = SMRPG_GetClientPrestigeLevel(target);
	SMRPG_SetClientPrestigeLevel(target, level);
	
	#if defined _shop_included
	if(g_bShopLoaded && level > oldPrestige)
		RemoveOldPrestigeSkins(target);
	#endif
	
	ApplyPrestigeConfig(target);
	UpdateUpgradeVisibility(target);
	
	char adminName[MAX_NAME_LENGTH], targetName[MAX_NAME_LENGTH];
	GetClientName(client, adminName, sizeof(adminName));
	GetClientName(target, targetName, sizeof(targetName));
	
	CPrintToChatAll("{green}[Prestige]{default} {lightgreen}%s{default} has been set to {lightgreen}%s{default} (Prestige %d) by {lightgreen}%s{default}!", 
		targetName, g_PrestigeInfo[level].name, level, adminName);
	
	char centerMessage[128];
	Format(centerMessage, sizeof(centerMessage), "%s\nhas been set to\n%s!", targetName, g_PrestigeInfo[level].name);
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			PrintCenterText(i, centerMessage);
			DataPack pack = new DataPack();
			pack.WriteCell(GetClientUserId(i));
			pack.WriteString(centerMessage);
			CreateTimer(1.0, Timer_CenterText, pack, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	
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
	
	CreateTimer(0.5, Timer_ApplyModel, GetClientUserId(client));
}

#if defined _zr_included
public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if(!IsValidClient(client))
		return;
		
	CreateTimer(0.5, Timer_ApplyModel, GetClientUserId(client));
}

public void ZR_OnClientInfected(int client, int attacker, bool motherInfect, bool respawnOverride, bool respawn)
{
	CreateTimer(0.5, Timer_ApplyModel, GetClientUserId(client));
}
#endif

public Action Timer_ApplyModel(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	
	if(client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
	{
		ApplyClientModel(client);
	}
	
	return Plugin_Continue;
}

#if defined _shop_included
void AwardShopCredits(int client, int baseCredits)
{
	if(!g_bShopLoaded)
		return;
	
	int prestigeLevel = SMRPG_GetClientPrestigeLevel(client);
	float creditMultiplier = g_PrestigeInfo[prestigeLevel].credit_multiplier;
	int finalCredits = RoundFloat(float(baseCredits) * creditMultiplier);
	
	if(finalCredits > 0)
	{
		Shop_GiveClientCredits(client, finalCredits);
		
		if(g_cvPrestigeDebug.BoolValue)
		{
			LogMessage("[Prestige Debug] Awarded %d shop credits to %N (multiplier: %.2fx)", 
				finalCredits, client, creditMultiplier);
		}
	}
}
#endif

void ApplyClientModel(int client)
{
	if(!g_cvPrestigeModels.BoolValue)
		return;
		
	if(g_sClientEquippedModel[client][0] == '\0')
		return;
		
	int clientPrestige = SMRPG_GetClientPrestigeLevel(client);
	
	if(g_iClientEquippedPrestige[client] > clientPrestige)
	{
		g_sClientEquippedModel[client][0] = '\0';
		g_iClientEquippedPrestige[client] = -1;
		
		if(!g_bDisableMessages[client])
			CPrintToChat(client, "{green}[Prestige]{default} Your equipped model was removed as it requires a higher prestige.");
		
		return;
	}
	
	bool isZombie = IsClientZombie(client);
	bool isHuman = IsClientHuman(client);
	int requiredTeam = -1;
	
	for(int i = 0; i < g_hPrestigeModels[g_iClientEquippedPrestige[client]].Length; i++)
	{
		PrestigeModel model;
		g_hPrestigeModels[g_iClientEquippedPrestige[client]].GetArray(i, model);
		
		if(StrEqual(model.path, g_sClientEquippedModel[client]))
		{
			requiredTeam = model.team;
			break;
		}
	}
	
	if(requiredTeam == -1)
	{
		if(g_cvPrestigeDebug.BoolValue)
			LogMessage("[Prestige Debug] Could not find model %s in prestige %d", g_sClientEquippedModel[client], g_iClientEquippedPrestige[client]);
		return;
	}
	
	bool canEquip = false;
	if(requiredTeam == 2)
	{
		canEquip = true;
	}
	else if(requiredTeam == 1 && isZombie)
	{
		canEquip = true;
	}
	else if(requiredTeam == 0 && isHuman)
	{
		canEquip = true;
	}
	
	if(!canEquip)
	{
		if(g_cvPrestigeDebug.BoolValue)
			LogMessage("[Prestige Debug] %N cannot equip model %s (team %d, client is zombie: %s, human: %s)", 
				client, g_sClientEquippedModel[client], requiredTeam, isZombie ? "yes" : "no", isHuman ? "yes" : "no");
		return;
	}
	
	SetEntityModel(client, g_sClientEquippedModel[client]);
	
	if(g_cvPrestigeDebug.BoolValue)
	{
		char teamName[32];
		if(requiredTeam == 0) strcopy(teamName, sizeof(teamName), "Human/CT");
		else if(requiredTeam == 1) strcopy(teamName, sizeof(teamName), "Zombie/T");
		else strcopy(teamName, sizeof(teamName), "Both");
		
		LogMessage("[Prestige Debug] Applied %s model to %N (team: %s, prestige: %d)", 
			teamName, client, isZombie ? "Zombie" : "Human", g_iClientEquippedPrestige[client]);
	}
}

void UpdateUpgradeVisibility(int client)
{
	ApplyPrestigeConfig(client);
}

void SendPrestigeToDiscord(int client, int oldPrestige, int newPrestige, int playerLevelBefore, int playerXPBefore)
{
	if(!g_cvDiscordEnable.BoolValue)
		return;
	
	char webhookURL[512];
	g_cvDiscordWebhook.GetString(webhookURL, sizeof(webhookURL));
	
	if(webhookURL[0] == '\0')
		return;
	
	char clientName[MAX_NAME_LENGTH];
	GetClientName(client, clientName, sizeof(clientName));
	
	char mapName[128];
	GetCurrentMap(mapName, sizeof(mapName));
	
	int playerLevelAfter = SMRPG_GetClientLevel(client);
	int playerXPAfter = SMRPG_GetClientExperience(client);
	
	int players = 0, zombies = 0, humans = 0;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			players++;
			#if defined _zr_included || defined _zombieriot_included
			if(IsClientZombie(i)) zombies++;
			else humans++;
			#else
			if(GetClientTeam(i) == 2) zombies++;
			else if(GetClientTeam(i) == 3) humans++;
			#endif
		}
	}
	
	char timeString[64];
	FormatTime(timeString, sizeof(timeString), "%Y-%m-%d %H:%M:%S", GetTime());
	
	char teamHuman[16], teamZombie[16];
	#if defined _zr_included || defined _zombieriot_included
	strcopy(teamHuman, sizeof(teamHuman), "Human");
	strcopy(teamZombie, sizeof(teamZombie), "Zombie");
	#else
	strcopy(teamHuman, sizeof(teamHuman), "CT");
	strcopy(teamZombie, sizeof(teamZombie), "T");
	#endif
	
	Webhook webhook = new Webhook("");
	
	char title[128];
	Format(title, sizeof(title), "🎉 %s achieved %s!", clientName, g_PrestigeInfo[newPrestige].name);
	
	Embed embed = new Embed(title, "");
	
	int color = 0x00FF00;
	if(newPrestige >= 5) color = 0xFFA500;
	if(newPrestige >= 10) color = 0xFF0000;
	if(newPrestige >= 15) color = 0x800080;
	
	embed.SetColor(color);
	
	char oldPrestigeName[64], newPrestigeName[64];
	strcopy(oldPrestigeName, sizeof(oldPrestigeName), g_PrestigeInfo[oldPrestige].name);
	strcopy(newPrestigeName, sizeof(newPrestigeName), g_PrestigeInfo[newPrestige].name);
	
	char steamId[32];
	if(GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId)))
	{
		char description[512];
		Format(description, sizeof(description),
			"**Player:** %s\n**SteamID:** %s\n**Prestige:** %s → %s\n**Level Before:** %d\n**Level After:** %d\n**Experience Before:** %d XP\n**Experience After:** %d XP\n**Map:** %s\n**Time:** %s\n**Server Players:** %d (%s: %d, %s: %d)", 
			clientName, 
			steamId,
			oldPrestigeName, 
			newPrestigeName,
			playerLevelBefore,
			playerLevelAfter,
			playerXPBefore,
			playerXPAfter,
			mapName, 
			timeString, 
			players, 
			teamHuman, 
			humans, 
			teamZombie, 
			zombies);
		
		embed.SetDescription(description);
	}
	else
	{
		char description[512];
		Format(description, sizeof(description),
			"**Player:** %s\n**Prestige:** %s → %s\n**Level Before:** %d\n**Level After:** %d\n**Experience Before:** %d XP\n**Experience After:** %d XP\n**Map:** %s\n**Time:** %s\n**Server Players:** %d (%s: %d, %s: %d)", 
			clientName,
			oldPrestigeName, 
			newPrestigeName,
			playerLevelBefore,
			playerLevelAfter,
			playerXPBefore,
			playerXPAfter,
			mapName, 
			timeString, 
			players, 
			teamHuman, 
			humans, 
			teamZombie, 
			zombies);
		
		embed.SetDescription(description);
	}
	
	char footerText[128];
	Format(footerText, sizeof(footerText), "Prestige System v1.1 | Before/After comparison");
	EmbedFooter footer = new EmbedFooter(footerText);
	embed.SetFooter(footer);
	delete footer;
	
	webhook.AddEmbed(embed);
	DataPack pack = new DataPack();
	pack.Reset();
	
	webhook.Execute(webhookURL, OnPrestigeWebhookSent, pack);
	
	delete webhook;
}

public void OnPrestigeWebhookSent(HTTPResponse response, DataPack pack)
{
	delete pack;
	if(g_cvPrestigeDebug.BoolValue)
	{
		if(response.Status == HTTPStatus_OK)
			LogMessage("[Prestige Debug] Discord webhook sent successfully");
		else
			LogMessage("[Prestige Debug] Discord webhook failed: Status %d", response.Status);
	}
}

bool IsValidClient(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client);
}

bool IsClientZombie(int client)
{
	#if defined _zr_included
	if(g_bZRAvailable)
	{
		return ZR_IsClientZombie(client);
	}
	#endif
	
	#if defined _zombieriot_included
	if(g_bZRiotAvailable)
	{
		return ZRiot_IsClientZombie(client);
	}
	#endif
	return (GetClientTeam(client) == 2);
}

bool IsClientHuman(int client)
{
	#if defined _zr_included
	if(g_bZRAvailable)
	{
		return !ZR_IsClientZombie(client);
	}
	#endif
	
	#if defined _zombieriot_included
	if(g_bZRiotAvailable)
	{
		return !ZRiot_IsClientZombie(client);
	}
	#endif
	return (GetClientTeam(client) == 3);
}