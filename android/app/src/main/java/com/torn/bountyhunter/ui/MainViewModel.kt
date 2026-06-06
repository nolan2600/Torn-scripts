package com.torn.bountyhunter.ui

import android.Manifest
import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.viewModelScope
import com.torn.bountyhunter.MainActivity
import com.torn.bountyhunter.api.ApiClient
import com.torn.bountyhunter.data.*
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.util.concurrent.ConcurrentHashMap

class MainViewModel(app: Application) : AndroidViewModel(app) {

    val prefs = Prefs(app)

    private val _bounties = MutableLiveData<List<BountyMatch>>(emptyList())
    val bounties: LiveData<List<BountyMatch>> = _bounties

    private val _loading = MutableLiveData(false)
    val loading: LiveData<Boolean> = _loading

    private val _error = MutableLiveData<String?>(null)
    val error: LiveData<String?> = _error

    private val _statusText = MutableLiveData<String>("")
    val statusText: LiveData<String> = _statusText

    private val _countdown = MutableLiveData(0)
    val countdown: LiveData<Int> = _countdown

    private val _counts = MutableLiveData<RefreshCounts>(RefreshCounts())
    val counts: LiveData<RefreshCounts> = _counts

    private var myUserId: Int? = null
    private var myAge: Int? = null
    private var myCountry: String? = null

    private val profileCache = ConcurrentHashMap<Int, Pair<CachedProfile, Long>>()
    private var warCache: Pair<Set<Int>, Long>? = null

    private var refreshJob: Job? = null
    private var countdownJob: Job? = null

    // Hospital alert tracking: targetId -> hospUntil at time of scheduling
    private val hospAlertJobs = ConcurrentHashMap<Int, Pair<Job, Long>>()

    data class CachedProfile(
        val status: PlayerStatus?,
        val age: Int?,
        val factionId: Int?,
        val revivable: Boolean?,
        val name: String?,
        val level: Int?
    )

    companion object {
        const val STATUS_CACHE_MS = 20_000L
        const val FACTION_CACHE_MS = 5 * 60 * 1000L
        const val CONCURRENCY = 3
        const val NPP_DAYS = 14
        const val NOTIF_CHANNEL_ID = "bh_hosp_alerts"
        const val API_RATE_MS = 750L

        val BS_RANGES = listOf(
            Triple("bs-2k",   2_000L,         25_000L),
            Triple("bs-20k",  20_000L,        250_000L),
            Triple("bs-200k", 200_000L,       2_500_000L),
            Triple("bs-2m",   2_000_000L,     25_000_000L),
            Triple("bs-20m",  20_000_000L,    250_000_000L),
            Triple("bs-200m", 200_000_000L,   Long.MAX_VALUE)
        )

        private val HOSP_ADJ_COUNTRY = mapOf(
            "Mexican" to "Mexico", "Caymanian" to "Cayman Islands", "Canadian" to "Canada",
            "Hawaiian" to "Hawaii", "British" to "United Kingdom", "Argentinian" to "Argentina",
            "Argentine" to "Argentina", "Swiss" to "Switzerland", "Japanese" to "Japan",
            "Chinese" to "China", "Emirati" to "United Arab Emirates", "South African" to "South Africa"
        )
    }

    init {
        createNotificationChannel()
    }

    // ── Public API ─────────────────────────────────────────────────────────

    fun startAutoRefresh() {
        refreshJob?.cancel()
        refreshJob = viewModelScope.launch {
            while (isActive) {
                doRefresh()
                val secs = prefs.refreshSec
                if (secs <= 0) break
                startCountdown(secs)
                delay(secs * 1_000L)
            }
        }
    }

    fun stopAutoRefresh() {
        refreshJob?.cancel()
        refreshJob = null
        countdownJob?.cancel()
        countdownJob = null
        _countdown.postValue(0)
    }

    fun triggerRefreshNow() {
        stopAutoRefresh()
        refreshJob = viewModelScope.launch {
            doRefresh()
            val secs = prefs.refreshSec
            if (secs > 0) {
                startCountdown(secs)
                delay(secs * 1_000L)
                if (isActive) startAutoRefresh()
            }
        }
    }

    // ── Countdown ──────────────────────────────────────────────────────────

    private fun startCountdown(secs: Int) {
        countdownJob?.cancel()
        countdownJob = viewModelScope.launch {
            for (i in secs downTo 0) {
                _countdown.postValue(i)
                delay(1_000L)
            }
        }
    }

    // ── Main refresh pipeline ──────────────────────────────────────────────

