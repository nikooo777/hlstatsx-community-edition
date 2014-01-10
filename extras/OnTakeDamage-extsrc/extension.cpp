#define GAME_DLL 1
#include "cbase.h"
#include "extension.h"
#include "macros.h"

#ifndef METAMOD_PLAPI_VERSION
#define GetEngineFactory engineFactory
#define GetServerFactory serverFactory
#endif

TakeDamageHook g_Interface;
SMEXT_LINK(&g_Interface);

// Globals
IForward *g_pTakeDamageHook	= NULL;
IGameConfig *g_pGameConf = NULL;
IServerGameClients *serverclients = NULL;
IServerGameEnts *gameents = NULL;

// Hooks
SH_DECL_HOOK2_void(IServerGameClients, ClientPutInServer, SH_NOATTRIB, 0, edict_t *, char const *);
SH_DECL_HOOK1_void(IServerGameClients, ClientDisconnect, SH_NOATTRIB, 0, edict_t *);
SH_DECL_MANUALHOOK1(OnTakeDamageHook, 0, 0, 0, int, CTakeDamageInfo const&);

// Functions
bool TakeDamageHook::SDK_OnLoad(char *error, size_t maxlength, bool late)
{
	char conf_error[255] = "";
	if(!gameconfs->LoadGameConfigFile("takedamage", &g_pGameConf, conf_error, sizeof(conf_error)))
	{
		if(conf_error)
			snprintf(error, maxlength, "Could not read takedamage.txt: %s", conf_error);
		
		return false;
	}

	SETUPHOOK("TakeDamage", OnTakeDamageHook);

	g_pTakeDamageHook = forwards->CreateForward("OnTakeDamage", ET_Event, 5, NULL, Param_Cell, Param_Cell, Param_Cell, Param_Float, Param_Cell);

	return true;
}

void TakeDamageHook::SDK_OnUnload()
{
	forwards->ReleaseForward(g_pTakeDamageHook);

	gameconfs->CloseGameConfigFile(g_pGameConf);
}

bool TakeDamageHook::SDK_OnMetamodLoad(ISmmAPI *ismm, char *error, size_t maxlen, bool late)
{
	GET_V_IFACE_CURRENT(GetServerFactory, serverclients, IServerGameClients, INTERFACEVERSION_SERVERGAMECLIENTS);
	GET_V_IFACE_CURRENT(GetServerFactory, gameents, IServerGameEnts, INTERFACEVERSION_SERVERGAMEENTS);

	SH_ADD_HOOK_MEMFUNC(IServerGameClients, ClientPutInServer, serverclients, &g_Interface, &TakeDamageHook::Hook_ClientPutInServer, true);
	SH_ADD_HOOK_MEMFUNC(IServerGameClients, ClientDisconnect, serverclients, &g_Interface, &TakeDamageHook::Hook_ClientDisconnect, true);

	return true;
}

bool TakeDamageHook::SDK_OnMetamodUnload(char *error, size_t maxlength)
{
	SH_REMOVE_HOOK_MEMFUNC(IServerGameClients, ClientPutInServer, serverclients, &g_Interface, &TakeDamageHook::Hook_ClientPutInServer, true);
	SH_REMOVE_HOOK_MEMFUNC(IServerGameClients, ClientDisconnect, serverclients, &g_Interface, &TakeDamageHook::Hook_ClientDisconnect, true);

	return true;
}

void TakeDamageHook::Hook_ClientPutInServer(edict_t *pEdict, const char *playername)
{
	CBaseEntity *pEnt = gameents->EdictToBaseEntity(pEdict);
	if(pEnt)
	{
		SH_ADD_MANUALHOOK_MEMFUNC(OnTakeDamageHook, pEnt, &g_Interface, &TakeDamageHook::Hook_OnTakeDamage, true);
	}
}

void TakeDamageHook::Hook_ClientDisconnect(edict_t *pEdict)
{
	CBaseEntity *pEnt = gameents->EdictToBaseEntity(pEdict);
	if(pEnt)
	{
		SH_REMOVE_MANUALHOOK_MEMFUNC(OnTakeDamageHook, pEnt, &g_Interface, &TakeDamageHook::Hook_OnTakeDamage, true);
	}
}

int TakeDamageHook::Hook_OnTakeDamage(const CTakeDamageInfo &info)
{
	if(g_pTakeDamageHook->GetFunctionCount() == 0)
		RETURN_META_VALUE(MRES_IGNORED, 0);

	int victim = engine->IndexOfEdict(gameents->BaseEntityToEdict(META_IFACEPTR(CBaseEntity)));
	int attacker = info.m_hAttacker.GetEntryIndex();
	int inflictor = info.m_hInflictor.GetEntryIndex();
	int damagetype = info.GetDamageType();
	float damage = info.GetDamage();
	
	g_pTakeDamageHook->PushCell(victim);
	g_pTakeDamageHook->PushCell(attacker);
	g_pTakeDamageHook->PushCell(inflictor);
	g_pTakeDamageHook->PushFloat(damage);
	g_pTakeDamageHook->PushCell(damagetype);
	g_pTakeDamageHook->Execute(NULL);

	RETURN_META_VALUE(MRES_IGNORED, 0);
}