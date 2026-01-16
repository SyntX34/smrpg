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

int g_iSpriteBeam;
int g_iSpriteHalo;
int g_iSpriteExplosion;

ArrayList g_hExplosionSounds;
int g_iClientTeam[MAXPLAYERS+1];
float g_fLastExplosionTime[MAXPLAYERS+1];

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
	
	g_hExplosionSounds = new ArrayList(PLATFORM_MAX_PATH);
	
	g_fLastExplosionTime[0] = 0.0;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			g_fLastExplosionTime[i] = 0.0;
			OnClientPutInServer(i);
		}
	}
}

public void OnPluginEnd()
{
	if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME))
		SMRPG_UnregisterUpgradeType(UPGRADE_SHORTNAME);
	
	delete g_hExplosionSounds;
}

public void OnAllPluginsLoaded()
{
	OnLibraryAdded("smrpg");
}

public void OnMapStart()
{
	char sExplosionSounds[][PLATFORM_MAX_PATH] = {
		"weapons/explode3.wav",
		"weapons/explode4.wav",
		"weapons/explode5.wav"
	};
	
	for(int i = 0; i < sizeof(sExplosionSounds); i++)
	{
		PrecacheSound(sExplosionSounds[i], true);
		g_hExplosionSounds.PushString(sExplosionSounds[i]);
		
		char sDownloadPath[PLATFORM_MAX_PATH];
		Format(sDownloadPath, sizeof(sDownloadPath), "sound/%s", sExplosionSounds[i]);
		if(FileExists(sDownloadPath))
			AddFileToDownloadsTable(sDownloadPath);
	}
	
	#if defined _smrpg_sharedmaterials_included
	g_iSpriteBeam = SMRPG_GC_PrecacheModel("SpriteBeam");
	g_iSpriteHalo = SMRPG_GC_PrecacheModel("SpriteHalo");
	g_iSpriteExplosion = SMRPG_GC_PrecacheModel("SpriteExplosion");
	#else
	g_iSpriteBeam = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iSpriteHalo = PrecacheModel("materials/sprites/halo01.vmt");
	g_iSpriteExplosion = PrecacheModel("sprites/zerogxplode.spr");
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
	g_fLastExplosionTime[client] = 0.0;
}

public void OnClientDisconnect(int client)
{
	g_iClientTeam[client] = 0;
	g_fLastExplosionTime[client] = 0.0;
}

public void OnGameFrame()
{
	static int iFrameCount;
	if(++iFrameCount % 64 == 0)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && IsPlayerAlive(i))
				g_iClientTeam[i] = GetClientTeam(i);
			else
				g_iClientTeam[i] = 0;
		}
	}
}

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

public void Hook_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3])
{
	if(attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || 
	   victim <= 0 || victim > MaxClients || !IsPlayerAlive(victim))
		return;
	
	if(!SMRPG_IsEnabled() || !SMRPG_IsUpgradeEnabled(UPGRADE_SHORTNAME))
		return;
	
	if(IsFakeClient(attacker) && SMRPG_IgnoreBots())
		return;
	
	if(!SMRPG_IsFFAEnabled() && g_iClientTeam[attacker] == g_iClientTeam[victim])
		return;
	
	int iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return;
	
	int iWeapon = weapon;
	if(iWeapon <= 0 || !IsValidEntity(iWeapon))
	{
		iWeapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
		if(iWeapon <= 0)
			return;
	}
	
	if(!IsShotgunWeapon(iWeapon))
		return;
	
	float currentTime = GetGameTime();
	if(currentTime - g_fLastExplosionTime[attacker] < 0.5)
		return;
	
	float fExplosionChance = float(iLevel) * g_hCVExplosionChance.FloatValue;
	if(GetRandomFloat(0.0, 1.0) > fExplosionChance)
		return;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
		return;
	
	g_fLastExplosionTime[attacker] = currentTime;
	
	float victimPos[3];
	GetClientAbsOrigin(victim, victimPos);
	victimPos[2] += 30.0;
	
	CreateExplosionEffect(victim, attacker, iLevel, victimPos);
}

