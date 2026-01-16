#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "elementalmastery"
#define ICE_SLOW_DURATION 3.0
#define EARTH_STUN_DURATION 1.5
#define FIRE_DURATION 5.0
#define FIRE_DAMAGE_INTERVAL 1.0

enum ElementType
{
    ELEMENT_FIRE,
    ELEMENT_ICE,
    ELEMENT_LIGHTNING,
    ELEMENT_EARTH
}

int g_iClientFlags[MAXPLAYERS+1];
#define CLIENT_HAS_UPGRADE (1 << 0)
#define CLIENT_ELEMENT_ACTIVE (1 << 1)
#define CLIENT_IN_COOLDOWN (1 << 2)

ElementType g_iCurrentElement[MAXPLAYERS+1];
ConVar g_hCVCooldown;
ConVar g_hCVDamageMultiplier;
ConVar g_hCVElementSwitchTime;

Handle g_hElementTimer[MAXPLAYERS+1];
Handle g_hAutoSwitchTimer[MAXPLAYERS+1];
float g_fFireDamageEndTime[MAXPLAYERS+1];
int g_iFireAttacker[MAXPLAYERS+1];

bool g_bUpgradeLoaded = false;

public Plugin myinfo = 
{
    name = "SM:RPG Upgrade > Elemental Mastery",
    author = "+SyntX",
    description = "Master different elemental powers to enhance your attacks.",
    version = SMRPG_VERSION,
    url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
    LoadTranslations("smrpg_stock_upgrades.phrases");
    
    // Hook player death for cleanup
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_spawn", Event_PlayerSpawn);
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            OnClientPutInServer(i);
        }
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
        SMRPG_RegisterUpgradeType("Elemental Mastery", UPGRADE_SHORTNAME, "Master different elemental powers to enhance your attacks.", 10, true, 10, 20, 15);
        SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
        SMRPG_SetUpgradeBuySellCallback(UPGRADE_SHORTNAME, SMRPG_BuySell);
        
        g_hCVCooldown = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_elementalmastery_cooldown", "30.0", "Cooldown time in seconds between element switches", 0, true, 1.0);
        g_hCVDamageMultiplier = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_elementalmastery_damage", "1.5", "Damage multiplier for elemental attacks", 0, true, 1.0);
        g_hCVElementSwitchTime = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_elementalmastery_switchtime", "5.0", "Time between automatic element switches", 0, true, 1.0);
        
        g_bUpgradeLoaded = true;
        
        // Initialize existing clients
        for(int i = 1; i <= MaxClients; i++)
        {
            if(IsClientInGame(i) && SMRPG_GetClientUpgradeLevel(i, UPGRADE_SHORTNAME) > 0)
            {
                g_iClientFlags[i] |= CLIENT_HAS_UPGRADE;
                StartAutoElementSwitch(i);
                g_iClientFlags[i] |= CLIENT_ELEMENT_ACTIVE;
            }
        }
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if(StrEqual(name, "smrpg"))
    {
        g_bUpgradeLoaded = false;
        
        // Clear all flags
        for(int i = 1; i <= MaxClients; i++)
        {
            g_iClientFlags[i] = 0;
        }
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    
    // Reset all values
    g_iClientFlags[client] = 0;
    g_iCurrentElement[client] = ELEMENT_FIRE;
    g_hElementTimer[client] = null;
    g_hAutoSwitchTimer[client] = null;
    g_fFireDamageEndTime[client] = 0.0;
    g_iFireAttacker[client] = 0;
}

