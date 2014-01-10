int hookoffset;

#define SETUPHOOK(hookname, hookdef) \
	g_pGameConf->GetOffset(hookname, &hookoffset); \
	if(hookoffset > 0) \
	{ \
		SH_MANUALHOOK_RECONFIGURE(hookdef, hookoffset, 0, 0); \
		g_pSM->LogMessage(myself, #hookname " offset = %d", hookoffset); \
	} \
	else \
	{ \
		g_pSM->LogError(myself, #hookname " offset %d not valid", hookoffset); \
		return false; \
	}

#define SIGFIND(configname, funcname, functype) \
	if(!g_pGameConf->GetMemSig(configname, &add)) \
	{ \
		g_pSM->LogError(myself, "Could not locate function " #configname); \
		return false; \
	} \
	else \
	{ \
		funcname = (functype)add; \
		g_pSM->LogMessage(myself,"%p " #configname, funcname); \
	}