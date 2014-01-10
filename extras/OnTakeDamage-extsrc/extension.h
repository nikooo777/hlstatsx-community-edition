#ifndef _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_
#define _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_

#include "smsdk_ext.h"

class TakeDamageHook : public SDKExtension
{
public:
	virtual bool SDK_OnLoad(char *error, size_t maxlength, bool late);
	virtual void SDK_OnUnload();
	//virtual void SDK_OnAllLoaded();
	//virtual void SDK_OnPauseChange(bool paused);
	//virtual bool QueryRunning(char *error, size_t maxlength);
public:
#if defined SMEXT_CONF_METAMOD
	virtual bool SDK_OnMetamodLoad(ISmmAPI *ismm, char *error, size_t maxlength, bool late);
	virtual bool SDK_OnMetamodUnload(char *error, size_t maxlength);
	//virtual bool SDK_OnMetamodPauseChange(bool paused, char *error, size_t maxlength);
#endif
public:
	//Client Sourcehook Handlers
	void Hook_ClientPutInServer(edict_t *pEdict, const char *playername);
	void Hook_ClientDisconnect(edict_t *pEdict);
	int Hook_OnTakeDamage(const CTakeDamageInfo &info);
};

extern IServerGameClients *serverclients;
extern IServerGameEnts *gameents;

#endif // _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_