#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "explodeshotgun"

ConVar g_hCVExplosionChance;
ConVar g_hCVExplosionRadius;
ConVar g_hCVExplosionDamage;

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
	
	CreateExplosionEffect(victim, attacker, iLevel, damagePosition);
}

/**
 * Create explosion effect
 */
void CreateExplosionEffect(int victim, int attacker, int level, const float impactPosition[3])
{
	EmitAmbientSound("weapons/explode3.wav", impactPosition, SOUND_FROM_WORLD, SNDLEVEL_GUNFIRE);
	
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
			
			SMRPG_IgniteClient(i, 2.0, UPGRADE_SHORTNAME, true, attacker);
		}
	}
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