    private suspend fun doRefresh() {
        val apiKey = prefs.tornApiKey.trim()
        if (apiKey.isEmpty()) {
            _error.postValue("No API key. Open Settings to configure.")
            return
        }

        _loading.postValue(true)
        _error.postValue(null)

        try {
            // Step 1: validate key + get own profile for country / age / id
            tryGetMyProfile(apiKey)

            // Step 2: fetch all bounty pages
            _statusText.postValue("Fetching bounties…")
            val allBounties = fetchAllBounties(apiKey)
            _statusText.postValue("Fetched ${allBounties.size} bounties")

            // Step 3: deduplicate by target (keep highest reward, sum counts)
            val grouped = LinkedHashMap<Int, BountyEntry>()
            val countMap = HashMap<Int, Int>()
            for (b in allBounties) {
                val qty = if ((b.quantity ?: 0) > 0) b.quantity!! else 1
                val ex = grouped[b.target_id]
                if (ex == null) {
                    grouped[b.target_id] = b
                    countMap[b.target_id] = qty
                } else {
                    countMap[b.target_id] = (countMap[b.target_id] ?: 0) + qty
                    if (b.reward > ex.reward) grouped[b.target_id] = b
                }
            }
            val deduped = grouped.values.toList()

            val counts = RefreshCounts(total = allBounties.size)

            // Step 4: basic filter — min reward + exclude self
            val byBasic = deduped.filter { b ->
                b.reward >= prefs.minPrice && (myUserId == null || b.target_id != myUserId)
            }

            // Step 5: FF / BS filter
            _statusText.postValue("Fetching FF scores for ${byBasic.size} targets…")
            val ffMap = fetchFFScores(prefs.ffScouterKey.trim(), byBasic.map { it.target_id })
            val includeUnknown = prefs.includeUnknownFF || (ffMap.isEmpty() && prefs.ffScouterKey.isNotBlank())

            val byFF = byBasic.mapNotNull { b ->
                val entry = ffMap[b.target_id]
                when {
                    entry != null -> Pair(b, entry)
                    includeUnknown -> Pair(b, null)
                    prefs.ffScouterKey.isBlank() -> Pair(b, null)  // no key = no filtering
                    else -> null
                }
            }.filter { (_, entry) ->
                if (entry == null) true
                else entry.first >= prefs.minFF && entry.first <= prefs.maxFF
            }

            val selectedRanges = prefs.bsRanges
            val byBS = if (selectedRanges.isEmpty()) byFF
            else byFF.filter { (_, entry) ->
                if (entry == null) true
                else {
                    val bsNum = parseBS(entry.second) ?: return@filter true
                    selectedRanges.any { rid ->
                        val r = BS_RANGES.find { it.first == rid } ?: return@any false
                        bsNum in r.second..r.third
                    }
                }
            }

            // Step 6: profile status check
            _statusText.postValue("Checking ${byBS.size} target statuses…")
            val profiles = fetchProfiles(byBS.map { it.first.target_id }, apiKey)
            val warFactions = fetchWarFactions(apiKey)

            val nowSec = System.currentTimeMillis() / 1_000L
            val hospWindowSec = prefs.hospitalMaxMin * 60L
            val matches = ArrayList<BountyMatch>()

            for ((b, ffEntry) in byBS) {
                val p = profiles[b.target_id] ?: continue
                val status = p.status ?: continue

                if (!isAttackableByAge(p.age, myAge)) continue

                val targetCountry = playerCountry(status)
                if (myCountry != null && targetCountry != null && targetCountry != myCountry) continue

                val inWar = p.factionId != null && warFactions.contains(p.factionId)
                if (prefs.hideWarTargets && inWar) continue

                val state = status.state ?: continue
                val until = status.until ?: 0L
                val remaining = maxOf(0L, until - nowSec)

                when (state) {
                    "Okay" -> matches.add(
                        BountyMatch(
                            targetId = b.target_id, targetName = b.target_name,
                            targetLevel = b.target_level, reward = b.reward,
                            bountyCount = countMap[b.target_id] ?: 1,
                            ff = ffEntry?.first, bs = ffEntry?.second,
                            statusState = "Okay", hospUntil = 0L,
                            revivable = null, inFactionWar = inWar
                        )
                    )
                    "Hospital" -> if (remaining <= hospWindowSec) {
                        if (prefs.revivableOnly && p.revivable != true) continue
                        matches.add(
                            BountyMatch(
                                targetId = b.target_id, targetName = b.target_name,
                                targetLevel = b.target_level, reward = b.reward,
                                bountyCount = countMap[b.target_id] ?: 1,
                                ff = ffEntry?.first, bs = ffEntry?.second,
                                statusState = "Hospital", hospUntil = until,
                                revivable = p.revivable, inFactionWar = inWar
                            )
                        )
                    }
                }
            }

            matches.sortByDescending { it.reward }

            _bounties.postValue(matches)
            _counts.postValue(counts.copy(
                afterBasic = byBasic.size,
                afterFF = byFF.size,
                afterBS = byBS.size,
                matches = matches.size
            ))
            _statusText.postValue("${matches.size} matches · last refresh ${timeLabel()}")

            if (prefs.hospAlertsEnabled) scheduleHospAlerts(matches)

        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _error.postValue(e.message ?: "Unknown error")
            _statusText.postValue("Error · ${e.message}")
        } finally {
            _loading.postValue(false)
        }
    }

