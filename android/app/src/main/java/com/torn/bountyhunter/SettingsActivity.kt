package com.torn.bountyhunter

import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.torn.bountyhunter.api.ApiClient
import com.torn.bountyhunter.data.Prefs
import com.torn.bountyhunter.databinding.ActivitySettingsBinding
import kotlinx.coroutines.launch

class SettingsActivity : AppCompatActivity() {

    private lateinit var binding: ActivitySettingsBinding
    private lateinit var prefs: Prefs

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        prefs = Prefs(this)

        binding.toolbar.setNavigationOnClickListener { finish() }

        populateFields()
        setupListeners()
    }

    private fun populateFields() {
        with(binding) {
            etTornKey.setText(prefs.tornApiKey)
            etFfKey.setText(prefs.ffScouterKey)
            etMinReward.setText(prefs.minPrice.toString())
            etMinFF.setText(prefs.minFF.toString())
            etMaxFF.setText(prefs.maxFF.toString())
            etHospMaxMin.setText(prefs.hospitalMaxMin.toString())
            etRefreshSec.setText(prefs.refreshSec.toString())

            switchUnknownFF.isChecked = prefs.includeUnknownFF
            switchRevivableOnly.isChecked = prefs.revivableOnly
            switchHideWar.isChecked = prefs.hideWarTargets
            switchHospAlerts.isChecked = prefs.hospAlertsEnabled

            val bs = prefs.bsRanges
            cbBs2k.isChecked   = bs.contains("bs-2k")
            cbBs20k.isChecked  = bs.contains("bs-20k")
            cbBs200k.isChecked = bs.contains("bs-200k")
            cbBs2m.isChecked   = bs.contains("bs-2m")
            cbBs20m.isChecked  = bs.contains("bs-20m")
            cbBs200m.isChecked = bs.contains("bs-200m")
        }
    }

    private fun setupListeners() {
        binding.btnValidateTorn.setOnClickListener { validateTornKey() }
        binding.btnValidateFF.setOnClickListener { validateFFKey() }
        binding.btnSave.setOnClickListener { saveAndFinish() }
    }

    private fun validateTornKey() {
        val key = binding.etTornKey.text?.toString()?.trim() ?: return
        if (key.length != 16) {
            showKeyStatus(isTorn = true, ok = false, msg = "Key must be 16 characters")
            return
        }
        binding.btnValidateTorn.isEnabled = false
        lifecycleScope.launch {
            try {
                val profile = ApiClient.torn.getMyProfile(key).resolvedProfile()
                if (profile != null) {
                    showKeyStatus(isTorn = true, ok = true, msg = "Valid — ${profile.name} (L${profile.level})")
                } else {
                    showKeyStatus(isTorn = true, ok = false, msg = "Invalid key or no access")
                }
            } catch (e: Exception) {
                showKeyStatus(isTorn = true, ok = false, msg = e.message ?: "Request failed")
            } finally {
                binding.btnValidateTorn.isEnabled = true
            }
        }
    }

    private fun validateFFKey() {
        val key = binding.etFfKey.text?.toString()?.trim() ?: return
        if (key.isBlank()) {
            showKeyStatus(isTorn = false, ok = true, msg = "Left blank — FF filtering disabled")
            return
        }
        if (key.length != 16) {
            showKeyStatus(isTorn = false, ok = false, msg = "Key must be 16 characters")
            return
        }
        binding.btnValidateFF.isEnabled = false
        lifecycleScope.launch {
            try {
                val result = ApiClient.ffScouter.checkKey(key)
                when {
                    result.code != null -> showKeyStatus(isTorn = false, ok = false,
                        msg = result.error ?: "FFScouter error code ${result.code}")
                    result.is_registered == true -> showKeyStatus(isTorn = false, ok = true,
                        msg = if (result.is_premium == true) "Valid — premium" else "Valid")
                    else -> showKeyStatus(isTorn = false, ok = false,
                        msg = "Not registered — sign up at ffscouter.com first")
                }
            } catch (e: Exception) {
                showKeyStatus(isTorn = false, ok = false, msg = e.message ?: "Request failed")
            } finally {
                binding.btnValidateFF.isEnabled = true
            }
        }
    }

    private fun showKeyStatus(isTorn: Boolean, ok: Boolean, msg: String) {
        val tv = if (isTorn) binding.tvTornKeyStatus else binding.tvFfKeyStatus
        tv.text = msg
        tv.setTextColor(getColor(if (ok) R.color.status_ok else R.color.error))
        tv.visibility = View.VISIBLE
    }

    private fun saveAndFinish() {
        with(binding) {
            prefs.tornApiKey    = etTornKey.text?.toString()?.trim() ?: ""
            prefs.ffScouterKey  = etFfKey.text?.toString()?.trim() ?: ""
            prefs.minPrice      = etMinReward.text?.toString()?.toLongOrNull() ?: 500_000L
            prefs.minFF         = etMinFF.text?.toString()?.toFloatOrNull() ?: 1.0f
            prefs.maxFF         = etMaxFF.text?.toString()?.toFloatOrNull() ?: 3.0f
            prefs.hospitalMaxMin = etHospMaxMin.text?.toString()?.toIntOrNull() ?: 5
            prefs.refreshSec    = etRefreshSec.text?.toString()?.toIntOrNull()?.coerceAtLeast(10) ?: 60

            prefs.includeUnknownFF = switchUnknownFF.isChecked
            prefs.revivableOnly    = switchRevivableOnly.isChecked
            prefs.hideWarTargets   = switchHideWar.isChecked
            prefs.hospAlertsEnabled = switchHospAlerts.isChecked

            val bs = mutableSetOf<String>()
            if (cbBs2k.isChecked)   bs.add("bs-2k")
            if (cbBs20k.isChecked)  bs.add("bs-20k")
            if (cbBs200k.isChecked) bs.add("bs-200k")
            if (cbBs2m.isChecked)   bs.add("bs-2m")
            if (cbBs20m.isChecked)  bs.add("bs-20m")
            if (cbBs200m.isChecked) bs.add("bs-200m")
            prefs.bsRanges = bs
        }

        Toast.makeText(this, "Settings saved", Toast.LENGTH_SHORT).show()
        finish()
    }
}
