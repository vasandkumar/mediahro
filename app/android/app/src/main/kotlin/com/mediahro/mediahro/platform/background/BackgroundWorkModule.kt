package com.mediahro.mediahro.platform.background

import android.content.Context
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.mediahro.mediahro.pigeon.BackgroundWorkHostApi
import java.util.concurrent.TimeUnit

/**
 * BackgroundWorkFacade on Android (ADR-049): each id is one unique periodic
 * WorkManager job (`UPDATE` keeps the schedule's phase when nothing changed and
 * applies a new interval or constraints otherwise). When the OS runs the job,
 * [PeriodicWorker] delivers the id on `runs`.
 *
 * Nothing here needs a permission or an extra service: WorkManager's boot
 * receiver is removed by the flavour manifests (docs/07), so after a restart
 * jobs resume when the app next starts and schedules them again.
 */
class BackgroundWorkModule(private val context: Context) : BackgroundWorkHostApi {
    private val work: WorkManager get() = WorkManager.getInstance(context)

    override fun schedulePeriodic(
        id: String,
        intervalMs: Long,
        requiresNetwork: Boolean,
        unmeteredOnly: Boolean,
        requiresCharging: Boolean,
    ) {
        val name = BackgroundPlan.uniqueName(id)
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(BackgroundPlan.network(requiresNetwork, unmeteredOnly))
            .setRequiresCharging(requiresCharging)
            .build()
        val request = PeriodicWorkRequestBuilder<PeriodicWorker>(
            BackgroundPlan.interval(intervalMs),
            TimeUnit.MILLISECONDS,
        )
            .setConstraints(constraints)
            .setInputData(Data.Builder().putString(PeriodicWorker.KEY_ID, id).build())
            .build()
        work.enqueueUniquePeriodicWork(name, ExistingPeriodicWorkPolicy.UPDATE, request)
    }

    override fun cancel(id: String) {
        work.cancelUniqueWork(BackgroundPlan.uniqueName(id))
    }

    override fun complete(id: String, success: Boolean) {
        BackgroundHub.broker.complete(id, success)
    }

    override fun available(): Boolean = true
}
