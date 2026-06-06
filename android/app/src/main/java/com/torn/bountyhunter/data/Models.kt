package com.torn.bountyhunter.data

// ── Torn API responses ─────────────────────────────────────────────────────

data class BountyEntry(
    val target_id: Int,
    val target_name: String,
    val target_level: Int,
    val reward: Long,
    val quantity: Int?
)

data class BountiesResponse(
    val bounties: List<BountyEntry>?,
    val bounties_delay: Int?,
    val _metadata: BountiesMetadata?
)

data class BountiesMetadata(
    val links: MetadataLinks?
)

data class MetadataLinks(
    val next: String?,
    val prev: String?,
    val first: String?,
    val last: String?
)

data class PlayerStatus(
    val state: String?,
    val description: String?,
    val until: Long?,
    val color: String?
)

data class PlayerFaction(
    val faction_id: Int?,
    val id: Int?,
    val name: String?,
    val faction_name: String?,
    val position: String?,
    val days_in_faction: Int?
)

data class UserProfile(
    val id: Int?,
    val name: String?,
    val level: Int?,
    val age: Int?,
    val status: PlayerStatus?,
    val faction: PlayerFaction?,
    val faction_id: Int?,   // some v2 responses expose this at the top level
    val revivable: Boolean?
)

data class UserProfileResponse(
    val profile: UserProfile?,
    // Fallback: some endpoints return profile fields at the top level
    val id: Int?,
    val name: String?,
    val level: Int?,
    val age: Int?,
    val status: PlayerStatus?,
    val faction: PlayerFaction?,
    val faction_id: Int?,
    val revivable: Boolean?
) {
    fun resolvedProfile(): UserProfile? = profile ?: if (id != null) UserProfile(
        id = id, name = name, level = level, age = age,
        status = status, faction = faction, faction_id = faction_id, revivable = revivable
    ) else null
}


// ── FFScouter API response ─────────────────────────────────────────────────

data class FFScouterEntry(
    val player_id: Int?,
    val fair_fight: Double?,
    val bs_estimate_human: String?
)

data class FFScouterKeyCheckResponse(
    val is_registered: Boolean?,
    val is_premium: Boolean?,
    val code: Int?,
    val error: String?
)

// ── Internal domain model ──────────────────────────────────────────────────

data class BountyMatch(
    val targetId: Int,
    val targetName: String,
    val targetLevel: Int,
    val reward: Long,
    val bountyCount: Int,
    val ff: Double?,
    val bs: String?,
    val statusState: String,
    val hospUntil: Long,
    val revivable: Boolean?,
    val inFactionWar: Boolean
)

data class RefreshCounts(
    val total: Int = 0,
    val afterBasic: Int = 0,
    val afterFF: Int = 0,
    val afterBS: Int = 0,
    val matches: Int = 0,
    val ffError: String? = null
)

enum class SortMode { REWARD, TIME_LEFT }
enum class StatusFilter { ALL, OKAY, HOSPITAL }
