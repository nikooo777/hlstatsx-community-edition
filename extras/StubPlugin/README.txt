This plugin has only the single purpose of providing the three public cvars that HLstatsX:CE uses for identification.

These should only be used if you are NOT already running the HLstatsX:CE Ingame (sourcemod) Plugin.

You will need to create a vdf file to load the the plugin.


Ex.

addons/hlxcestub_ep1.dll
addons/stub.vdf

Windows VDF example:

"Plugin"
{
	"file"	"..\cstrike\addons\hlxcestub_ep1.dll"
}

linux VDF example:

"Plugin"
{
	"file"	"../tf/addons/hlxcestub_ob.so"
}