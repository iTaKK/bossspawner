/*	
 *	============================================================================
 *	
 *	[TF2] Custom Boss Spawner
 *	Alliedmodders: http://forums.alliedmods.net/member.php?u=87026
 *	Current Version: 4.1
 *
 *	This plugin is FREE and can be distributed to anyone.  
 *	If you have paid for this plugin, get your money back.
 *	
 *	Version Log:
 *	v.4.1
 *	- Fixed translations files typo
 *	- Added boss spawn notification
 *	- Little fix on reload boss config command
 *	- Fixed HUD display conflicting with other plugins
 *	- Added boss custom spawn location: "position" key
 *	- Added ability to change HUD location
 *	============================================================================
 */

#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <morecolors>

#define PLUGIN_VERSION "4.1"

new Handle:cVars[6] = 	{INVALID_HANDLE, ...};
new Handle:cTimer = 	INVALID_HANDLE;
new Handle:bTimer = 	INVALID_HANDLE;
new Handle:hHUD = 		INVALID_HANDLE;

new const String:BossAttributes[64][11][124];
//0 - Name
//1 - Model
//2 - Type
//3 - HP base
//4 - HP Scale
//5 - WeaponModel
//6 - Size
//7 - Glow
//8 - PosFix
//9 - Lifeline

new sMode;
new Float:sInterval;
new Float:sMin;
new Float:sHUDx;
new Float:sHUDy;

new index_boss = 0;
new bool:g_Enabled;
new bossEnt = -1;
new Float:g_pos[3];
new Float:k_pos[3];
new bossCounter;
new g_trackent = -1;
new g_healthBar = -1;
new max_boss;
new bool:ActiveTimer;
new SpawnEnt;
new bool:queueBoss;
new index_command;
new bool:s_rand;

public Plugin:myinfo =  {
	name = "[TF2] Custom Boss Spawner",
	author = "Tak (chaosxk)",
	description = "Spawns a custom boss with or without a timer.",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net"
}

