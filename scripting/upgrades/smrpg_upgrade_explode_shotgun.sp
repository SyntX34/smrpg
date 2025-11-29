#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>
#if defined _smrpg_sharedmaterials_included
#include <smrpg_sharedmaterials>
#endif

#define UPGRADE_SHORTNAME "explodeshotgun"

ConVar g_hCVExplosionChance;
ConVar g_hCVExplosionRadius;
ConVar g_hCVExplosionDamage;

// Visual effect models
int g_iSpriteBeam;
int g_iSpriteHalo;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Explode Shotgun",
	author = "+SyntX",
	description = "Exploding bullets for shotguns based on SM:RPG upgrade level.",
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

public void OnMapStart()
{
	AddFileToDownloadsTable("materials/effects/fire_cloud1b.vmt");
	AddFileToDownloadsTable("materials/effects/fire_cloud2b.vmt");
	AddFileToDownloadsTable("materials/effects/fire_embers1b.vmt");
	AddFileToDownloadsTable("materials/effects/fire_embers2b.vmt");
	AddFileToDownloadsTable("materials/effects/fire_embers3b.vmt");
	AddFileToDownloadsTable("materials/effects/fire_cloud1b.vtf");
	AddFileToDownloadsTable("materials/effects/fire_cloud2b.vtf");
	AddFileToDownloadsTable("materials/effects/fire_embers1b.vtf");
	AddFileToDownloadsTable("materials/effects/fire_embers2b.vtf");
	AddFileToDownloadsTable("materials/effects/fire_embers3b.vtf");
	
	#if defined _smrpg_sharedmaterials_included
	g_iSpriteBeam = SMRPG_GC_PrecacheModel("SpriteBeam");
	g_iSpriteHalo = SMRPG_GC_PrecacheModel("SpriteHalo");
	#else
	g_iSpriteBeam = PrecacheModel("materials/sprites/bomb_planted_ring.vmt");
	g_iSpriteHalo = PrecacheModel("materials/sprites/halo.vtf");
	#endif
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "smrpg"))
	{
		SMRPG_RegisterUpgradeType("Explode Shotgun", UPGRADE_SHORTNAME, "Chance to create explosive bullets when shooting with a shotgun.", 0, true, 10, 20, 15);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		g_hCVExplosionChance = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_explodeshotgun_chance", "0.1", "Chance for bullets to explode (multiplied by level)", 0, true, 0.0, true, 1.0);
		g_hCVExplosionRadius = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_explodeshotgun_radius", "200.0", "Explosion radius", 0, true, 50.0);
		g_hCVExplosionDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_explodeshotgun_damage", "15.0", "Base explosion damage", 0, true, 0.0);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost);
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

/**
 * Hook callbacks
 */
public void Hook_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || victim <= 0 || victim > MaxClients || !IsPlayerAlive(victim))
		return;
	
	if(!SMRPG_IsEnabled())
		return;
	
	if(!SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME))
		return;
	
	if(IsFakeClient(attacker) && SMRPG_IgnoreBots())
		return;
	
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	
	int iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	int iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = GetEntPropEnt(inflictor, Prop_Send, "m_hActiveWeapon");
	
	if(iWeapon == -1)
		return;
	
	if(iWeapon != GetPlayerWeaponSlot(attacker, 0))
		return;
	
	if(!IsShotgunWeapon(iWeapon))
		return;
	
	float fExplosionChance = float(iLevel) * g_hCVExplosionChance.FloatValue;

	if(GetRandomFloat(0.0, 1.0) > fExplosionChance)
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
		return; 
	
	float victimPos[3];
	GetClientAbsOrigin(victim, victimPos);
	victimPos[2] += 30.0;
	
	CreateExplosionEffect(victim, attacker, iLevel, victimPos);
}

/**
 * Emit sound to nearby players only
 */
void EmitSoundToNearbyPlayers(const float origin[3], const char[] sample, float radius)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i))
            continue;
        
        float clientPos[3];
        GetClientAbsOrigin(i, clientPos);
        
        float distance = GetVectorDistance(origin, clientPos);
        if (distance <= radius)
        {
            EmitSoundToClient(i, sample, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL);
        }
    }
}

/**
 * Create explosion effect
 */