public void OnClientDisconnect(int client)
{
    ClearClientTimers(client);
    g_iClientFlags[client] = 0;
    g_fFireDamageEndTime[client] = 0.0;
    g_iFireAttacker[client] = 0;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    // Clear all effects on dead player
    if(client > 0)
    {
        // Reset movement speed if slowed
        if(GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue") < 1.0)
        {
            SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
        }
        
        // Reset move type if stunned
        if(GetEntityMoveType(client) == MOVETYPE_NONE)
        {
            SetEntityMoveType(client, MOVETYPE_WALK);
        }
        
        // Stop fire damage
        g_fFireDamageEndTime[client] = 0.0;
    }
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    // Reset player state on spawn
    if(client > 0)
    {
        SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
        SetEntityMoveType(client, MOVETYPE_WALK);
        g_fFireDamageEndTime[client] = 0.0;
    }
}

void ClearClientTimers(int client)
{
    if(g_hElementTimer[client] != null)
    {
        KillTimer(g_hElementTimer[client]);
        g_hElementTimer[client] = null;
    }
    
    if(g_hAutoSwitchTimer[client] != null)
    {
        KillTimer(g_hAutoSwitchTimer[client]);
        g_hAutoSwitchTimer[client] = null;
    }
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
    if(type == UpgradeQueryType_Buy)
    {
        // Player bought the upgrade, start auto-switching
        if(!(g_iClientFlags[client] & CLIENT_ELEMENT_ACTIVE))
        {
            g_iClientFlags[client] |= CLIENT_HAS_UPGRADE;
            StartAutoElementSwitch(client);
            g_iClientFlags[client] |= CLIENT_ELEMENT_ACTIVE;
        }
    }
    else if(type == UpgradeQueryType_Sell)
    {
        // Player sold the upgrade, stop all effects
        ClearClientTimers(client);
        g_iClientFlags[client] &= ~(CLIENT_HAS_UPGRADE | CLIENT_ELEMENT_ACTIVE | CLIENT_IN_COOLDOWN);
    }
}

/**
 * Hook for damage dealt - FIXED: Only apply to opponents
 */
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    // CRITICAL FIX: Only apply effects when attacker damages an opponent
    if(attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
    {
        // Check if victim is an opponent (different team or valid target)
        if(victim > 0 && victim <= MaxClients && IsClientInGame(victim))
        {
            // Check if they're on the same team - if so, DON'T apply effects
            if(GetClientTeam(attacker) == GetClientTeam(victim))
                return Plugin_Continue;
            
            // Also check if victim is actually damaged (damage > 0)
            if(damage <= 0)
                return Plugin_Continue;
        }
        else
        {
            // Victim is not a valid player, don't apply effects
            return Plugin_Continue;
        }
        
        // Now check for upgrade
        if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME) && (g_iClientFlags[attacker] & CLIENT_HAS_UPGRADE))
        {
            if(SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME) && SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
            {
                // Apply elemental damage multiplier
                float damageMultiplier = g_hCVDamageMultiplier != null ? g_hCVDamageMultiplier.FloatValue : 1.5;
                damage *= damageMultiplier;
                
                // Apply elemental effect based on current element
                ApplyElementalEffect(victim, attacker, g_iCurrentElement[attacker]);
                
                return Plugin_Changed;
            }
        }
    }
    
    return Plugin_Continue;
}

/**
 * Apply elemental effect based on element type
 */
