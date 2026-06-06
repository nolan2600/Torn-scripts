package com.torn.bountyhunter

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.view.View
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import com.torn.bountyhunter.data.BountyMatch
import com.torn.bountyhunter.databinding.ActivityMainBinding
import com.torn.bountyhunter.ui.BountyAdapter
import com.torn.bountyhunter.ui.MainViewModel

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val vm: MainViewModel by viewModels()
    private lateinit var adapter: BountyAdapter

    private val notifPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* result ignored — alerts still work silently if denied */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)

        adapter = BountyAdapter(
            onAttack  = { openUrl("https://www.torn.com/page.php?sid=attack&user2ID=${it.targetId}") },
            onProfile = { openUrl("https://www.torn.com/profiles.php?XID=${it.targetId}") },
            formatMoney = vm::formatMoney
        )
        binding.recyclerView.adapter = adapter
        binding.recyclerView.layoutManager = LinearLayoutManager(this)
        binding.recyclerView.setHasFixedSize(false)

        binding.swipeRefresh.setColorSchemeResources(R.color.accent)
        binding.swipeRefresh.setProgressBackgroundColorSchemeResource(R.color.surface_dark)
        binding.swipeRefresh.setOnRefreshListener { vm.triggerRefreshNow() }

        observeViewModel()
        requestNotifPermissionIfNeeded()
    }

    override fun onResume() {
        super.onResume()
        if (vm.prefs.tornApiKey.isNotBlank()) {
            // Only start if not already running (avoid double-start)
            if (vm.bounties.value.isNullOrEmpty()) vm.startAutoRefresh()
        } else {
            binding.tvError.text = getString(R.string.no_api_key)
            binding.tvError.visibility = View.VISIBLE
        }
    }

    override fun onPause() {
        super.onPause()
        vm.stopAutoRefresh()
    }

    private fun observeViewModel() {
        vm.bounties.observe(this) { list ->
            adapter.submitList(list)
            binding.swipeRefresh.isRefreshing = false
            binding.tvEmpty.visibility = if (list.isEmpty()) View.VISIBLE else View.GONE
        }

        vm.loading.observe(this) { loading ->
            binding.progressBar.visibility = if (loading) View.VISIBLE else View.GONE
            if (loading) binding.tvEmpty.visibility = View.GONE
        }

        vm.error.observe(this) { err ->
            if (err != null) {
                binding.tvError.text = err
                binding.tvError.visibility = View.VISIBLE
            } else {
                binding.tvError.visibility = View.GONE
            }
        }

        vm.statusText.observe(this) { text ->
            if (text.isNullOrBlank()) {
                binding.tvStatus.visibility = View.GONE
            } else {
                binding.tvStatus.text = text
                binding.tvStatus.visibility = View.VISIBLE
            }
        }

        vm.countdown.observe(this) { secs ->
            if (secs > 0) {
                binding.tvCountdown.text = "↻ ${secs}s"
                binding.tvCountdown.visibility = View.VISIBLE
            } else {
                binding.tvCountdown.visibility = View.GONE
            }
        }

        vm.counts.observe(this) { c ->
            if (c.total > 0) {
                binding.tvCounts.text = "${c.matches} matches  (${c.total} bounties → ${c.afterBasic} filter → ${c.matches})"
            } else {
                binding.tvCounts.text = ""
            }
        }
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.main_menu, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean = when (item.itemId) {
        R.id.action_refresh  -> { vm.triggerRefreshNow(); true }
        R.id.action_settings -> { startActivity(Intent(this, SettingsActivity::class.java)); true }
        else -> super.onOptionsItemSelected(item)
    }

    private fun openUrl(url: String) {
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    }

    private fun requestNotifPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}