    // ── API helpers ────────────────────────────────────────────────────────

    private suspend fun tryGetMyProfile(apiKey: String) {
        try {
            val p = ApiClient.torn.getMyProfile(apiKey).resolvedProfile() ?: return
            myUserId = p.id ?: myUserId
            myAge = p.age ?: myAge
            myCountry = playerCountry(p.status) ?: myCountry
        } catch (_: Exception) {}
    }

    private suspend fun fetchAllBounties(apiKey: String): List<BountyEntry> {
        val all = ArrayList<BountyEntry>()
        var nextUrl: String? = null
        var offset = 0
        var safety = 15

        while (safety-- > 0) {
            val response = if (nextUrl != null) {
                val url = ensureKeyInUrl(nextUrl, apiKey)
                ApiClient.torn.getBountiesByUrl(url)
            } else {
                ApiClient.torn.getBounties(apiKey, 100, offset)
            }

            val batch = response.bounties ?: break
            all.addAll(batch)
            if (batch.isEmpty()) break

            nextUrl = response._metadata?.links?.next
            if (nextUrl.isNullOrBlank()) break
            offset += batch.size
        }

        return all
    }

    private suspend fun fetchFFScores(
        ffKey: String,
        ids: List<Int>
    ): Map<Int, Pair<Double, String?>> {
        if (ffKey.isBlank() || ids.isEmpty()) return emptyMap()
        val result = HashMap<Int, Pair<Double, String?>>()
        ids.chunked(200).forEach { chunk ->
            try {
                val data = ApiClient.ffScouter.getStats(ffKey, chunk.joinToString(","))
                for (e in data) {
                    val id = e.player_id ?: continue
                    val ff = e.fair_fight ?: continue
                    result[id] = Pair(ff, e.bs_estimate_human)
                }
            } catch (_: Exception) {}
        }
        return result
    }

    private suspend fun fetchProfiles(ids: List<Int>, apiKey: String): Map<Int, CachedProfile> {
        val out = ConcurrentHashMap<Int, CachedProfile>()
        val now = System.currentTimeMillis()
        val stale = ArrayList<Int>()

        for (id in ids.distinct()) {
            val cached = profileCache[id]
            if (cached != null) {
                val (data, fetchedAt) = cached
                val hospLocked = data.status?.state == "Hospital" &&
                    ((data.status.until ?: 0L) * 1_000L) > now
                if (hospLocked || now - fetchedAt < STATUS_CACHE_MS) {
                    out[id] = data
                    continue
                }
            }
            stale.add(id)
        }

        if (stale.isEmpty()) return out

        val semaphore = Semaphore(CONCURRENCY)
        coroutineScope {
            stale.map { id ->
                async {
                    semaphore.withPermit {
                        delay(API_RATE_MS / CONCURRENCY)
                        try {
                            val profile = ApiClient.torn
                                .getUserProfile(id, apiKey)
                                .resolvedProfile() ?: return@withPermit

                            val factionId = profile.faction?.faction_id
                                ?: profile.faction?.id

                            val data = CachedProfile(
                                status = profile.status,
                                age = profile.age,
                                factionId = factionId,
                                revivable = profile.revivable,
                                name = profile.name,
                                level = profile.level
                            )
                            profileCache[id] = Pair(data, System.currentTimeMillis())
                            out[id] = data
                        } catch (_: Exception) {}
                    }
                }
            }.awaitAll()
        }

        return out
    }

    private suspend fun fetchWarFactions(apiKey: String): Set<Int> {
        val now = System.currentTimeMillis()
        warCache?.let { (ids, at) -> if (now - at < FACTION_CACHE_MS) return ids }

        val ids = HashSet<Int>()
        try {
            val url = "https://api.torn.com/torn/?selections=rankedwars,territorywars&key=$apiKey"
            val data = ApiClient.torn.getRankedWars(url)
            data.rankedwars?.values?.forEach { war ->
                war.factions?.keys?.forEach { fid -> fid.toIntOrNull()?.let { ids.add(it) } }
            }
            data.territorywars?.values?.forEach { war ->
                war.assaulting_faction?.let { ids.add(it) }
                war.defending_faction?.let { ids.add(it) }
            }
        } catch (_: Exception) {}

        warCache = Pair(ids, now)
        return ids
    }

