#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "timewarp"

ConVar g_hCVCooldown;
ConVar g_hCVDuration;
ConVar g_hCVRadius;

Handle g_hTimeWarpTimer[MAXPLAYERS+1];
bool g_bTimeWarped[MAXPLAYERS+1];

public Plugin myinfo = 
{
    name = "SM:RPG Upgrade > Time Warp",
    author = "+SyntX",
    description = "Slow down time for nearby enemies when activated.",
    version = SMRPG_VERSION,
    url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
    LoadTranslations("smrpg_stock_upgrades.phrases");
    
    for(int i=1;i<=MaxClients;i++)
    {
        if(IsClientInGame(i))
            OnClientPutInServer(i);
    }
}

public void OnPluginEnd()
{
    if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME))
        SMRPG_UnregisterUpgradeType(UPGRADE_SHORTNAME);
}

public void OnAllPluginsLoaded()
{
    OnLibraryAdded("smrpg");
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "smrpg"))
    {
        SMRPG_RegisterUpgradeType("Time Warp", UPGRADE_SHORTNAME, "Slows down time for nearby enemies in a radius.", 5, true, 10, 20, 15);
        SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
        SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
        
        g_hCVCooldown = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_timewarp_cooldown", "60.0", "Cooldown time in seconds", 0, true, 1.0);
        g_hCVDuration = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_timewarp_duration", "5.0", "Duration of time warp effect in seconds", 0, true, 1.0);
        g_hCVRadius = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_timewarp_radius", "300.0", "Radius of time warp effect", 0, true, 100.0);
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_PreThink, OnPlayerPreThink);
    g_hTimeWarpTimer[client] = null;
    g_bTimeWarped[client] = false;
}

public void OnClientDisconnect(int client)
{
    if(g_hTimeWarpTimer[client] != null)
    {
        KillTimer(g_hTimeWarpTimer[client]);
        g_hTimeWarpTimer[client] = null;
    }
    g_bTimeWarped[client] = false;
}

/**
 * SM:RPG Upgrade callbacks
 */
public void SMRPG_TranslateUpgrade(int client, const char[] shortname, TranslationType type, char[] translation, int maxlen)
{
    if(type == TranslationType_Name)
        Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
    else if(type == TranslationType_Description)
    {
        char sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
        StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
        Format(translation, maxlen, "%T", sDescriptionKey, client);
    }
}

public void SMRPG_BuySell(int client, UpgradeQueryType type)
{
    // Reset any active effects when upgrade is sold
    if(type == UpgradeQueryType_Sell)
    {
        if(g_bTimeWarped[client])
        {
            EndTimeWarp(client);
        }
    }
}

/**
 * Player think hook
 */
public void OnPlayerPreThink(int client)
{
    if(g_bTimeWarped[client])
    {
        // Slow down player movement
        SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 0.5);
    }
}

/**
 * Activate time warp ability
 */
public void SMRPG_UpgradeActivated(int client, const char[] shortname)
{
    if(!StrEqual(shortname, UPGRADE_SHORTNAME))
        return;
    
    if(g_hTimeWarpTimer[client] != null)
    {
        // PrintToChat(client, "Time Warp is on cooldown!");
        return;
    }
    
    if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
        return;
    
    // Activate time warp
    StartTimeWarp(client);
    
    // Set cooldown
    float cooldown = g_hCVCooldown.FloatValue;
    g_hTimeWarpTimer[client] = CreateTimer(cooldown, TimeWarpCooldown_Timer, client);
}

/**
 * Start time warp effect
 */
void StartTimeWarp(int client)
{
    int level = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
    float radius = g_hCVRadius.FloatValue;
    float duration = g_hCVDuration.FloatValue;
    
    // Find nearby enemies
    float clientPos[3];
    GetClientAbsOrigin(client, clientPos);
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientInGame(i) || !IsPlayerAlive(i) || i == client)
            continue;
        
        if(!SMRPG_IsFFAEnabled() && GetClientTeam(i) == GetClientTeam(client))
            continue;
        
        float targetPos[3];
        GetClientAbsOrigin(i, targetPos);
        
        float distance = GetVectorDistance(clientPos, targetPos);
        if(distance <= radius)
        {
            g_bTimeWarped[i] = true;
            // Set a timer to end the effect for this player
            CreateTimer(duration, EndTimeWarp_Timer, i);
        }
    }
    
    // Visual effect
    TE_SetupBeamRingPoint(clientPos, 0.0, radius, PrecacheModel("sprites/laser.vmt"), PrecacheModel("sprites/halo01.vmt"), 0, 15, duration, 10.0, 0.0, {100, 100, 255, 255}, 10, 0);
    TE_SendToAll();
    
    // PrintToChat(client, "Time Warp activated! Nearby enemies slowed for %f seconds.", duration);
}

/**
 * End time warp effect
 */
void EndTimeWarp(int client)
{
    g_bTimeWarped[client] = false;
    SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
}

/**
 * Timer callbacks
 */
public Action TimeWarpCooldown_Timer(Handle timer, any client)
{
    if(IsClientInGame(client))
    {
        g_hTimeWarpTimer[client] = null;
        // PrintToChat(client, "Time Warp is ready!");
    }
    return Plugin_Stop;
}

public Action EndTimeWarp_Timer(Handle timer, any client)
{
    if(IsClientInGame(client))
    {
        EndTimeWarp(client);
        // PrintToChat(client, "Time Warp effect ended.");
    }
    return Plugin_Stop;
}