#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "vortex"

ConVar g_hCVCooldown;
ConVar g_hCVRadius;
ConVar g_hCVDuration;
ConVar g_hCVDamage;

Handle g_hVortexTimer[MAXPLAYERS+1];
bool g_bVortexActive[MAXPLAYERS+1];

public Plugin myinfo = 
{
    name = "SM:RPG Upgrade > Vortex",
    author = "+SyntX",
    description = "Create a vortex that pulls enemies toward the center and damages them.",
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
        SMRPG_RegisterUpgradeType("Vortex", UPGRADE_SHORTNAME, "Create a vortex that pulls enemies toward center and damages them.", 10, true, 10, 20, 15);
        SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
        SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
        
        g_hCVCooldown = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_vortex_cooldown", "90.0", "Cooldown time in seconds", 0, true, 1.0);
        g_hCVRadius = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_vortex_radius", "400.0", "Radius of vortex effect", 0, true, 100.0);
        g_hCVDuration = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_vortex_duration", "5.0", "Duration of vortex effect in seconds", 0, true, 1.0);
        g_hCVDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_vortex_damage", "10.0", "Damage per second", 0, true, 1.0);
    }
}

public void OnClientPutInServer(int client)
{
    g_hVortexTimer[client] = null;
    g_bVortexActive[client] = false;
}

public void OnClientDisconnect(int client)
{
    if(g_hVortexTimer[client] != null)
    {
        KillTimer(g_hVortexTimer[client]);
        g_hVortexTimer[client] = null;
    }
    g_bVortexActive[client] = false;
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
        if(g_bVortexActive[client])
        {
            g_bVortexActive[client] = false;
        }
    }
}

/**
 * Activate vortex ability
 */
public void SMRPG_UpgradeActivated(int client, const char[] shortname)
{
    if(!StrEqual(shortname, UPGRADE_SHORTNAME))
        return;
    
    if(g_hVortexTimer[client] != null)
    {
        // PrintToChat(client, "Vortex is on cooldown!");
        return;
    }
    
    if(!IsPlayerAlive(client))
    {
        // PrintToChat(client, "You must be alive to use Vortex!");
        return;
    }
    
    if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
        return;
    
    // Activate vortex
    ActivateVortex(client);
    
    // Set cooldown
    float cooldown = g_hCVCooldown.FloatValue;
    g_hVortexTimer[client] = CreateTimer(cooldown, VortexCooldown_Timer, client);
}

/**
 * Activate vortex effect
 */
void ActivateVortex(int client)
{
    int level = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
    float radius = g_hCVRadius.FloatValue;
    float duration = g_hCVDuration.FloatValue;
    
    g_bVortexActive[client] = true;
    
    // Create visual effects
    float clientPos[3];
    GetClientAbsOrigin(client, clientPos);
    
    // Create spiral effect
    for(int i = 0; i < 5; i++)
    {
        float height = float(i) * 20.0;
        TE_SetupBeamRingPoint(clientPos, 0.0, radius - float(i) * 50.0, PrecacheModel("sprites/laser.vmt"), PrecacheModel("sprites/halo01.vmt"), 0, 15, duration/5.0, 5.0, 0.0, {0, 100, 255, 255}, 10, 0);
        TE_SendToAll();
    }
    
    // Apply vortex effect periodically
    CreateTimer(1.0, VortexEffect_Timer, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
    
    // End vortex after duration
    CreateTimer(duration, EndVortex_Timer, client);
    
    // PrintToChat(client, "Vortex activated! Pulling enemies for %f seconds.", duration);
}

/**
 * Vortex effect timer
 */
public Action VortexEffect_Timer(Handle timer, any client)
{
    if(!IsClientInGame(client) || !g_bVortexActive[client])
        return Plugin_Stop;
    
    if(!IsPlayerAlive(client))
    {
        g_bVortexActive[client] = false;
        return Plugin_Stop;
    }
    
    float clientPos[3];
    GetClientAbsOrigin(client, clientPos);
    float radius = g_hCVRadius.FloatValue;
    float damage = g_hCVDamage.FloatValue;
    
    // Pull enemies toward center and damage them
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
            // Pull toward center
            float direction[3];
            MakeVectorFromPoints(targetPos, clientPos, direction);
            NormalizeVector(direction, direction);
            ScaleVector(direction, 100.0 * (1.0 - (distance / radius))); // Stronger pull when closer to edge
            
            // Apply velocity
            TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, direction);
            
            // Deal damage
            SDKHooks_TakeDamage(i, client, client, damage, DMG_GENERIC);
        }
    }
    
    return Plugin_Continue;
}

/**
 * End vortex effect
 */
public Action EndVortex_Timer(Handle timer, any client)
{
    if(IsClientInGame(client))
    {
        g_bVortexActive[client] = false;
        // PrintToChat(client, "Vortex effect ended.");
    }
    return Plugin_Stop;
}

/**
 * Timer callbacks
 */
public Action VortexCooldown_Timer(Handle timer, any client)
{
    if(IsClientInGame(client))
    {
        g_hVortexTimer[client] = null;
        // PrintToChat(client, "Vortex is ready!");
    }
    return Plugin_Stop;
}