void CreateExplosionEffect(int victim, int attacker, int level, const float impactPosition[3])
{
    EmitSoundToNearbyPlayers(impactPosition, "weapons/explode3.wav", 800.0);
    CreateVisualEffects(impactPosition);
    CreateGroundBeacon(impactPosition);
    
    float explosionRadius = g_hCVExplosionRadius.FloatValue;
    float explosionDamage = g_hCVExplosionDamage.FloatValue * float(level) / 10.0;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientInGame(i) || !IsPlayerAlive(i) || i == attacker)
            continue;
        
        if(!SMRPG_IsFFAEnabled() && GetClientTeam(i) == GetClientTeam(attacker))
            continue;
        
        float targetPos[3];
        GetClientAbsOrigin(i, targetPos);
        
        float distance = GetVectorDistance(impactPosition, targetPos);
        if(distance <= explosionRadius)
        {
            float scaledDamage = explosionDamage * (1.0 - (distance / explosionRadius));
            
            SDKHooks_TakeDamage(i, attacker, attacker, scaledDamage, DMG_BLAST);
            
            float pushForce[3];
            MakeVectorFromPoints(impactPosition, targetPos, pushForce);
            NormalizeVector(pushForce, pushForce);
            ScaleVector(pushForce, 500.0 * (1.0 - (distance / explosionRadius)));
            pushForce[2] = 200.0;
            
            TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, pushForce);
        }
    }
}

/**
 * Create visual effects around the explosion point
 */
void CreateVisualEffects(const float pos[3])
{
	// Create beam ring effect instead of glow sprites
	if (g_iSpriteBeam > 0)
	{
		int color[4] = {255, 100, 0, 255};
		TE_SetupBeamRingPoint(pos, 0.0, 100.0, g_iSpriteBeam, g_iSpriteHalo, 0, 15, 0.5, 10.0, 0.0, color, 10, 0);
		TE_SendToAll();
	}
	
	// Create explosion particles
	if (g_iSpriteHalo > 0)
	{
		TE_SetupExplosion(pos, g_iSpriteHalo, 5.0, 1, 0, 100, 0);
		TE_SendToAll();
	}
}

/**
 * Create a beacon effect on the ground
 */
void CreateGroundBeacon(const float pos[3])
{
	float groundPos[3];
	groundPos[0] = pos[0];
	groundPos[1] = pos[1];
	groundPos[2] = pos[2] - 30.0;
	
	char sBuffer[64];
	int iEnt = CreateEntityByName("light_dynamic");
	if(iEnt != INVALID_ENT_REFERENCE)
	{
		Format(sBuffer, sizeof(sBuffer), "explode_beacon_%f_%f", groundPos[0], groundPos[1]);
		DispatchKeyValue(iEnt,"targetname", sBuffer);
		Format(sBuffer, sizeof(sBuffer), "%f %f %f", groundPos[0], groundPos[1], groundPos[2]);
		DispatchKeyValue(iEnt, "origin", sBuffer);
		DispatchKeyValue(iEnt, "angles", "-90 0 0");
		DispatchKeyValue(iEnt, "_light", "255 100 0 200");
		DispatchKeyValue(iEnt, "pitch","-90");
		DispatchKeyValue(iEnt, "distance","256");
		DispatchKeyValue(iEnt, "spotlight_radius","128");
		DispatchKeyValue(iEnt, "brightness","4");
		DispatchKeyValue(iEnt, "style","6");
		DispatchKeyValue(iEnt, "spawnflags","1");
		DispatchSpawn(iEnt);
		AcceptEntityInput(iEnt, "DisableShadow");
		
		char sAddOutput[64];
		Format(sAddOutput, sizeof(sAddOutput), "OnUser1 !self:kill::3.0:1");
		SetVariantString(sAddOutput);
		AcceptEntityInput(iEnt, "AddOutput");
		AcceptEntityInput(iEnt, "FireUser1");
	}
	
	int color[4] = {255, 100, 0, 255};
	TE_SetupBeamRingPoint(groundPos, 0.0, 200.0, g_iSpriteBeam, g_iSpriteHalo, 0, 10, 3.0, 5.0, 0.0, color, 10, 0);
	TE_SendToAll();
}

/**
 * Helper functions
 */
bool IsShotgunWeapon(int weapon)
{
	if(weapon <= 0 || !IsValidEntity(weapon))
		return false;
	
	char sWeapon[64];
	GetEntityClassname(weapon, sWeapon, sizeof(sWeapon));
	
	if(StrContains(sWeapon, "weapon_m3") != -1 ||
	   StrContains(sWeapon, "weapon_xm1014") != -1 ||
	   StrContains(sWeapon, "weapon_nova") != -1 ||
	   StrContains(sWeapon, "weapon_mag7") != -1)
	{
		return true;
	}
	
	return false;
}