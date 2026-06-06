package com.torn.bountyhunter.data

import android.content.Context
import android.content.SharedPreferences

class Prefs(context: Context) {

    private val sp: SharedPreferences =
        context.getSharedPreferences("bh_prefs", Context.MODE_PRIVATE)

    var tornApiKey: String
        get() = sp.getString("torn_api_key", "") ?: ""
        set(v) = sp.edit().putString("torn_api_key", v).apply()

    var ffScouterKey: String
        get() = sp.getString("ff_scouter_key", "") ?: ""
        set(v) = sp.edit().putString("ff_scouter_key", v).apply()

    var minPrice: Long
        get() = sp.getLong("min_price", 500_000L)
        set(v) = sp.edit().putLong("min_price", v).apply()

    var minFF: Float
        get() = sp.getFloat("min_ff", 1.0f)
        set(v) = sp.edit().putFloat("min_ff", v).apply()

    var maxFF: Float
        get() = sp.getFloat("max_ff", 3.0f)
        set(v) = sp.edit().putFloat("max_ff", v).apply()

    var hospitalMaxMin: Int
        get() = sp.getInt("hospital_max_min", 5)
        set(v) = sp.edit().putInt("hospital_max_min", v).apply()

    var refreshSec: Int
        get() = sp.getInt("refresh_sec", 60)
        set(v) = sp.edit().putInt("refresh_sec", v).apply()

    var includeUnknownFF: Boolean
        get() = sp.getBoolean("include_unknown_ff", false)
        set(v) = sp.edit().putBoolean("include_unknown_ff", v).apply()

    var revivableOnly: Boolean
        get() = sp.getBoolean("revivable_only", false)
        set(v) = sp.edit().putBoolean("revivable_only", v).apply()

    var hideWarTargets: Boolean
        get() = sp.getBoolean("hide_war_targets", false)
        set(v) = sp.edit().putBoolean("hide_war_targets", v).apply()

    var hospAlertsEnabled: Boolean
        get() = sp.getBoolean("hosp_alerts_enabled", false)
        set(v) = sp.edit().putBoolean("hosp_alerts_enabled", v).apply()

    var bsRanges: Set<String>
        get() = sp.getStringSet("bs_ranges", emptySet()) ?: emptySet()
        set(v) = sp.edit().putStringSet("bs_ranges", v).apply()

    var watchedTargetIds: Set<String>
        get() = sp.getStringSet("watched_ids", emptySet()) ?: emptySet()
        set(v) = sp.edit().putStringSet("watched_ids", v).apply()

    var maxPrice: Long
        get() = sp.getLong("max_price", 0L)
        set(v) = sp.edit().putLong("max_price", v).apply()

    var sortMode: SortMode
        get() = try { SortMode.valueOf(sp.getString("sort_mode", "REWARD") ?: "REWARD") } catch (_: Exception) { SortMode.REWARD }
        set(v) = sp.edit().putString("sort_mode", v.name).apply()

    var statusFilter: StatusFilter
        get() = try { StatusFilter.valueOf(sp.getString("status_filter", "ALL") ?: "ALL") } catch (_: Exception) { StatusFilter.ALL }
        set(v) = sp.edit().putString("status_filter", v.name).apply()
}