public OnPluginStart() {
	cVars[0] = CreateConVar("sm_boss_version", PLUGIN_VERSION, "Halloween Boss Spawner Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	cVars[1] = CreateConVar("sm_boss_mode", "1", "What spawn mode should boss spawn? (0 - Random ; 1 - Ordered from HHH - Monoculus - Merasmus");
	cVars[2] = CreateConVar("sm_boss_interval", "300", "How many seconds until the next boss spawns?");
	cVars[3] = CreateConVar("sm_boss_minplayers", "12", "How many players are needed before enabling auto-spawning?");
	cVars[4] = CreateConVar("sm_boss_hud_x", "0.05", "X-Coordinate of the HUD display.");
	cVars[5] = CreateConVar("sm_boss_hud_y", "0.05", "Y-Coordinate of the HUD display");

	RegAdminCmd("sm_getcoords", GetCoords, ADMFLAG_GENERIC, "Get the Coordinates of your cursor.");
	RegAdminCmd("sm_forceboss", ForceSpawn, ADMFLAG_GENERIC, "Forces a boss to spawn");
	RegAdminCmd("sm_slayboss", SlayBoss, ADMFLAG_GENERIC, "Forces a boss to die");
	RegAdminCmd("sm_reloadbossconfig", ReloadConfig, ADMFLAG_GENERIC, "Reloads the map setting config");
	RegAdminCmd("sm_spawn", SpawnBossCommand, ADMFLAG_GENERIC, "Spawns a boss at the position the user is looking at.");

	HookEvent("teamplay_round_start", RoundStart);
	HookEvent("pumpkin_lord_summoned", Horse_Summoned, EventHookMode_Pre);
	HookEvent("pumpkin_lord_killed", Horse_Killed, EventHookMode_Pre);
	HookEvent("merasmus_summoned", Merasmus_Summoned, EventHookMode_Pre);
	HookEvent("merasmus_killed", Merasmus_Killed, EventHookMode_Pre);
	HookEvent("eyeball_boss_summoned", Monoculus_Summoned, EventHookMode_Pre);
	HookEvent("eyeball_boss_killed", Monoculus_Killed, EventHookMode_Pre);
	HookEvent("merasmus_escape_warning", Merasmus_Leave, EventHookMode_Pre);
	HookEvent("eyeball_boss_escape_imminent", Monoculus_Leave, EventHookMode_Pre);

	HookConVarChange(cVars[0], cVarChange);
	HookConVarChange(cVars[1], cVarChange);
	HookConVarChange(cVars[2], cVarChange);
	HookConVarChange(cVars[3], cVarChange);
	HookConVarChange(cVars[4], cVarChange);
	HookConVarChange(cVars[5], cVarChange);
	
	LoadTranslations("common.phrases");
	LoadTranslations("bossspawner.phrases");
	AutoExecConfig(true, "bossspawner");
}

public OnPluginEnd() {
	RemoveExistingBoss();
	ClearTimer(cTimer);
}

public OnConfigsExecuted() {
	sMode = GetConVarInt(cVars[1]);
	sInterval = GetConVarFloat(cVars[2]);
	sMin = GetConVarFloat(cVars[3]);
	sHUDx = GetConVarFloat(cVars[4]);
	sHUDy = GetConVarFloat(cVars[5]);
	SetupMapConfigs("bossspawner_maps.cfg");
	if(g_Enabled) {
		SetupBossConfigs("bossspawner_boss.cfg");
		FindHealthBar();
		PrecacheSound("ui/halloween_boss_summoned_fx.wav");
	}
}

public RemoveBossLifeline(const String:command[], const String:execute[], duration) {
	new flags = GetCommandFlags(command); 
	SetCommandFlags(command, flags & ~FCVAR_CHEAT); 
	ServerCommand("%s %i", execute, duration);
	//SetCommandFlags(command, flags|FCVAR_CHEAT); 
}

public OnMapEnd() {
	RemoveExistingBoss();
	ClearTimer(cTimer);
}

public OnClientPostAdminCheck(client) {
	if(GetClientCount(true) == sMin) {
		if(bossCounter == 0) {
			ResetTimer();
		}
	}
}

public OnClientDisconnect(client) {
	if(GetClientCount(true) < sMin) {
		RemoveExistingBoss();
		ClearTimer(cTimer);
	}
}

public cVarChange(Handle:convar, String:oldValue[], String:newValue[]) {
	if (StrEqual(oldValue, newValue, true))
		return;
	
	new Float:iNewValue = StringToFloat(newValue);

	if(convar == cVars[0])  {
		SetConVarString(cVars[0], PLUGIN_VERSION);
	}
	else if(convar == cVars[1]) {
		sMode = RoundFloat(iNewValue);
	}
	else if((convar == cVars[2]) || (convar == cVars[3])) {
		if(convar == cVars[2]) sInterval = iNewValue;
		else sMin = iNewValue;
		
		if(GetClientCount(true) >= sMin) {
			if(bossCounter == 0) {
				ResetTimer();
			}
		}
		else {
			RemoveExistingBoss();
			ClearTimer(cTimer);
		}
	}
	else if(convar == cVars[4]) {
		sHUDx = iNewValue;
	}
	else if(convar == cVars[5]) {
		sHUDy = iNewValue;
	}
}

/* -----------------------------------EVENT HANDLES-----------------------------------*/
public Action:RoundStart(Handle:event, const String:name[], bool:dontBroadcast) {
	bossCounter = 0;
	if(!g_Enabled) return Plugin_Continue;
	ClearTimer(cTimer);
	if(GetClientCount(true) >= sMin) {
		if(bossCounter == 0) {
			ResetTimer();
		}
	}
	return Plugin_Continue;
}

public Action:Horse_Summoned(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
	return Plugin_Handled;
}

public Action:Horse_Killed(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_defeated_fx.wav");
	return Plugin_Handled;
}

public Action:Merasmus_Summoned(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
	return Plugin_Handled;
}

public Action:Merasmus_Killed(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_defeated_fx.wav");
	return Plugin_Handled;
}

public Action:Monoculus_Summoned(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
	return Plugin_Handled;
}

public Action:Monoculus_Killed(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_defeated_fx.wav");
	return Plugin_Handled;
}

public Action:Merasmus_Leave(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	return Plugin_Handled;
}

public Action:Monoculus_Leave(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!g_Enabled) return Plugin_Continue;
	return Plugin_Handled;
}
/* -----------------------------------EVENT HANDLES-----------------------------------*/

/* ---------------------------------COMMAND FUNCTION----------------------------------*/

public Action:ForceSpawn(client, args) {
	if(!g_Enabled) return Plugin_Handled;
	if(bossCounter != 0) {
		CReplyToCommand(client, "%t", "Boss_Active");
		return Plugin_Handled;
	}
	new String:arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if(bossCounter == 0) {
		ClearTimer(cTimer);
		SpawnBoss();
	}
	else {
		CReplyToCommand(client, "%t", "Boss_Active");
	}
	return Plugin_Handled;
}

public Action:GetCoords(client, args) {
	if(!g_Enabled) return Plugin_Handled;
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		ReplyToCommand(client, "%t", "Error");
		return Plugin_Handled;
	}
	new Float:l_pos[3];
	GetClientAbsOrigin(client, l_pos);
	ReplyToCommand(client, "[Boss Spawner] Coords: %0.0f,%0.0f,%0.0f\n[Boss Spawner] Use those coordinates and place them in configs/bossspawner_maps.cfg", l_pos[0], l_pos[1], l_pos[2]);
	return Plugin_Handled;
}