void ApplyElementalEffect(int victim, int attacker, ElementType element)
{
    // Make sure victim is alive and valid
    if(victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || !IsPlayerAlive(victim))
        return;
    
    // Make sure attacker is valid
    if(attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker))
        return;
    
    // Don't apply effects to teammates
    if(GetClientTeam(attacker) == GetClientTeam(victim))
        return;
    
    switch(element)
    {
        case ELEMENT_FIRE:
        {
            // Fire effect - damage over time for 5 seconds
            // Use a single global timer instead of per-victim timers
            g_fFireDamageEndTime[victim] = GetGameTime() + FIRE_DURATION;
            g_iFireAttacker[victim] = attacker;
            
            // Start fire damage processing
            CreateTimer(FIRE_DAMAGE_INTERVAL, ProcessFireDamage, GetClientUserId(victim), TIMER_FLAG_NO_MAPCHANGE);
        }
        case ELEMENT_ICE:
        {
            // Slow effect - FIXED: No timers, just set and forget with duration check
            float currentSpeed = GetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue");
            
            // Only apply if not already slowed more than this
            if(currentSpeed > 0.5)
            {
                SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 0.5);
                
                // Create timer to reset movement speed
                CreateTimer(ICE_SLOW_DURATION, ResetMovementSpeed, GetClientUserId(victim));
            }
        }
        case ELEMENT_LIGHTNING:
        {
            // Shock effect - instant extra damage (no lasting effects)
            float extraDamage = 10.0;
            SDKHooks_TakeDamage(victim, attacker, attacker, extraDamage, DMG_SHOCK);
        }
        case ELEMENT_EARTH:
        {
            // Stun effect
            MoveType currentMoveType = GetEntityMoveType(victim);
            
            // Only stun if not already stunned and not in a special movetype
            if(currentMoveType == MOVETYPE_WALK)
            {
                SetEntityMoveType(victim, MOVETYPE_NONE);
                
                // Create timer to reset movement
                CreateTimer(EARTH_STUN_DURATION, ResetMovementType, GetClientUserId(victim));
            }
        }
    }
}

/**
 * Process fire damage
 * Single timer per victim
 */
