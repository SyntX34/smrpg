#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "shadowstep"

ConVar g_hCVCooldown;
ConVar g_hCVDistance;
ConVar g_hCVTeleportDelay;

Handle g_hShadowStepTimer[MAXPLAYERS+1];
bool g_bShadowStepping[MAXPLAYERS+1];
float g_fShadowStepPosition[MAXPLAYERS+1][3];

public Plugin myinfo = 
{
    name = "SM:RPG Upgrade > Shadow Step",
    author = "+SyntX",
    description = "Teleport behind enemies to flank them.",
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
        SMRPG_RegisterUpgradeType("Shadow Step", UPGRADE_SHORTNAME, "Teleport behind nearby enemies.", 5, true, 10, 20, 15);
        SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
        SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
        
        g_hCVCooldown = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_shadowstep_cooldown", "45.0", "Cooldown time in seconds", 0, true, 1.0);
        g_hCVDistance = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_shadowstep_distance", "200.0", "Distance behind target to teleport", 0, true, 50.0);
        g_hCVTeleportDelay = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_shadowstep_delay", "0.5", "Delay before teleport in seconds", 0, true, 0.1);
    }
}

public void OnClientPutInServer(int client)
{
    g_hShadowStepTimer[client] = null;
    g_bShadowStepping[client] = false;
}

public void OnClientDisconnect(int client)
{
    if(g_hShadowStepTimer[client] != null)
    {
        KillTimer(g_hShadowStepTimer[client]);
        g_hShadowStepTimer[client] = null;
    }
    g_bShadowStepping[client] = false;
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
        if(g_bShadowStepping[client])
        {
            g_bShadowStepping[client] = false;
        }
    }
}

/**
 * Activate shadow step ability
 */
public void SMRPG_UpgradeActivated(int client, const char[] shortname)
{
    if(!StrEqual(shortname, UPGRADE_SHORTNAME))
        return;
    
    if(g_hShadowStepTimer[client] != null)
    {
        // PrintToChat(client, "Shadow Step is on cooldown!");
        return;
    }
    
    if(!IsPlayerAlive(client))
    {
        // PrintToChat(client, "You must be alive to use Shadow Step!");
        return;
    }
    
    if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
        return;
    
    // Find target to teleport behind
    int target = FindNearestEnemy(client);
    if(target == -1)
    {
        // PrintToChat(client, "No nearby enemies found!");
        return;
    }
    
    // Mark as shadow stepping
    g_bShadowStepping[client] = true;
    
    // Calculate teleport position
    CalculateTeleportPosition(client, target);
    
    // Visual effect before teleport
    float clientPos[3];
    GetClientAbsOrigin(client, clientPos);
    TE_SetupBeamPoints(clientPos, g_fShadowStepPosition[client], PrecacheModel("sprites/laser.vmt"), PrecacheModel("sprites/halo01.vmt"), 0, 15, g_hCVTeleportDelay.FloatValue, 5.0, 5.0, 0, 0.0, {100, 0, 255, 255}, 0);
    TE_SendToAll();
    
    // Set teleport timer
    CreateTimer(g_hCVTeleportDelay.FloatValue, Teleport_Timer, client);
    
    // Set cooldown
    float cooldown = g_hCVCooldown.FloatValue;
    g_hShadowStepTimer[client] = CreateTimer(cooldown, ShadowStepCooldown_Timer, client);
}

/**
 * Find nearest enemy
 */
int FindNearestEnemy(int client)
{
    int target = -1;
    float closestDistance = g_hCVDistance.FloatValue * 2.0; // Search within double the teleport distance
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
        if(distance < closestDistance)
        {
            closestDistance = distance;
            target = i;
        }
    }
    
    return target;
}

/**
 * Calculate teleport position behind target
 */
void CalculateTeleportPosition(int client, int target)
{
    float targetPos[3], targetAngle[3];
    GetClientAbsOrigin(target, targetPos);
    GetClientEyeAngles(target, targetAngle);
    
    // Calculate position behind target
    float direction[3];
    GetAngleVectors(targetAngle, direction, NULL_VECTOR, NULL_VECTOR);
    direction[2] = 0.0; // Keep on same level
    NormalizeVector(direction, direction);
    ScaleVector(direction, -g_hCVDistance.FloatValue); // Behind the target
    
    AddVectors(targetPos, direction, g_fShadowStepPosition[client]);
    g_fShadowStepPosition[client][2] = targetPos[2]; // Keep same height
}

/**
 * Timer callbacks
 */
public Action Teleport_Timer(Handle timer, any client)
{
    if(IsClientInGame(client) && IsPlayerAlive(client) && g_bShadowStepping[client])
    {
        TeleportEntity(client, g_fShadowStepPosition[client], NULL_VECTOR, NULL_VECTOR);
        // PrintToChat(client, "Shadow Step successful!");
        g_bShadowStepping[client] = false;
    }
    return Plugin_Stop;
}

public Action ShadowStepCooldown_Timer(Handle timer, any client)
{
    if(IsClientInGame(client))
    {
        g_hShadowStepTimer[client] = null;
        // PrintToChat(client, "Shadow Step is ready!");
    }
    return Plugin_Stop;
}