package com.torn.bountyhunter.ui

import android.content.res.ColorStateList
import android.os.Handler
import android.os.Looper
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
    private val onWatch: (BountyMatch) -> Unit,
    private val formatMoney: (Long) -> String
) : ListAdapter<BountyMatch, BountyAdapter.VH>(DIFF) {

    var watchedIds: Set<Int> = emptySet()
        set(value) {
            if (field == value) return
            field = value
            notifyItemRangeChanged(0, itemCount, PAYLOAD_WATCH)
        }

    inner class VH(val b: ItemBountyBinding) : RecyclerView.ViewHolder(b.root) {

        private val handler = Handler(Looper.getMainLooper())
        private var countdownRunnable: Runnable? = null
        private var boundHospUntil = 0L

        fun bind(m: BountyMatch, isWatched: Boolean) {
            b.tvName.text = buildString {
                append(m.targetName)
                append(" L${m.targetLevel}")
                if (m.bountyCount > 1) append(" ×${m.bountyCount}")
            }

            b.tvReward.text = formatMoney(m.reward)

            val ffStr = m.ff?.let { "FF ${"%.2f".format(it)}" } ?: "FF ?"
            val bsStr = m.bs?.let { " · BS $it" } ?: ""
            b.tvFfBs.text = "$ffStr$bsStr"

            when (m.statusState) {
                "Okay" -> {
                    stopCountdown()
                    b.tvStatus.text = "Okay"
                    b.tvStatus.setTextColor(ContextCompat.getColor(b.root.context, R.color.status_ok))
                    b.tvRevivable.visibility = View.GONE
                    b.btnWatch.visibility = View.GONE
                }
                "Hospital" -> {
                    startCountdown(m.hospUntil)
                    when (m.revivable) {
                        true  -> { b.tvRevivable.text = "Revivable"; b.tvRevivable.visibility = View.VISIBLE }
                        false -> { b.tvRevivable.text = "Not revivable"; b.tvRevivable.visibility = View.VISIBLE }
                        null  -> b.tvRevivable.visibility = View.GONE
                    }
                    b.btnWatch.visibility = View.VISIBLE
                    bindWatchButton(isWatched, m)
                }
                else -> {
                    stopCountdown()
                    b.tvStatus.text = m.statusState
                    b.tvStatus.setTextColor(ContextCompat.getColor(b.root.context, R.color.text_secondary))
                    b.tvRevivable.visibility = View.GONE
                    b.btnWatch.visibility = View.GONE
                }
            }

            b.tvWarBadge.visibility = if (m.inFactionWar) View.VISIBLE else View.GONE

            b.btnAttack.setOnClickListener { onAttack(m) }
            b.btnProfile.setOnClickListener { onProfile(m) }
            b.root.setOnClickListener { onProfile(m) }
        }

        fun bindWatchOnly(m: BountyMatch, isWatched: Boolean) {
            if (m.statusState == "Hospital") {
                b.btnWatch.visibility = View.VISIBLE
                bindWatchButton(isWatched, m)
            }
        }

        private fun bindWatchButton(isWatched: Boolean, m: BountyMatch) {
            val tint = if (isWatched) R.color.accent else R.color.text_secondary
            b.btnWatch.imageTintList = ColorStateList.valueOf(
                ContextCompat.getColor(b.root.context, tint)
            )
            b.btnWatch.setOnClickListener { onWatch(m) }
        }

        private fun startCountdown(hospUntil: Long) {
            if (boundHospUntil == hospUntil && countdownRunnable != null) return
            stopCountdown()
            boundHospUntil = hospUntil
            val run = object : Runnable {
                override fun run() {
                    val nowSec = System.currentTimeMillis() / 1_000L
                    val rem = maxOf(0L, boundHospUntil - nowSec)
                    b.tvStatus.text = "Hospital · ${formatTime(rem)}"
                    b.tvStatus.setTextColor(ContextCompat.getColor(b.root.context, R.color.status_hosp))
                    if (rem > 0) handler.postDelayed(this, 1_000L)
                }
            }
            countdownRunnable = run
            handler.post(run)
        }

        fun stopCountdown() {
            countdownRunnable?.let { handler.removeCallbacks(it) }
            countdownRunnable = null
            boundHospUntil = 0L
        }

        private fun formatTime(rem: Long): String = when {
            rem <= 0    -> "Out now"
            rem >= 3600 -> "${rem / 3600}h ${(rem % 3600) / 60}m"
            rem >= 60   -> "${rem / 60}m ${rem % 60}s"
            else        -> "${rem}s"
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH =
        VH(ItemBountyBinding.inflate(LayoutInflater.from(parent.context), parent, false))

    override fun onBindViewHolder(holder: VH, position: Int) {
        holder.bind(getItem(position), watchedIds.contains(getItem(position).targetId))
    }

    override fun onBindViewHolder(holder: VH, position: Int, payloads: MutableList<Any>) {
        if (payloads.isEmpty()) {
            onBindViewHolder(holder, position)
        } else {
            holder.bindWatchOnly(getItem(position), watchedIds.contains(getItem(position).targetId))
        }
    }

    override fun onViewDetachedFromWindow(holder: VH) {
        super.onViewDetachedFromWindow(holder)
        holder.stopCountdown()
    }

    override fun onViewRecycled(holder: VH) {
        super.onViewRecycled(holder)
        holder.stopCountdown()
    }

    companion object {
        private const val PAYLOAD_WATCH = "watch"

        private val DIFF = object : DiffUtil.ItemCallback<BountyMatch>() {
            override fun areItemsTheSame(a: BountyMatch, b: BountyMatch) = a.targetId == b.targetId
            override fun areContentsTheSame(a: BountyMatch, b: BountyMatch) = a == b
        }
    }
}
