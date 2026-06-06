package com.torn.bountyhunter.ui

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.torn.bountyhunter.R
import com.torn.bountyhunter.data.BountyMatch
import com.torn.bountyhunter.databinding.ItemBountyBinding

class BountyAdapter(
    private val onAttack: (BountyMatch) -> Unit,
    private val onProfile: (BountyMatch) -> Unit,
    private val formatMoney: (Long) -> String
) : ListAdapter<BountyMatch, BountyAdapter.VH>(DIFF) {

    inner class VH(private val b: ItemBountyBinding) : RecyclerView.ViewHolder(b.root) {

        fun bind(m: BountyMatch) {
            // Name + level + count
            b.tvName.text = buildString {
                append(m.targetName)
                append(" L${m.targetLevel}")
                if (m.bountyCount > 1) append(" ×${m.bountyCount}")
            }

            // Reward
            b.tvReward.text = formatMoney(m.reward)

            // FF + BS
            val ffStr = m.ff?.let { "FF ${"%.2f".format(it)}" } ?: "FF ?"
            val bsStr = m.bs?.let { " · BS $it" } ?: ""
            b.tvFfBs.text = "$ffStr$bsStr"

            // Status
            when (m.statusState) {
                "Okay" -> {
                    b.tvStatus.text = "Okay"
                    b.tvStatus.setTextColor(ContextCompat.getColor(b.root.context, R.color.status_ok))
                    b.tvRevivable.visibility = View.GONE
                }
                "Hospital" -> {
                    val nowSec = System.currentTimeMillis() / 1_000L
                    val rem = maxOf(0L, m.hospUntil - nowSec)
                    val hospLabel = when {
                        rem <= 0 -> "Out now"
                        rem >= 3600 -> "${rem / 3600}h ${(rem % 3600) / 60}m"
                        rem >= 60   -> "${rem / 60}m ${rem % 60}s"
                        else        -> "${rem}s"
                    }
                    b.tvStatus.text = "Hospital · $hospLabel"
                    b.tvStatus.setTextColor(ContextCompat.getColor(b.root.context, R.color.status_hosp))

                    when (m.revivable) {
                        true  -> { b.tvRevivable.text = "Revivable"; b.tvRevivable.visibility = View.VISIBLE }
                        false -> { b.tvRevivable.text = "Not revivable"; b.tvRevivable.visibility = View.VISIBLE }
                        null  -> b.tvRevivable.visibility = View.GONE
                    }
                }
                else -> {
                    b.tvStatus.text = m.statusState
                    b.tvStatus.setTextColor(ContextCompat.getColor(b.root.context, R.color.text_secondary))
                    b.tvRevivable.visibility = View.GONE
                }
            }

            // War badge
            b.tvWarBadge.visibility = if (m.inFactionWar) View.VISIBLE else View.GONE

            // Buttons
            b.btnAttack.setOnClickListener { onAttack(m) }
            b.btnProfile.setOnClickListener { onProfile(m) }
            b.root.setOnClickListener { onProfile(m) }
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH =
        VH(ItemBountyBinding.inflate(LayoutInflater.from(parent.context), parent, false))

    override fun onBindViewHolder(holder: VH, position: Int) =
        holder.bind(getItem(position))

    companion object {
        private val DIFF = object : DiffUtil.ItemCallback<BountyMatch>() {
            override fun areItemsTheSame(a: BountyMatch, b: BountyMatch) = a.targetId == b.targetId
            override fun areContentsTheSame(a: BountyMatch, b: BountyMatch) = a == b
        }
    }
}
