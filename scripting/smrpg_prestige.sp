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

#define MAX_PRESTIGE 12
#define MAX_UPGRADE_SLOTS 10
#define CONFIG_PATH "configs/smrpg/prestige.cfg"
#define DOWNLOADS_PATH "configs/smrpg/prestige_downloads.txt"

#define MPS MAXPLAYERS+1
#define PMP PLATFORM_MAX_PATH

ConVar g_cvPrestigeEnabled;
ConVar g_cvPrestigeRequiredLevel;
ConVar g_cvPrestigeMaxLevel;
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

ArrayList g_hUpgradeRestrictions[MAX_PRESTIGE + 1];
ArrayList g_hPrestigeSounds[MAX_PRESTIGE + 1];
ArrayList g_hPrestigeModels[MAX_PRESTIGE + 1];

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
	g_cvPrestigeRequiredLevel = CreateConVar("smrpg_prestige_required_level", "1500", "Level required to prestige", FCVAR_NOTIFY);
	g_cvPrestigeMaxLevel = CreateConVar("smrpg_prestige_max_level", "1500", "Max level for each prestige", FCVAR_NOTIFY);
	g_cvPrestigeDebug = CreateConVar("smrpg_prestige_debug", "0", "Enable debug messages", FCVAR_NOTIFY);
	g_cvPrestigeSounds = CreateConVar("smrpg_prestige_sounds", "1", "Enable prestige sounds", FCVAR_NOTIFY);
	g_cvPrestigeModels = CreateConVar("smrpg_prestige_models", "1", "Enable prestige models", FCVAR_NOTIFY);
	g_cvDiscordEnable = CreateConVar("smrpg_prestige_discord", "1", "Enable Discord logging", FCVAR_NOTIFY);
	g_cvDiscordWebhook = CreateConVar("smrpg_prestige_discord_webhook", "", "Discord webhook URL for prestige logging", FCVAR_PROTECTED);
	
	for(int i = 0; i <= MAX_PRESTIGE; i++)
	{
		g_hUpgradeRestrictions[i] = new ArrayList(sizeof(UpgradeRestriction));
		g_hPrestigeSounds[i] = new ArrayList(sizeof(PrestigeSound));
		g_hPrestigeModels[i] = new ArrayList(sizeof(PrestigeModel));
	}
	
	g_hCookieDisableMessages = RegClientCookie("prestige_disable_messages", "Disable prestige messages", CookieAccess_Private);
	g_hCookieDisableMenuPopup = RegClientCookie("prestige_disable_menu_popup", "Disable prestige menu popup", CookieAccess_Private);
	g_bZRAvailable = LibraryExists("zombiereloaded");
	g_bZRiotAvailable = LibraryExists("zombieriot");
	g_bShopLoaded = LibraryExists("shop");
	
	LoadPrestigeConfig();
	LoadDownloadsConfig();
	
	AutoExecConfig(true, "smrpg_prestige");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	
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
	
	for(int i = 0; i <= MAX_PRESTIGE; i++)
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
	return (prestigeLevel > 0);
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
	
	for(int prestige = 1; prestige <= MAX_PRESTIGE; prestige++)
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
		
		if(clientPrestige != requiredPrestige)
		{
			if(clientPrestige < requiredPrestige)
				CPrintToChat(client, "{green}[Shop]{default} This model requires {green}Prestige %d{default}. You are currently {green}Prestige %d{default}.", requiredPrestige, clientPrestige);
			else
				CPrintToChat(client, "{green}[Shop]{default} This model is from {green}Prestige %d{default}. You are now {green}Prestige %d{default} and cannot use old models.", requiredPrestige, clientPrestige);
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
	
	CategoryId categories[2];
	categories[0] = g_category_prestige_zombies;
	categories[1] = g_category_prestige_humans;
	
	for(int cat = 0; cat < 2; cat++)
	{
		CategoryId category_id = categories[cat];
		if(category_id == INVALID_CATEGORY)
			continue;
		
		for(int prestige = 1; prestige < clientPrestige; prestige++)
		{
			for(int i = 0; i < g_hPrestigeModels[prestige].Length; i++)
			{
				PrestigeModel model;
				g_hPrestigeModels[prestige].GetArray(i, model);
				if(category_id == g_category_prestige_zombies && model.team != 1 && model.team != 2)
					continue;
				if(category_id == g_category_prestige_humans && model.team != 0 && model.team != 2)
					continue;
				
				char itemUnique[256];
				Format(itemUnique, sizeof(itemUnique), "prestige_%d_%s_%d", prestige, model.name, i);
				
				ItemId item_id = Shop_GetItemId(category_id, itemUnique);
				if(item_id != INVALID_ITEM)
				{
					if(Shop_IsClientHasItem(client, item_id))
					{
						Shop_RemoveClientItem(client, item_id, 0);
						
						if(g_cvPrestigeDebug.BoolValue)
							LogMessage("[Prestige Debug] Removed old prestige %d item '%s' from %N", prestige, itemUnique, client);
					}
				}
			}
		}
	}
	
	if(g_iClientEquippedPrestige[client] < clientPrestige)
	{
		g_sClientEquippedModel[client][0] = '\0';
		g_iClientEquippedPrestige[client] = -1;
		
		if(!g_bDisableMessages[client])
			CPrintToChat(client, "{green}[Prestige]{default} Your old prestige model has been removed.");
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
	
	ParseUpgradeRestrictions();
	ParsePrestigeSounds();
	ParsePrestigeModels();
	
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

void ParsePrestigeSounds()
{
	for(int prestige = 0; prestige <= MAX_PRESTIGE; prestige++)
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
	for(int prestige = 0; prestige <= MAX_PRESTIGE; prestige++)
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
		
	int requiredLevel = g_cvPrestigeRequiredLevel.IntValue;
	int prestigeLevel = SMRPG_GetClientPrestigeLevel(client);
	
	if(g_cvPrestigeSounds.BoolValue && newlevel > oldlevel)
	{
		PlayPrestigeSound(client, prestigeLevel);
	}
	
	if(newlevel >= requiredLevel && oldlevel < requiredLevel && prestigeLevel < MAX_PRESTIGE && !g_bPrestigeDeclined[client])
	{
		if(!g_bDisableMenuPopup[client])
		{
			ShowPrestigeOffer(client);
		}
		else if(!g_bDisableMessages[client])
		{
			CPrintToChat(client, "{green}[Prestige]{default} You are eligible to prestige! Type {lightgreen}!prestige{default} to view details.");
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
		EmitSoundToClient(client, sound.path);
		
		if(g_cvPrestigeDebug.BoolValue)
			LogMessage("[Prestige Debug] Played sound to %N: %s", client, sound.path);
	}
}

void ShowPrestigeOffer(int client)
{
	Menu menu = new Menu(MenuHandler_PrestigeOffer);
	
	char title[256];
	int currentPrestige = SMRPG_GetClientPrestigeLevel(client);
	int nextPrestige = currentPrestige + 1;
	
	Format(title, sizeof(title), "Prestige Opportunity!\n \nYou've reached level %d!\n \nCurrent: Prestige %d\nNext: Prestige %d\n \nBenefits of Prestige %d:", 
		g_cvPrestigeRequiredLevel.IntValue, currentPrestige, nextPrestige, nextPrestige);
	menu.SetTitle(title);
	
	char prestigeKey[4];
	IntToString(nextPrestige, prestigeKey, sizeof(prestigeKey));
	
	char buffer[128];
	g_kvPrestigeConfig.Rewind();
	if(g_kvPrestigeConfig.JumpToKey(prestigeKey))
	{
		float xpMultiplier = g_kvPrestigeConfig.GetFloat("xp_multiplier", 1.0);
		Format(buffer, sizeof(buffer), "• XP Rate: %.0f%%", xpMultiplier * 100);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		
		float creditMultiplier = g_kvPrestigeConfig.GetFloat("credit_multiplier", 1.0);
		Format(buffer, sizeof(buffer), "• Credit Bonus: +%.0f%%", (creditMultiplier - 1.0) * 100);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		
		Format(buffer, sizeof(buffer), "• New upgrades unlocked");
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		
		if(g_cvPrestigeModels.BoolValue && g_hPrestigeModels[nextPrestige].Length > 0)
		{
			Format(buffer, sizeof(buffer), "• %d new models available", g_hPrestigeModels[nextPrestige].Length);
			menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		}
		
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
	
	return 0;
}

void HandlePrestigeDecline(int client)
{
	g_bPrestigeDeclined[client] = true;
	
	int currentPrestige = SMRPG_GetClientPrestigeLevel(client);
	int nextPrestige = currentPrestige + 1;
	
	if(!g_bDisableMessages[client])
	{
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
			
			CPrintToChat(client, "{green}[Prestige]{default} You're missing: {lightgreen}%.0f%% XP{default} and {lightgreen}+%.0f%% credits{default}", 
				xpMultiplier * 100, (creditMultiplier - 1.0) * 100);
		}
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
		Format(buffer, sizeof(buffer), "XP Rate: %.0f%%", xpMultiplier * 100);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		
		float creditMultiplier = g_kvPrestigeConfig.GetFloat("credit_multiplier", 1.0);
		Format(buffer, sizeof(buffer), "Credit Bonus: +%.0f%%", (creditMultiplier - 1.0) * 100);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		
		int maxLevel = g_kvPrestigeConfig.GetNum("max_level", 1500);
		Format(buffer, sizeof(buffer), "Max Level: %d", maxLevel);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		
		if(g_hPrestigeModels[nextPrestige].Length > 0)
		{
			Format(buffer, sizeof(buffer), "Models Available: %d", g_hPrestigeModels[nextPrestige].Length);
			menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		}
		
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
	
	return 0;
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
		
		#if defined _shop_included
		if(g_bShopLoaded)
			RemoveOldPrestigeSkins(client);
		#endif
		
		if(g_iClientEquippedPrestige[client] >= 0 && g_iClientEquippedPrestige[client] < newPrestige)
		{
			g_sClientEquippedModel[client][0] = '\0';
			g_iClientEquippedPrestige[client] = -1;
			
			if(!g_bDisableMessages[client])
				CPrintToChat(client, "{green}[Prestige]{default} Your previous prestige model has been unequipped.");
		}
		
		ApplyPrestigeConfig(client);
		SendPrestigeToDiscord(client, currentPrestige, newPrestige);
		
		if(g_cvPrestigeSounds.BoolValue && g_hPrestigeSounds[newPrestige].Length > 0)
		{
			int randomIndex = GetRandomInt(0, g_hPrestigeSounds[newPrestige].Length - 1);
			PrestigeSound sound;
			g_hPrestigeSounds[newPrestige].GetArray(randomIndex, sound);
			
			if(sound.path[0] != '\0')
			{
				EmitSoundToClient(client, sound.path);
				
				if(g_cvPrestigeDebug.BoolValue)
					LogMessage("[Prestige Debug] Played prestige up sound to %N: %s", client, sound.path);
			}
		}
		
		if(!g_bDisableMessages[client])
		{
			CPrintToChat(client, "{green}[Prestige]{default} Congratulations! You are now {green}Prestige %d{default}!", newPrestige);
			CPrintToChat(client, "{green}[Prestige]{default} Your stats have been reset. New journey begins!");
			
			if(g_cvPrestigeModels.BoolValue && g_hPrestigeModels[newPrestige].Length > 0)
			{
				CPrintToChat(client, "{green}[Prestige]{default} You've unlocked {green}%d new models{default}! Type {lightgreen}!prestigemodels{default} to equip them.", 
					g_hPrestigeModels[newPrestige].Length);
			}
		}
		
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
	
	ShowPrestigeMainMenu(client);
	
	return Plugin_Handled;
}

void ShowPrestigeMainMenu(int client)
{
	Menu menu = new Menu(MenuHandler_PrestigeMain);
	
	int prestigeLevel = SMRPG_GetClientPrestigeLevel(client);
	int currentLevel = SMRPG_GetClientLevel(client);
	int maxLevel = SMRPG_GetClientPrestigeMaxLevel(client);
	int requiredLevel = g_cvPrestigeRequiredLevel.IntValue;
	
	char title[256];
	Format(title, sizeof(title), "Prestige Menu\n \nPrestige: %d/%d | Level: %d/%d\n ", 
		prestigeLevel, MAX_PRESTIGE, currentLevel, maxLevel);
	menu.SetTitle(title);
	
	menu.AddItem("details", "View Details");
	
	if(currentLevel >= requiredLevel && prestigeLevel < MAX_PRESTIGE)
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
	
	if(nextPrestige > MAX_PRESTIGE)
	{
		CPrintToChat(client, "{green}[Prestige]{default} You are at maximum prestige!");
		ShowPrestigeMainMenu(client);
		return;
	}
	
	Menu menu = new Menu(MenuHandler_NextLevel);
	
	char title[256];
	Format(title, sizeof(title), "Next Prestige Level (%d)\n ", nextPrestige);
	menu.SetTitle(title);
	
	char buffer[128];
	char prestigeKey[4];
	IntToString(nextPrestige, prestigeKey, sizeof(prestigeKey));
	
	g_kvPrestigeConfig.Rewind();
	if(g_kvPrestigeConfig.JumpToKey(prestigeKey))
	{
		char name[64];
		g_kvPrestigeConfig.GetString("name", name, sizeof(name), "Unknown");
		Format(buffer, sizeof(buffer), "Name: %s", name);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		
		int requiredLevel = g_cvPrestigeRequiredLevel.IntValue;
		Format(buffer, sizeof(buffer), "Required Level: %d", requiredLevel);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		
		float xpMultiplier = g_kvPrestigeConfig.GetFloat("xp_multiplier", 1.0);
		Format(buffer, sizeof(buffer), "XP Multiplier: %.0f%%", xpMultiplier * 100);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		
		float creditMultiplier = g_kvPrestigeConfig.GetFloat("credit_multiplier", 1.0);
		Format(buffer, sizeof(buffer), "Credit Multiplier: +%.0f%%", (creditMultiplier - 1.0) * 100);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		
		int maxLevel = g_kvPrestigeConfig.GetNum("max_level", 1500);
		Format(buffer, sizeof(buffer), "Max Level: %d", maxLevel);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		
		if(g_hPrestigeModels[nextPrestige].Length > 0)
		{
			Format(buffer, sizeof(buffer), "New Models: %d", g_hPrestigeModels[nextPrestige].Length);
			menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		}
	}
	
	menu.AddItem("", "", ITEMDRAW_SPACER);
	menu.AddItem("back", "Back");
	
	menu.ExitButton = true;
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
	
	menu.AddItem("", "", ITEMDRAW_SPACER);
	menu.AddItem("back", "Back");
	
	menu.ExitButton = true;
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
		else if(StrEqual(info, "back"))
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
	
	char prestigeKey[4];
	IntToString(prestigeLevel, prestigeKey, sizeof(prestigeKey));
	
	g_kvPrestigeConfig.Rewind();
	if(g_kvPrestigeConfig.JumpToKey(prestigeKey))
	{
		char name[64];
		g_kvPrestigeConfig.GetString("name", name, sizeof(name), "Unknown");
		Format(buffer, sizeof(buffer), "Prestige Name: %s", name);
		panel.DrawText(buffer);
	}
	
	panel.DrawText(" ");
	
	if(prestigeLevel < MAX_PRESTIGE)
	{
		if(maxLevel > 0)
		{
			Format(buffer, sizeof(buffer), "Next Prestige at: Level %d", maxLevel);
			panel.DrawText(buffer);
			
			int progress = currentLevel * 100 / maxLevel;
			Format(buffer, sizeof(buffer), "Progress: %d%% (%d/%d)", progress, currentLevel, maxLevel);
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
				
				if(prestige <= clientPrestige)
				{
					menu.AddItem(itemData, itemText);
				}
				else
				{
					Format(itemText, sizeof(itemText), "%s [Prestige %d Required]", model.name, prestige);
					menu.AddItem("", itemText, ITEMDRAW_DISABLED);
				}
				
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
	
	if(level < 0 || level > MAX_PRESTIGE)
	{
		ReplyToCommand(client, "Invalid prestige level. Must be 0-%d.", MAX_PRESTIGE);
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

void SendPrestigeToDiscord(int client, int oldPrestige, int newPrestige)
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
	Embed embed = new Embed("🎉 Prestige Achieved", "");
	embed.SetColor(0x00FF00);
	
	char description[512];
	Format(description, sizeof(description),
		"**Player:** %s\n**Prestige:** %d → %d\n**Map:** %s\n**Time:** %s\n**Players:** %d (%s: %d, %s: %d)", 
		clientName, oldPrestige, newPrestige, mapName, timeString, players, teamHuman, humans, teamZombie, zombies);
	
	embed.SetDescription(description);
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
