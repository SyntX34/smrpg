#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "chainlightning"
#define MAX_CHAIN_TARGETS 10

ConVar g_hCVCooldown;
ConVar g_hCVInitialDamage;
ConVar g_hCVDamageDecay;
ConVar g_hCVMaxChains;
ConVar g_hCVChainRadius;
ConVar g_hCVChainDelay;

Handle g_hChainTimer[MAXPLAYERS+1];
bool g_bChainActive[MAXPLAYERS+1];
int g_iChainedTargets[MAXPLAYERS+1][MAX_CHAIN_TARGETS];
int g_iChainCount[MAXPLAYERS+1];

public Plugin myinfo = 
{
    name = "SM:RPG Upgrade > Chain Lightning",
    author = "+SyntX",
    description = "Unleash chain lightning that bounces between enemies, dealing decreasing damage.",
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
        SMRPG_RegisterUpgradeType("Chain Lightning", UPGRADE_SHORTNAME, "Unleash lightning that chains between enemies.", 10, true, 10, 20, 15);
        SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
        SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
        
        g_hCVCooldown = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_chainlightning_cooldown", "45.0", "Cooldown time in seconds", 0, true, 1.0);
        g_hCVInitialDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_chainlightning_damage", "40.0", "Initial damage to first target", 0, true, 1.0);
        g_hCVDamageDecay = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_chainlightning_decay", "0.75", "Damage multiplier per chain (0.75 = 75% of previous)", 0, true, 0.1, true, 1.0);
        g_hCVMaxChains = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_chainlightning_maxchains", "5", "Maximum number of chain bounces", 0, true, 1.0);
        g_hCVChainRadius = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_chainlightning_radius", "400.0", "Radius to search for next target", 0, true, 50.0);
        g_hCVChainDelay = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_chainlightning_delay", "0.15", "Delay between each chain in seconds", 0, true, 0.05);
    }
}

public void OnClientPutInServer(int client)
{
    g_hChainTimer[client] = null;
    g_bChainActive[client] = false;
    g_iChainCount[client] = 0;
    
    for(int i = 0; i < MAX_CHAIN_TARGETS; i++)
        g_iChainedTargets[client][i] = 0;
}

public void OnClientDisconnect(int client)
{
    if(g_hChainTimer[client] != null)
    {
        KillTimer(g_hChainTimer[client]);
        g_hChainTimer[client] = null;
    }
    g_bChainActive[client] = false;
    g_iChainCount[client] = 0;
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
    if(type == UpgradeQueryType_Sell)
    {
        if(g_bChainActive[client])
        {
            g_bChainActive[client] = false;
        }
    }
}

/**
 * Activate chain lightning ability
 */
public void SMRPG_UpgradeActivated(int client, const char[] shortname)
{
    if(!StrEqual(shortname, UPGRADE_SHORTNAME))
        return;
    
    if(g_hChainTimer[client] != null)
    {
        // PrintToChat(client, "Chain Lightning is on cooldown!");
        return;
    }
    
    if(!IsPlayerAlive(client))
    {
        // PrintToChat(client, "You must be alive to use Chain Lightning!");
        return;
    }
    
    if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
        return;
    
    // Find first target
    int firstTarget = FindNearestEnemy(client, -1);
    if(firstTarget == -1)
    {
        // PrintToChat(client, "No enemies in range!");
        return;
    }
    
    // Reset chain data
    g_iChainCount[client] = 0;
    for(int i = 0; i < MAX_CHAIN_TARGETS; i++)
        g_iChainedTargets[client][i] = 0;
    
    // Start the chain lightning
    InitiateChainLightning(client, firstTarget);
    
    // Set cooldown
    float cooldown = g_hCVCooldown.FloatValue;
    g_hChainTimer[client] = CreateTimer(cooldown, ChainLightningCooldown_Timer, client);
}

/**
 * Find nearest enemy that hasn't been chained yet
 */