public Action ProcessFireDamage(Handle timer, int userid)
{
    int victim = GetClientOfUserId(userid);
    
    if(victim > 0 && IsClientInGame(victim) && IsPlayerAlive(victim))
    {
        // Check if fire damage should still continue
        if(GetGameTime() < g_fFireDamageEndTime[victim])
        {
            int attacker = g_iFireAttacker[victim];
            
            // Make sure attacker is still valid
            if(attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
            {
                // Deal damage over time
                SDKHooks_TakeDamage(victim, attacker, attacker, 5.0, DMG_BURN);
                
                // Create next fire damage tick
                CreateTimer(FIRE_DAMAGE_INTERVAL, ProcessFireDamage, userid, TIMER_FLAG_NO_MAPCHANGE);
                return Plugin_Stop;
            }
        }
        
        // Fire ended or attacker invalid
        g_fFireDamageEndTime[victim] = 0.0;
        g_iFireAttacker[victim] = 0;
    }
    
    return Plugin_Stop;
}

/**
 * Switch to next element
 */
void SwitchToNextElement(int client)
{
    g_iCurrentElement[client] = view_as<ElementType>((g_iCurrentElement[client] + 1) % 4);
    
    // Optional: Print element switch message
    /*
    char elementName[32];
    switch(g_iCurrentElement[client])
    {
        case ELEMENT_FIRE: elementName = "Fire";
        case ELEMENT_ICE: elementName = "Ice";
        case ELEMENT_LIGHTNING: elementName = "Lightning";
        case ELEMENT_EARTH: elementName = "Earth";
    }
    PrintToChat(client, "Element switched to %s!", elementName);
    */
}

/**
 * Manual element switching function
 */
public Action Command_SwitchElement(int client, int args)
{
    if(!g_bUpgradeLoaded)
        return Plugin_Handled;
        
    if(g_iClientFlags[client] & CLIENT_IN_COOLDOWN)
    {
        // PrintToChat(client, "Element switch is on cooldown!");
        return Plugin_Handled;
    }
    
    if(!IsPlayerAlive(client))
    {
        // PrintToChat(client, "You must be alive to switch elements!");
        return Plugin_Handled;
    }
    
    if(!(g_iClientFlags[client] & CLIENT_HAS_UPGRADE))
    {
        // PrintToChat(client, "You don't have the Elemental Mastery upgrade!");
        return Plugin_Handled;
    }
    
    if(!SMRPG_RunUpgradeEffect(client, UPGRADE_SHORTNAME))
        return Plugin_Handled;
    
    // Start auto element switching if not already active
    if(!(g_iClientFlags[client] & CLIENT_ELEMENT_ACTIVE))
    {
        StartAutoElementSwitch(client);
        g_iClientFlags[client] |= CLIENT_ELEMENT_ACTIVE;
    }
    
    // Switch to next element
    SwitchToNextElement(client);
    
    // Set cooldown for manual switch
    float cooldown = g_hCVCooldown != null ? g_hCVCooldown.FloatValue : 30.0;
    g_iClientFlags[client] |= CLIENT_IN_COOLDOWN;
    
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    g_hElementTimer[client] = CreateTimer(cooldown, ElementCooldown_Timer, pack);
    
    return Plugin_Handled;
}

void StartAutoElementSwitch(int client)
{
    // Clear any existing auto switch timer
    if(g_hAutoSwitchTimer[client] != null)
    {
        KillTimer(g_hAutoSwitchTimer[client]);
        g_hAutoSwitchTimer[client] = null;
    }
    
    // Start new auto switch timer
    float switchTime = g_hCVElementSwitchTime != null ? g_hCVElementSwitchTime.FloatValue : 5.0;
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    g_hAutoSwitchTimer[client] = CreateTimer(switchTime, AutoSwitchElement_Timer, pack, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Timer callbacks
 */
public Action AutoSwitchElement_Timer(Handle timer, DataPack pack)
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    
    if(client > 0 && IsClientInGame(client) && IsPlayerAlive(client) && (g_iClientFlags[client] & CLIENT_HAS_UPGRADE))
    {
        // Automatically switch elements
        SwitchToNextElement(client);
        return Plugin_Continue;
    }
    
    // Client disconnected or no longer has upgrade
    delete pack;
    g_hAutoSwitchTimer[client] = null;
    return Plugin_Stop;
}

public Action ResetMovementSpeed(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    
    if(client > 0 && IsClientInGame(client))
    {
        if(IsPlayerAlive(client))
        {
            // Reset to normal speed
            SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
        }
    }
    return Plugin_Stop;
}

public Action ResetMovementType(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    
    if(client > 0 && IsClientInGame(client))
    {
        if(IsPlayerAlive(client))
        {
            // Reset to normal movement (walk)
            SetEntityMoveType(client, MOVETYPE_WALK);
        }
    }
    return Plugin_Stop;
}

public Action ElementCooldown_Timer(Handle timer, DataPack pack)
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    delete pack;
    
    if(client > 0 && IsClientInGame(client))
    {
        g_hElementTimer[client] = null;
        g_iClientFlags[client] &= ~CLIENT_IN_COOLDOWN;
        // PrintToChat(client, "Element switch is ready!");
    }
    return Plugin_Stop;
}

/**
 * Frame-based processing for fire damage (more efficient than timers)
 */
public void OnGameFrame()
{
    static float lastFireProcessTime = 0.0;
    float currentTime = GetGameTime();
    
    // Process fire damage every 0.1 seconds instead of every frame
    if(currentTime - lastFireProcessTime < 0.1)
        return;
    
    lastFireProcessTime = currentTime;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && IsPlayerAlive(i) && g_fFireDamageEndTime[i] > 0.0)
        {
            // Check if fire damage should still continue
            if(currentTime < g_fFireDamageEndTime[i])
            {
                int attacker = g_iFireAttacker[i];
                
                // Make sure attacker is still valid
                if(attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
                {
                    // Check if it's time for damage tick (every 1 second)
                    if(g_fFireDamageEndTime[i] - currentTime <= FIRE_DURATION - FIRE_DAMAGE_INTERVAL)
                    {
                        SDKHooks_TakeDamage(i, attacker, attacker, 5.0, DMG_BURN);
                    }
                }
                else
                {
                    // Attacker invalid, stop fire
                    g_fFireDamageEndTime[i] = 0.0;
                    g_iFireAttacker[i] = 0;
                }
            }
            else
            {
                // Fire duration ended
                g_fFireDamageEndTime[i] = 0.0;
                g_iFireAttacker[i] = 0;
            }
        }
    }
}