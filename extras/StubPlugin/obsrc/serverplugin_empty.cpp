//===== Copyright © 1996-2008, Valve Corporation, All rights reserved. ======//
//
// Purpose: 
//
// $NoKeywords: $
//
//===========================================================================//

#include <stdio.h>

#include "engine/iserverplugin.h"
#include "eiface.h"
#include "convar.h"
#include "tier2/tier2.h"
#include "tier0/memdbgon.h"

CGlobalVars *gpGlobals = NULL;

class CEmptyServerPlugin: public IServerPluginCallbacks
{
public:
	CEmptyServerPlugin();
	~CEmptyServerPlugin();

	// IServerPluginCallbacks methods
	virtual bool			Load(	CreateInterfaceFn interfaceFactory, CreateInterfaceFn gameServerFactory );
	virtual void			Unload( void );
	virtual void			Pause( void );
	virtual void			UnPause( void );
	virtual const char     *GetPluginDescription( void );      
	virtual void			LevelInit( char const *pMapName );
	virtual void			ServerActivate( edict_t *pEdictList, int edictCount, int clientMax );
	virtual void			GameFrame( bool simulating );
	virtual void			LevelShutdown( void );
	virtual void			ClientActive( edict_t *pEntity );
	virtual void			ClientDisconnect( edict_t *pEntity );
	virtual void			ClientPutInServer( edict_t *pEntity, char const *playername );
	virtual void			SetCommandClient( int index );
	virtual void			ClientSettingsChanged( edict_t *pEdict );
	virtual PLUGIN_RESULT	ClientConnect( bool *bAllowConnect, edict_t *pEntity, const char *pszName, const char *pszAddress, char *reject, int maxrejectlen );
	virtual PLUGIN_RESULT	ClientCommand( edict_t *pEntity, const CCommand &args );
	virtual PLUGIN_RESULT	NetworkIDValidated( const char *pszUserName, const char *pszNetworkID );
	virtual void			OnQueryCvarValueFinished( QueryCvarCookie_t iCookie, edict_t *pPlayerEntity, EQueryCvarValueStatus eStatus, const char *pCvarName, const char *pCvarValue );

	// added with version 3 of the interface.
	virtual void			OnEdictAllocated( edict_t *edict );
	virtual void			OnEdictFreed( const edict_t *edict  );	

	// IGameEventListener Interface
	virtual void FireGameEvent( KeyValues * event );

	virtual int GetCommandIndex() { return m_iClientCommandIndex; }
private:
	int m_iClientCommandIndex;
};


CEmptyServerPlugin g_EmtpyServerPlugin;
EXPOSE_SINGLE_INTERFACE_GLOBALVAR(CEmptyServerPlugin, IServerPluginCallbacks, INTERFACEVERSION_ISERVERPLUGINCALLBACKS, g_EmtpyServerPlugin );

CEmptyServerPlugin::CEmptyServerPlugin()
{
	m_iClientCommandIndex = 0;
}

CEmptyServerPlugin::~CEmptyServerPlugin()
{
}

bool CEmptyServerPlugin::Load(	CreateInterfaceFn interfaceFactory, CreateInterfaceFn gameServerFactory )
{
	ConnectTier1Libraries( &interfaceFactory, 1 );

	ConVar_Register( 0 );
	return true;
}

void CEmptyServerPlugin::Unload( void )
{
	ConVar_Unregister( );
	DisconnectTier1Libraries( );
}

void CEmptyServerPlugin::Pause( void )
{
}

void CEmptyServerPlugin::UnPause( void )
{
}

const char *CEmptyServerPlugin::GetPluginDescription( void )
{
	return "HLX:CE Plugin Stub v1.0";
}

void CEmptyServerPlugin::LevelInit( char const *pMapName )
{
}

void CEmptyServerPlugin::ServerActivate( edict_t *pEdictList, int edictCount, int clientMax )
{
}

void CEmptyServerPlugin::GameFrame( bool simulating )
{
}

void CEmptyServerPlugin::LevelShutdown( void ) // !!!!this can get called multiple times per map change
{
}

void CEmptyServerPlugin::FireGameEvent(class KeyValues *)
{
}

void CEmptyServerPlugin::ClientActive( edict_t *pEntity )
{
}

void CEmptyServerPlugin::ClientDisconnect( edict_t *pEntity )
{
}

void CEmptyServerPlugin::ClientPutInServer( edict_t *pEntity, char const *playername )
{
}

void CEmptyServerPlugin::SetCommandClient( int index )
{
}

void ClientPrint( edict_t *pEdict, char *format, ... )
{
}

void CEmptyServerPlugin::ClientSettingsChanged( edict_t *pEdict )
{
}

PLUGIN_RESULT CEmptyServerPlugin::ClientConnect( bool *bAllowConnect, edict_t *pEntity, const char *pszName, const char *pszAddress, char *reject, int maxrejectlen )
{
	return PLUGIN_CONTINUE;
}

PLUGIN_RESULT CEmptyServerPlugin::ClientCommand( edict_t *pEntity, const CCommand &args )
{
	return PLUGIN_CONTINUE;
}

PLUGIN_RESULT CEmptyServerPlugin::NetworkIDValidated( const char *pszUserName, const char *pszNetworkID )
{
	return PLUGIN_CONTINUE;
}

void CEmptyServerPlugin::OnQueryCvarValueFinished( QueryCvarCookie_t iCookie, edict_t *pPlayerEntity, EQueryCvarValueStatus eStatus, const char *pCvarName, const char *pCvarValue )
{
}

void CEmptyServerPlugin::OnEdictAllocated( edict_t *edict )
{
}

void CEmptyServerPlugin::OnEdictFreed( const edict_t *edict  )
{
}

static ConVar new_cvar1("hlxce_plugin_version", "1.0-Stub", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY, "HLstatsX:CE Version Stub Plugin");
static ConVar new_cvar2("hlxce_version", "", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY, "HLstatsX:CE");
static ConVar new_cvar3("hlxce_webpage", "http://www.hlxcommunity.com", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY, "http://www.hlxcommunity.com");