int FindNearestEnemy(int client, int lastTarget)
{
    int target = -1;
    float closestDistance = g_hCVChainRadius.FloatValue;
    float searchPos[3];
    
    if(lastTarget == -1)
    {
        // First target - search from player position
        GetClientAbsOrigin(client, searchPos);
    }
    else
    {
        // Chain target - search from last target position
        GetClientAbsOrigin(lastTarget, searchPos);
    }
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientInGame(i) || !IsPlayerAlive(i) || i == client)
            continue;
        
        if(!SMRPG_IsFFAEnabled() && GetClientTeam(i) == GetClientTeam(client))
            continue;
        
        // Check if this target was already hit
        bool alreadyHit = false;
        for(int j = 0; j < g_iChainCount[client]; j++)
        {
            if(g_iChainedTargets[client][j] == i)
            {
                alreadyHit = true;
                break;
            }
        }
        
        if(alreadyHit)
            continue;
        
        float targetPos[3];
        GetClientAbsOrigin(i, targetPos);
        
        float distance = GetVectorDistance(searchPos, targetPos);
        if(distance < closestDistance)
        {
            closestDistance = distance;
            target = i;
        }
    }
    
    return target;
}

/**
 * Start the chain lightning sequence
 */
void InitiateChainLightning(int attacker, int firstTarget)
{
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(attacker));
    pack.WriteCell(GetClientUserId(firstTarget));
    pack.WriteCell(-1);
    pack.WriteFloat(g_hCVInitialDamage.FloatValue);
    pack.WriteCell(0);
    
    CreateTimer(0.01, ChainLightning_Timer, pack);
}

/**
 * Chain lightning timer - handles each bounce
 */
public Action ChainLightning_Timer(Handle timer, DataPack pack)
{
    pack.Reset();
    int attacker = GetClientOfUserId(pack.ReadCell());
    int target = GetClientOfUserId(pack.ReadCell());
    int previousTarget = pack.ReadCell();
    float damage = pack.ReadFloat();
    int chainNum = pack.ReadCell();
    delete pack;
    
    if(!attacker || !target || !IsPlayerAlive(target))
        return Plugin_Stop;
    
    // Record this target as hit
    g_iChainedTargets[attacker][g_iChainCount[attacker]++] = target;
    
    // Deal damage to current target
    SDKHooks_TakeDamage(target, attacker, attacker, damage, DMG_SHOCK);
    
    // Create lightning visual effect
    float startPos[3], endPos[3];
    if(previousTarget == -1)
    {
        GetClientEyePosition(attacker, startPos);
    }
    else
    {
        int prevClient = GetClientOfUserId(previousTarget);
        if(prevClient && IsClientInGame(prevClient))
        {
            GetClientAbsOrigin(prevClient, startPos);
            startPos[2] += 50.0;
        }
        else
        {
            GetClientEyePosition(attacker, startPos);
        }
    }
    
    GetClientAbsOrigin(target, endPos);
    endPos[2] += 50.0;
    
    // Create the lightning beam
    int color[4] = {135, 206, 250, 255}; 
    TE_SetupBeamPoints(startPos, endPos, PrecacheModel("sprites/laser.vmt"), PrecacheModel("sprites/halo01.vmt"), 0, 1, 0.2, 3.0, 8.0, 1, 1.0, color, 10);
    TE_SendToAll();
    
    // Create spark effect at target
    TE_SetupSparks(endPos, NULL_VECTOR, 5, 3);
    TE_SendToAll();
    
    EmitAmbientSound("ambient/energy/zap1.wav", endPos, target, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.6);
    
    int level = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
    int maxChains = g_hCVMaxChains.IntValue + (level / 2);
    
    if(chainNum < maxChains)
    {
        // Find next target
        int nextTarget = FindNearestEnemy(attacker, target);
        if(nextTarget != -1)
        {
            float nextDamage = damage * g_hCVDamageDecay.FloatValue;
            DataPack nextPack = new DataPack();
            nextPack.WriteCell(GetClientUserId(attacker));
            nextPack.WriteCell(GetClientUserId(nextTarget));
            nextPack.WriteCell(GetClientUserId(target));
            nextPack.WriteFloat(nextDamage);
            nextPack.WriteCell(chainNum + 1);
            
            // Schedule next chain
            CreateTimer(g_hCVChainDelay.FloatValue, ChainLightning_Timer, nextPack);
        }
    }
    
    return Plugin_Stop;
}

/**
 * Timer callbacks
 */
public Action ChainLightningCooldown_Timer(Handle timer, any client)
{
    if(IsClientInGame(client))
    {
        g_hChainTimer[client] = null;
        // PrintToChat(client, "Chain Lightning is ready!");
    }
    return Plugin_Stop;
}

/**
 * Map start - precache sounds and models
 */
public void OnMapStart()
{
    PrecacheSound("ambient/energy/zap1.wav", true);
    PrecacheModel("sprites/laser.vmt", true);
    PrecacheModel("sprites/halo01.vmt", true);
}