public Action:SlayBoss(client, args) {
	if(!g_Enabled) {
		ReplyToCommand(client, "[Boss] Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	new ent = -1;
	while((ent = FindEntityByClassname(ent, "headless_hatman")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}
	while((ent = FindEntityByClassname(ent, "eyeball_boss")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}
	while((ent = FindEntityByClassname(ent, "merasmus")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}
	while((ent = FindEntityByClassname(ent, "tf_zombie")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}
	CPrintToChatAll("%t", "Boss_Slain");
	//OnEntityDestroyed(bossEnt);
	return Plugin_Handled;
}

public Action:ReloadConfig(client, args) {
	ClearTimer(cTimer);
	SetupMapConfigs("bossspawner_maps.cfg");
	SetupMapConfigs("bossspawner_boss.cfg");
	ReplyToCommand(client, "[Boss Spawner] Configs have been reloaded!");
}

public Action:SpawnBossCommand(client, args) {
	if(!g_Enabled) return Plugin_Handled;
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		ReplyToCommand(client, "%t", "Error");
		return Plugin_Handled;
	}
	if(!SetTeleportEndPoint(client)) {
		ReplyToCommand(client, "[Boss] Could not find spawn point.");
		return Plugin_Handled;
	}
	if(args != 1) {
		ReplyToCommand(client, "[Boss] Format: sm_spawn <boss>");
		return Plugin_Handled;
	}
	k_pos[2] -= 10.0;
	decl String:arg[15];
	GetCmdArg(1, arg, sizeof(arg));
	new i;
	for(i = 0; i < max_boss; i++) {
		if(StrEqual(BossAttributes[i][0], arg, false)){
			break;
		}
	}
	if(i == max_boss) {
		ReplyToCommand(client, "[Boss] Error: Boss does not exist.");
		return Plugin_Handled;
	}
	index_command = i;
	ActiveTimer = false;
	CreateBoss(index_command, k_pos);
	return Plugin_Handled;
}

SetTeleportEndPoint(client) {
	decl Float:vAngles[3];
	decl Float:vOrigin[3];
	decl Float:vBuffer[3];
	decl Float:vStart[3];
	decl Float:Distance;

	GetClientEyePosition(client,vOrigin);
	GetClientEyeAngles(client, vAngles);

	new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceentFilterPlayer);

	if(TR_DidHit(trace)) {
		TR_GetEndPosition(vStart, trace);
		GetVectorDistance(vOrigin, vStart, false);
		Distance = -35.0;
		GetAngleVectors(vAngles, vBuffer, NULL_VECTOR, NULL_VECTOR);
		k_pos[0] = vStart[0] + (vBuffer[0]*Distance);
		k_pos[1] = vStart[1] + (vBuffer[1]*Distance);
		k_pos[2] = vStart[2] + (vBuffer[2]*Distance);
	}
	else {
		CloseHandle(trace);
		return false;
	}

	CloseHandle(trace);
	return true;
}

public bool:TraceentFilterPlayer(ent, contentsMask) {
	return ent > GetMaxClients() || !ent;
}
/* ---------------------------------COMMAND FUNCTION----------------------------------*/

/* --------------------------------BOSS SPAWNING CORE---------------------------------*/
public SpawnBoss() {
	ActiveTimer = true;
	if(sMode == 0) {
		s_rand = true;
		index_boss = GetRandomInt(0, max_boss-1);
		CreateBoss(index_boss, g_pos);
	}
	else if(sMode == 1) {
		s_rand = false;
		CreateBoss(index_boss, g_pos);
		index_boss++;
		if(index_boss > max_boss-1) index_boss = 0;
	}
}

public CreateBoss(b_index, Float:kpos[3]) {
	decl String:ent_class[32];
	new Float:ipos[3];
	ipos[0] = kpos[0];
	ipos[1] = kpos[1];
	ipos[2] = kpos[2];
	strcopy(ent_class, sizeof(ent_class), BossAttributes[b_index][2]);
	if(!StrEqual(BossAttributes[b_index][10], NULL_STRING)) {
		decl String:sPos[3][16];
		ExplodeString(BossAttributes[b_index][10], ",", sPos, sizeof(sPos), sizeof(sPos[]));
		ipos[0] = StringToFloat(sPos[0]);
		ipos[1] = StringToFloat(sPos[1]);
		ipos[2] = StringToFloat(sPos[2]);
	}
	new ent = CreateEntityByName(ent_class);
	if(IsValidEntity(ent)) {
		if(StrEqual(ent_class, "tf_zombie_spawner")) {
			SetEntProp(ent, Prop_Data, "m_nSkeletonType", 1);
			new Float:temp[3];
			temp = ipos;
			temp[2] += StringToFloat(BossAttributes[b_index][8]);
			TeleportEntity(ent, temp, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(ent);
			EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
			SpawnEnt = ent;
			queueBoss = true;
			AcceptEntityInput(ent, "Enable");
			return;
		}
		new playerCounter = GetClientCount(true);
		new BaseHP = StringToInt(BossAttributes[b_index][3]);
		new ScaleHP = StringToInt(BossAttributes[b_index][4]);
		new sHealth = (BaseHP + ScaleHP*playerCounter)*10;
		if(StrEqual(ent_class, "eyeball_boss")) SetEntProp(ent, Prop_Data, "m_iTeamNum", 5);
		new Float:temp[3];
		temp = ipos;
		temp[2] += StringToFloat(BossAttributes[b_index][8]);
		TeleportEntity(ent, temp, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(ent);
		SetEntProp(ent, Prop_Data, "m_iHealth", sHealth);
		SetEntProp(ent, Prop_Data, "m_iMaxHealth", sHealth);
		EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
		if(!StrEqual(BossAttributes[b_index][1], NULL_STRING)) {
			SetEntityModel(ent, BossAttributes[b_index][1]);
		}
		if(ActiveTimer == true) {
			bossCounter = 1;
			bossEnt = ent;
			bTimer = CreateTimer(StringToFloat(BossAttributes[b_index][9]), RemoveTimer, b_index);
		}
		CPrintToChatAll("%t", "Boss_Spawn", BossAttributes[b_index][0]);
		SetSize(StringToFloat(BossAttributes[b_index][6]), ent);
		SetGlow(StrEqual(BossAttributes[b_index][7], "Yes") ? 1 : 0, ent);
	}
}

public Action:RemoveTimer(Handle:hTimer, any:b_index) {
	if(IsValidEntity(bossEnt)) {
		CPrintToChatAll("%t", "Boss_Left", BossAttributes[b_index][0]);
		CPrintToChatAll("[Boss] %s has left due to boredom.", BossAttributes[b_index][0]);
		AcceptEntityInput(bossEnt, "Kill");
		bossCounter = 0;
	}
	return Plugin_Handled;
}

//remove existing boss that has the same targetname so that it doesn't cause an extra spawn point
RemoveExistingBoss() {
	if(IsValidEntity(bossEnt)) {
		AcceptEntityInput(bossEnt, "kill");
		bossCounter = 0;
	}
}

SetGlow(value, ent) {
	if(IsValidEntity(ent)) {
		SetEntProp(ent, Prop_Send, "m_bGlowEnabled", value);
	}
}

SetSize(Float:value, ent) {
	if(IsValidEntity(ent)) {
		SetEntPropFloat(ent, Prop_Send, "m_flModelScale", value);
		ResizeHitbox(ent, value);
	}
}

//Taken from r3dw3r3w0lf
ResizeHitbox(entity, Float:fScale = 1.0) {
	decl Float:vecBossMin[3], Float:vecBossMax[3];	
	GetEntPropVector(entity, Prop_Send, "m_vecMins", vecBossMin);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", vecBossMax);
	
	decl Float:vecScaledBossMin[3], Float:vecScaledBossMax[3];
	
	vecScaledBossMin = vecBossMin;
	vecScaledBossMax = vecBossMax;
	
	ScaleVector(vecScaledBossMin, fScale);
	ScaleVector(vecScaledBossMax, fScale);
	SetEntPropVector(entity, Prop_Send, "m_vecMins", vecScaledBossMin);
	SetEntPropVector(entity, Prop_Send, "m_vecMaxs", vecScaledBossMax);
}
/* --------------------------------BOSS SPAWNING CORE---------------------------------*/

/* ---------------------------------TIMER & HUD CORE----------------------------------*/
public HUDTimer() {
	if(!g_Enabled) return;
	sInterval = GetConVarFloat(cVars[2]);
	if(hHUD != INVALID_HANDLE) {
		for(new i = 1; i <= MaxClients; i++) {
			if(IsClientInGame(i))
				ClearSyncHud(i, hHUD);
		}
		CloseHandle(hHUD);
	}
	hHUD = CreateHudSynchronizer();
	cTimer = CreateTimer(1.0, HUDCountDown, _, TIMER_REPEAT);
}

public Action:HUDCountDown(Handle:hTimer) {
	sInterval--;
	for(new i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			SetHudTextParams(sHUDx, sHUDy, 1.0, 255, 255, 255, 255);
			ShowSyncHudText(i, hHUD, "Boss: %d seconds", RoundFloat(sInterval));
		}
	}
	if(sInterval <= 0) {
		SpawnBoss();
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

ResetTimer() {
	if(bossCounter == 0) {
		CPrintToChatAll("%t", "Time", RoundFloat(sInterval));
		ClearTimer(cTimer);
		HUDTimer();
	}
}
/* ---------------------------------TIMER & HUD CORE----------------------------------*/

/* ---------------------------------ENTITY MANAGEMENT---------------------------------*/
public OnEntityCreated(ent, const String:classname[]) {
	if (StrEqual(classname, "monster_resource")) {
		g_healthBar = ent;
	}
	else if(g_trackent == -1 && (StrEqual(classname, "headless_hatman") || StrEqual(classname, "eyeball_boss") || StrEqual(classname, "merasmus"))) {
		g_trackent = ent;
		SDKHook(ent, SDKHook_SpawnPost, UpdateBossHealth);
		SDKHook(ent, SDKHook_OnTakeDamagePost, OnBossDamaged);
	}
	if(StrEqual(classname, "tf_zombie") && queueBoss == true) {
		g_trackent = ent;
		RequestFrame(OnSkeletonSpawn, EntIndexToEntRef(ent));
		SDKHook(ent, SDKHook_SpawnPost, UpdateBossHealth);
		SDKHook(ent, SDKHook_OnTakeDamagePost, OnBossDamaged);
	}
	if(StrEqual(classname, "prop_dynamic")) {
		RequestFrame(OnPropSpawn, EntIndexToEntRef(ent));
	}
}

public OnEntityDestroyed(ent) {
	if(g_Enabled) {
		if(IsValidEntity(ent) && ent > MaxClients) {
			decl String:classname[MAX_NAME_LENGTH];
			GetEntityClassname(ent, classname, sizeof(classname));
			if(ent == bossEnt) {
				bossEnt = -1;
				bossCounter = 0;
				if(bossCounter == 0) {
					HUDTimer();
					CPrintToChatAll("%t", "Time", RoundFloat(sInterval));
				}
			}
			if(ent == g_trackent) {
				g_trackent = FindEntityByClassname(-1, "merasmus");
				if (g_trackent == ent) {
					g_trackent = FindEntityByClassname(ent, "merasmus");
				}
					
				if (g_trackent > -1) {
					SDKHook(g_trackent, SDKHook_OnTakeDamagePost, OnBossDamaged);
				}
				UpdateBossHealth(g_trackent);
			}
		}
	}
}

public OnSkeletonSpawn(any:ref) {
	new ent = EntRefToEntIndex(ref);
	if(IsValidEntity(ent)) {
		new temp_index = index_boss;
		if(ActiveTimer == false) temp_index = index_command;
		else {
			if(s_rand == false) temp_index = index_boss == 0 ? max_boss-1 : index_boss-1;
			else temp_index = index_boss;
		}
		new playerCounter = GetClientCount(true);
		new BaseHP = StringToInt(BossAttributes[temp_index][3]);
		new ScaleHP = StringToInt(BossAttributes[temp_index][4]);
		new sHealth = (BaseHP + ScaleHP*playerCounter)*10;
		SetEntProp(ent, Prop_Data, "m_iHealth", sHealth);
		SetEntProp(ent, Prop_Data, "m_iMaxHealth", sHealth);
		if(ActiveTimer == true) {
			bossCounter = 1;
			bossEnt = ent;
		}
		AcceptEntityInput(SpawnEnt, "kill");
		bTimer = CreateTimer(StringToFloat(BossAttributes[temp_index][9]), RemoveTimer);
		CPrintToChatAll("%t", "Boss_Spawn", BossAttributes[temp_index][0]);
		UpdateSkeleton(ent, temp_index);
		queueBoss = false;
	}
}

//Taken from SoulSharD
public OnPropSpawn(any:ref) {
	new ent = EntRefToEntIndex(ref);
	if(IsValidEntity(ent)) {
		new parent = GetEntPropEnt(ent, Prop_Data, "m_pParent");
		if(IsValidEntity(parent)) {
			decl String:strClassname[64];
			GetEntityClassname(parent, strClassname, sizeof(strClassname));
			if(StrEqual(strClassname, "headless_hatman", false))
			{
				new temp_index = index_boss;
				if(ActiveTimer == false) temp_index = index_command;
				else {
					if(s_rand == false) temp_index = index_boss == 0 ? max_boss-1 : index_boss-1;
					else temp_index = index_boss;
				}
				if(!StrEqual(BossAttributes[temp_index][5], NULL_STRING)){
					if(StrEqual(BossAttributes[temp_index][5], "Invisible")) {
						SetEntityModel(ent, "");
					}
					else {
						SetEntityModel(ent, BossAttributes[temp_index][5]);
						SetEntPropEnt(parent, Prop_Send, "m_hActiveWeapon", ent);
					}
				}
			}
		}
	}
}

UpdateSkeleton(ent, temp_index) {
	if(IsValidEntity(ent)) {
		SetSize(StringToFloat(BossAttributes[temp_index][6]), ent);
		SetGlow(StrEqual(BossAttributes[temp_index][7], "Yes") ? 1 : 0, ent);
	}
}  

FindHealthBar() {
	g_healthBar = FindEntityByClassname(-1, "monster_resource");
	if(g_healthBar == -1) {
		g_healthBar = CreateEntityByName("monster_resource");
		if(g_healthBar != -1) {
			DispatchSpawn(g_healthBar);
		}
	}
}

public Action:OnBossDamaged(victim, &attacker, &inflictor, &Float:damage, &damagetype) {
	UpdateBossHealth(victim);
}

public UpdateBossHealth(ent) {
	if (g_healthBar == -1) return;
	new percentage;
	if(IsValidEntity(ent)) {
		new HP = GetEntProp(ent, Prop_Data, "m_iHealth");
		new maxHP = GetEntProp(ent, Prop_Data, "m_iMaxHealth");
		if(HP <= (maxHP * 0.9)) {
			SetEntProp(ent, Prop_Data, "m_iHealth", 0);
			ClearTimer(bTimer);
			if(HP <= -1) {
				SetEntProp(ent, Prop_Data, "m_takedamage", 0);
			}
			percentage = 0;
		}
		else {
			percentage = RoundToCeil((float(HP) / float(maxHP / 10)) * 255.9);	//max 255.9 accurate at 100%
		}
	}
	else {
		percentage = 0;
	}
	SetEntProp(g_healthBar, Prop_Send, "m_iBossHealthPercentageByte", percentage);
}

public ClearTimer(&Handle:timer) {  
	if(timer != INVALID_HANDLE) {  
		KillTimer(timer);  
	}  
	timer = INVALID_HANDLE;  
}  
/* ---------------------------------ENTITY MANAGEMENT---------------------------------*/

/* ---------------------------------CONFIG MANAGEMENT---------------------------------*/
public SetupMapConfigs(const String:sFile[]) {
	new String:sPath[PLATFORM_MAX_PATH]; 
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if(!FileExists(sPath)) {
		LogError("[Boss Spawner] Error: Can not find map filepath %s", sPath);
		SetFailState("[Boss Spawner] Error: Can not find map filepath %s", sPath);
	}
	new Handle:kv = CreateKeyValues("Boss Spawner Map");
	FileToKeyValues(kv, sPath);

	if(!KvGotoFirstSubKey(kv)) SetFailState("Could not read maps file: %s", sPath);
	
	new mapEnabled = 0;
	new bool:Default = false;
	new tempEnabled = 0;
	new Float:temp_pos[3];
	decl String:requestMap[PLATFORM_MAX_PATH];
	decl String:currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));
	do {
		KvGetSectionName(kv, requestMap, sizeof(requestMap));
		if(StrEqual(requestMap, currentMap, false)) {
			mapEnabled = KvGetNum(kv, "Enabled", 0);
			g_pos[0] = KvGetFloat(kv, "Position X", 0.0);
			g_pos[1] = KvGetFloat(kv, "Position Y", 0.0);
			g_pos[2] = KvGetFloat(kv, "Position Z", 0.0);
			Default = true;
		}
		else if(StrEqual(requestMap, "Default", false)) {
			tempEnabled = KvGetNum(kv, "Enabled", 0);
			temp_pos[0] = KvGetFloat(kv, "Position X", 0.0);
			temp_pos[1] = KvGetFloat(kv, "Position Y", 0.0);
			temp_pos[2] = KvGetFloat(kv, "Position Z", 0.0);
		}
	} while (KvGotoNextKey(kv));
	CloseHandle(kv);
	if(Default == false) {
		mapEnabled = tempEnabled;
		g_pos = temp_pos;
	}
	LogMessage("Map: %s, Enabled: %s, Position:%f, %f, %f", currentMap, mapEnabled ? "Yes" : "No", g_pos[0],g_pos[1],g_pos[2]);
	if(mapEnabled != 0) {
		g_Enabled = true;
		if(GetClientCount(true) >= sMin) {
			HUDTimer();
			CPrintToChatAll("%t", "Time", RoundFloat(sInterval));
		}
	}
	else if(mapEnabled == 0) {
		g_Enabled = false;
	}
	LogMessage("Loaded Map configs successfully."); 
}

public SetupBossConfigs(const String:sFile[]) {
	new String:sPath[PLATFORM_MAX_PATH]; 
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if(!FileExists(sPath)) {
		LogError("[Boss Spawner] Error: Can not find map filepath %s", sPath);
		SetFailState("[Boss Spawner] Error: Can not find map filepath %s", sPath);
	}
	new Handle:kv = CreateKeyValues("Custom Boss Spawner");
	FileToKeyValues(kv, sPath);

	if(!KvGotoFirstSubKey(kv)) SetFailState("Could not read maps file: %s", sPath);
	new b_index = 0;
	do {
		KvGetSectionName(kv, BossAttributes[b_index][0], sizeof(BossAttributes[][]));
		KvGetString(kv, "Model", BossAttributes[b_index][1], sizeof(BossAttributes[][]), NULL_STRING);
		KvGetString(kv, "Type", BossAttributes[b_index][2], sizeof(BossAttributes[][]));
		KvGetString(kv, "HP Base", BossAttributes[b_index][3], sizeof(BossAttributes[][]), "10000");
		KvGetString(kv, "HP Scale", BossAttributes[b_index][4], sizeof(BossAttributes[][]), "1000");
		KvGetString(kv, "WeaponModel", BossAttributes[b_index][5], sizeof(BossAttributes[][]), NULL_STRING);
		KvGetString(kv, "Size", BossAttributes[b_index][6], sizeof(BossAttributes[][]), "1.0");
		KvGetString(kv, "Glow", BossAttributes[b_index][7], sizeof(BossAttributes[][]), "Yes");
		KvGetString(kv, "PosFix", BossAttributes[b_index][8], sizeof(BossAttributes[][]), "0.0");
		KvGetString(kv, "Lifetime", BossAttributes[b_index][9], sizeof(BossAttributes[][]), "120");
		KvGetString(kv, "Position", BossAttributes[b_index][10], sizeof(BossAttributes[][]), NULL_STRING);
		if(StrEqual(BossAttributes[b_index][2], "tf_zombie_spawner") && !StrEqual(BossAttributes[b_index][1], NULL_STRING)) {
			if(StrEqual(BossAttributes[b_index][2], "tf_zombie_spawner")) {
				LogError("Skeleton type is not supported.");
				SetFailState("Skeleton type is not supported.");
			}
		}
		if(!StrEqual(BossAttributes[b_index][2], "headless_hatman") && !StrEqual(BossAttributes[b_index][2], "eyeball_boss") && !StrEqual(BossAttributes[b_index][2], "merasmus") && !StrEqual(BossAttributes[b_index][2], "tf_zombie_spawner")){
			LogError("Type is undetermined, please check boss type again.");
			SetFailState("Type is undetermined, please check boss type again.");
		}
		if(StrEqual(BossAttributes[b_index][2], "eyeball_boss")) {
			RemoveBossLifeline("tf_eyeball_boss_lifetime", "tf_eyeball_boss_lifetime", StringToInt(BossAttributes[b_index][9])+1);
		}
		else if(StrEqual(BossAttributes[b_index][2], "merasmus")) {
			RemoveBossLifeline("tf_merasmus_lifetime", "tf_merasmus_lifetime", StringToInt(BossAttributes[b_index][9])+1);
		}
		if(!StrEqual(BossAttributes[b_index][1], NULL_STRING)) {
			PrecacheModel(BossAttributes[b_index][1], true);
		}
		if(!StrEqual(BossAttributes[b_index][2], "headless_hatman")) {
			if(!StrEqual(BossAttributes[b_index][5], NULL_STRING)) {
				LogError("Weapon model can only be changed on Type:headless_hatman");
				SetFailState("Weapon model can only be changed on Type:headless_hatman");
			}
		}
		else if(!StrEqual(BossAttributes[b_index][5], NULL_STRING)) {
			if(!StrEqual(BossAttributes[b_index][5], "Invisible")) {
				PrecacheModel(BossAttributes[b_index][5], true);
			}
		}
		b_index++;
	} while (KvGotoNextKey(kv));
	max_boss = b_index;
	CloseHandle(kv);
	LogMessage("Loaded Boss configs successfully."); 
}
/* ---------------------------------CONFIG MANAGEMENT---------------------------------*/

/* ----------------------------------------END----------------------------------------*/