    // ── Hospital exit alerts ───────────────────────────────────────────────

    private fun scheduleHospAlerts(matches: List<BountyMatch>) {
        val hospNow = matches.filter { it.statusState == "Hospital" && it.hospUntil > 0 }
            .associateBy { it.targetId }
        val nowSec = System.currentTimeMillis() / 1_000L

        // Cancel alerts for targets no longer on the board
        val removed = hospAlertJobs.keys - hospNow.keys
        for (id in removed) {
            hospAlertJobs.remove(id)?.first?.cancel()
        }

        for (m in hospNow.values) {
            val existing = hospAlertJobs[m.targetId]
            // Don't reschedule if same hospital stint (hospUntil within 5s jitter)
            if (existing != null && Math.abs(existing.second - m.hospUntil) <= 5) continue
            existing?.first?.cancel()

            val alertAtSec = m.hospUntil - 60
            if (alertAtSec < nowSec - 10) continue  // window already passed

            val delayMs = maxOf(0L, (alertAtSec - nowSec) * 1_000L)
            val snapUntil = m.hospUntil
            val job = viewModelScope.launch {
                delay(delayMs)
                fireHospAlert(m)
            }
            hospAlertJobs[m.targetId] = Pair(job, snapUntil)
        }
    }

    private fun fireHospAlert(m: BountyMatch) {
        val app = getApplication<Application>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(app, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) return

        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val remSec = maxOf(0L, m.hospUntil - System.currentTimeMillis() / 1_000L)
        val remLabel = if (remSec <= 0) "out NOW" else "~${remSec}s"

        val intent = Intent(app, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pi = PendingIntent.getActivity(
            app, m.targetId, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif = NotificationCompat.Builder(app, NOTIF_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("${m.targetName} exits hospital $remLabel")
            .setContentText(buildString {
                append("Reward: ${formatMoney(m.reward)}")
                m.ff?.let { append(" · FF: ${"%.2f".format(it)}") }
                if (m.revivable == true) append(" · Revivable")
            })
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()

        nm.notify(m.targetId, notif)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                NOTIF_CHANNEL_ID,
                "Hospital Exit Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "Alerts when a bounty target is about to leave hospital" }
            (getApplication<Application>()
                .getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }
    }

    // ── Filter helpers (mirror the web script logic) ───────────────────────

    private fun playerCountry(status: PlayerStatus?): String? {
        val state = status?.state ?: return null
        val desc = status.description ?: ""
        return when (state) {
            "Okay", "Jail", "Federal" -> "Torn"
            "Abroad" -> Regex("^In\\s+(.+)$").find(desc)?.groupValues?.get(1)?.trim()
            "Hospital" -> when {
                desc.contains("In hospital", ignoreCase = true) -> "Torn"
                else -> Regex("^In an?\\s+(.+?)\\s+hospital", RegexOption.IGNORE_CASE)
                    .find(desc)?.groupValues?.get(1)?.trim()
                    ?.let { HOSP_ADJ_COUNTRY[it] }
            }
            else -> null
        }
    }

    private fun isAttackableByAge(targetAge: Int?, myAge: Int?): Boolean {
        targetAge ?: return true
        val meUnderNpp = myAge != null && myAge < NPP_DAYS
        return if (meUnderNpp) targetAge >= 1 else targetAge >= NPP_DAYS
    }

    private fun parseBS(human: String?): Long? {
        human ?: return null
        val m = Regex("""^\s*([\d.]+)\s*([kKmMbB]?)\s*$""").matchEntire(human) ?: return null
        val n = m.groupValues[1].toDoubleOrNull() ?: return null
        val mult = when (m.groupValues[2].lowercase()) {
            "k" -> 1_000L; "m" -> 1_000_000L; "b" -> 1_000_000_000L; else -> 1L
        }
        return (n * mult).toLong()
    }

    private fun ensureKeyInUrl(url: String, key: String): String {
        if (url.contains("key=")) return url
        return if (url.contains("?")) "$url&key=$key" else "$url?key=$key"
    }

    private fun timeLabel(): String {
        val h = java.util.Calendar.getInstance()
        return "%02d:%02d".format(h.get(java.util.Calendar.HOUR_OF_DAY), h.get(java.util.Calendar.MINUTE))
    }

    fun formatMoney(n: Long): String = when {
        n >= 1_000_000_000L -> "\$${"%.2f".format(n / 1_000_000_000.0)}B"
        n >= 1_000_000L     -> "\$${"%.2f".format(n / 1_000_000.0)}M"
        n >= 1_000L         -> "\$${"%.1f".format(n / 1_000.0)}K"
        else                -> "\$$n"
    }

    override fun onCleared() {
        super.onCleared()
        hospAlertJobs.values.forEach { it.first.cancel() }
    }
}
