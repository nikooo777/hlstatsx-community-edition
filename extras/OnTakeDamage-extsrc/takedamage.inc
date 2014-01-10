#if defined _takedamage_included
 #endinput
#endif
#define _takedamage_included

/**
 * @brief When a client takes damage
 *
 * @param    victim     Victim client index
 * @param    attacker   Attacker client index
 * @param    inflictor  Inflictor client index
 * @param    damage     Amount of damage taken
 * @param    damagetype Damage type
 * @noreturn
 */
forward Action:OnTakeDamage(victim, attacker, inflictor, Float:damage, damagetype);

/** Do Not Edit Below This Line **/

public Extension:__ext_takedamage =
{
	name = "OnTakeDamage",
	file = "takedamage.ext",
#if defined AUTOLOAD_EXTENSIONS
	autoload = 1,
#else
	autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
	required = 1,
#else
	required = 0,
#endif
};