void CreateExplosionEffect(int victim, int attacker, int level, const float impactPosition[3])
{
	if(victim <= 0 || !IsClientInGame(victim) || !IsPlayerAlive(victim) ||
	   attacker <= 0 || !IsClientInGame(attacker))
		return;
	
	char soundPath[PLATFORM_MAX_PATH];
	int soundCount = g_hExplosionSounds.Length;
	if(soundCount > 0)
	{
		g_hExplosionSounds.GetString(GetRandomInt(0, soundCount - 1), soundPath, sizeof(soundPath));
		EmitSoundToAll(soundPath, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, impactPosition);
	}
	
	CreateVisualEffects(impactPosition, level);
	
	ApplyExplosionDamage(attacker, victim, level, impactPosition);
}

void CreateVisualEffects(const float pos[3], int level)
{
	if(g_iSpriteBeam <= 0 || g_iSpriteHalo <= 0)
		return;
	
	int color[4] = {255, 100, 0, 200};
	TE_SetupBeamRingPoint(pos, 10.0, g_hCVExplosionRadius.FloatValue * 0.8, g_iSpriteBeam, g_iSpriteHalo, 
		0, 10, 0.3, 5.0, 0.0, color, 5, 0);
	TE_SendToAll();
	
	if(level >= 5)
	{
		TE_SetupExplosion(pos, g_iSpriteExplosion, 3.0, 1, 0, 100, 0);
		TE_SendToAll();
	}
}

void ApplyExplosionDamage(int attacker, int victim, int level, const float impactPosition[3])
{
	float explosionRadius = g_hCVExplosionRadius.FloatValue;
	float explosionDamage = g_hCVExplosionDamage.FloatValue * float(level) / 10.0;
	float explosionRadiusSquared = explosionRadius * explosionRadius;
	
	float victimPos[3];
	GetClientAbsOrigin(victim, victimPos);
	
	float distanceSquared = GetVectorDistanceSquared(impactPosition, victimPos);
	if(distanceSquared <= explosionRadiusSquared)
	{
		float distance = SquareRoot(distanceSquared);
		float scaledDamage = explosionDamage * (1.0 - (distance / explosionRadius));
		
		if(scaledDamage > 0.0)
		{
			SDKHooks_TakeDamage(victim, attacker, attacker, scaledDamage, DMG_BLAST);
			
			float pushForce[3];
			MakeVectorFromPoints(impactPosition, victimPos, pushForce);
			NormalizeVector(pushForce, pushForce);
			ScaleVector(pushForce, 400.0 * (1.0 - (distance / explosionRadius)));
			pushForce[2] = 150.0;
			
			TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, pushForce);
		}
	}
	
	float radiusSquared = explosionRadius * explosionRadius;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !IsPlayerAlive(i) || i == victim || i == attacker)
			continue;
		
		if(!SMRPG_IsFFAEnabled() && g_iClientTeam[i] == g_iClientTeam[attacker])
			continue;
		
		float targetPos[3];
		GetClientAbsOrigin(i, targetPos);
		
		float distSquared = GetVectorDistanceSquared(impactPosition, targetPos);
		if(distSquared <= radiusSquared)
		{
			float distance = SquareRoot(distSquared);
			float scaledDamage = explosionDamage * 0.5 * (1.0 - (distance / explosionRadius));
			
			if(scaledDamage > 0.0)
			{
				SDKHooks_TakeDamage(i, attacker, attacker, scaledDamage, DMG_BLAST);
			}
		}
	}
}

bool IsShotgunWeapon(int weapon)
{
	if(weapon <= 0 || !IsValidEntity(weapon))
		return false;
	
	static char sWeapon[32];
	GetEntityClassname(weapon, sWeapon, sizeof(sWeapon));
	
	return (sWeapon[7] == 'm' && sWeapon[8] == '3') ||
		   (sWeapon[7] == 'x' && sWeapon[8] == 'm') ||
		   (sWeapon[7] == 'n' && sWeapon[8] == 'o') ||
		   (sWeapon[7] == 'm' && sWeapon[8] == 'a' && sWeapon[9] == 'g');
}

float GetVectorDistanceSquared(const float vec1[3], const float vec2[3])
{
	float result = 0.0;
	result += (vec1[0] - vec2[0]) * (vec1[0] - vec2[0]);
	result += (vec1[1] - vec2[1]) * (vec1[1] - vec2[1]);
	result += (vec1[2] - vec2[2]) * (vec1[2] - vec2[2]);
	return result;
}