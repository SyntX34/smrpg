#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "gravitywell"

ConVar g_hCVCooldown;
ConVar g_hCVRadius;
ConVar g_hCVGravityStrength;
ConVar g_hCVDuration;

Handle g_hGravityWellTimer[MAXPLAYERS+1];
bool g_bGravityWellActive[MAXPLAYERS+1];
float g_fGravityWellPosition[MAXPLAYERS+1][3];

public Plugin myinfo = 
{
    name = "SM:RPG Upgrade > Gravity Well",
    author = "+SyntX",
    description = "Create a gravity well that attracts enemies to a point.",
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
        SMRPG_RegisterUpgradeType("Gravity Well", UPGRADE_SHORTNAME, "Create a gravity well that attracts enemies to a point.", 8, true, 10, 20, 15);
        SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
        SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
        
        g_hCVCooldown = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_gravitywell_cooldown", "75.0", "Cooldown time in seconds", 0, true, 1.0);
        g_hCVRadius = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_gravitywell_radius", "350.0", "Radius of gravity well effect", 0, true, 100.0);
        g_hCVGravityStrength = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_gravitywell_strength", "300.0", "Strength of gravity pull", 0, true, 50.0);
        g_hCVDuration = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_gravitywell_duration", "6.0", "Duration of gravity well effect in seconds", 0, true, 1.0);
    }
}

public void OnClientPutInServer(int client)
{
    g_hGravityWellTimer[client] = null;
    g_bGravityWellActive[client] = false;
}

public void OnClientDisconnect(int client)
{
    if(g_hGravityWellTimer[client] != null)
    {
        KillTimer(g_hGravityWellTimer[client]);
        g_hGravityWellTimer[client] = null;
    }
    g_bGravityWellActive[client] = false;
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
        if(g_bGravityWellActive[client])
        {
            g_bGravityWellActive[client] = false;
        }
    }
}

/**
 * Activate gravity well ability
 */
public void SMRPG_UpgradeActivated(int client, const char[] shortname)
{
    if(!StrEqual(shortname, UPGRADE_SHORTNAME))
        return;
    
    if(g_hGravityWellTimer[client] != null)
    {
        // PrintToChat(client, "Gravity Well is on cooldown!");
        return;
    }
    
    if(!IsPlayerAlive(client))
    {
        // PrintToChat(client, "You must be alive to use Gravity Well!");
        return;
    }
    
    if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
        return;
    
    // Activate gravity well at player position
    ActivateGravityWell(client);
    
    // Set cooldown
    float cooldown = g_hCVCooldown.FloatValue;
    g_hGravityWellTimer[client] = CreateTimer(cooldown, GravityWellCooldown_Timer, client);
}

/**
 * Activate gravity well effect
 */
void ActivateGravityWell(int client)
{
    int level = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
    float radius = g_hCVRadius.FloatValue;
    float duration = g_hCVDuration.FloatValue;
    
    g_bGravityWellActive[client] = true;
    
    // Set gravity well position
    GetClientAbsOrigin(client, g_fGravityWellPosition[client]);
    
    // Create visual effects
    TE_SetupBeamRingPoint(g_fGravityWellPosition[client], 0.0, radius, PrecacheModel("sprites/laser.vmt"), PrecacheModel("sprites/halo01.vmt"), 0, 15, duration, 10.0, 0.0, {100, 0, 255, 255}, 10, 0);
    TE_SendToAll();
    
    // Create a dynamic light for the gravity well
    int iEnt = CreateEntityByName("light_dynamic");
    if(iEnt != INVALID_ENT_REFERENCE)
    {
        char sBuffer[64];
        Format(sBuffer, sizeof(sBuffer), "gravitywell_%d", client);
        DispatchKeyValue(iEnt,"targetname", sBuffer);
        Format(sBuffer, sizeof(sBuffer), "%f %f %f", g_fGravityWellPosition[client][0], g_fGravityWellPosition[client][1], g_fGravityWellPosition[client][2]);
        DispatchKeyValue(iEnt, "origin", sBuffer);
        DispatchKeyValue(iEnt, "angles", "0 0 0");
        DispatchKeyValue(iEnt, "_light", "100 0 255 200");
        DispatchKeyValue(iEnt, "pitch","0");
        DispatchKeyValue(iEnt, "distance","256");
        DispatchKeyValue(iEnt, "spotlight_radius","128");
        DispatchKeyValue(iEnt, "brightness","4");
        DispatchKeyValue(iEnt, "style","6");
        DispatchKeyValue(iEnt, "spawnflags","1");
        DispatchSpawn(iEnt);
        AcceptEntityInput(iEnt, "DisableShadow");
        
        char sAddOutput[64];
        Format(sAddOutput, sizeof(sAddOutput), "OnUser1 !self:kill::%f:1", duration);
        SetVariantString(sAddOutput);
        AcceptEntityInput(iEnt, "AddOutput");
        AcceptEntityInput(iEnt, "FireUser1");
    }
    
    // Apply gravity well effect periodically
    CreateTimer(0.1, GravityWellEffect_Timer, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
    
    // End gravity well after duration
    CreateTimer(duration, EndGravityWell_Timer, client);
    
    // PrintToChat(client, "Gravity Well activated! Attracting enemies for %f seconds.", duration);
}

/**
 * Gravity well effect timer
 */
public Action GravityWellEffect_Timer(Handle timer, any client)
{
    if(!IsClientInGame(client) || !g_bGravityWellActive[client])
        return Plugin_Stop;
    
    if(!IsPlayerAlive(client))
    {
        g_bGravityWellActive[client] = false;
        return Plugin_Stop;
    }
    
    float radius = g_hCVRadius.FloatValue;
    float gravityStrength = g_hCVGravityStrength.FloatValue;
    
    // Attract enemies toward gravity well
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientInGame(i) || !IsPlayerAlive(i) || i == client)
            continue;
        
        if(!SMRPG_IsFFAEnabled() && GetClientTeam(i) == GetClientTeam(client))
            continue;
        
        float targetPos[3];
        GetClientAbsOrigin(i, targetPos);
        
        float distance = GetVectorDistance(g_fGravityWellPosition[client], targetPos);
        if(distance <= radius)
        {
            // Pull toward gravity well center
            float direction[3];
            MakeVectorFromPoints(targetPos, g_fGravityWellPosition[client], direction);
            NormalizeVector(direction, direction);
            ScaleVector(direction, gravityStrength * (1.0 - (distance / radius))); // Stronger pull when closer to edge
            
            // Apply velocity
            TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, direction);
        }
    }
    
    return Plugin_Continue;
}

/**
 * End gravity well effect
 */
public Action EndGravityWell_Timer(Handle timer, any client)
{
    if(IsClientInGame(client))
    {
        g_bGravityWellActive[client] = false;
        // PrintToChat(client, "Gravity Well effect ended.");
    }
    return Plugin_Stop;
}

/**
 * Timer callbacks
 */
public Action GravityWellCooldown_Timer(Handle timer, any client)
{
    if(IsClientInGame(client))
    {
        g_hGravityWellTimer[client] = null;
        // PrintToChat(client, "Gravity Well is ready!");
    }
    return Plugin_Stop;
}