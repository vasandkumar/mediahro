package com.mediahro.mediahro.platform.background

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.mediahro.mediahro.platform.AppEngine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * One run of a scheduled job (ADR-049). It makes sure a Flutter engine is
 * running Dart (starting the app's engine without a screen if the app is not
 * open, as ADR-036 does for the car), hands the job id to Dart on `runs`, and
 * waits for `complete()`. Success is `Result.success`; a failure, or Dart not
 * answering in time, is `Result.retry`, which WorkManager backs off and retries.
 */
class PeriodicWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val id = inputData.getString(KEY_ID) ?: return Result.failure()
        AppEngine.onWork(active = true)
        try {
            withContext(Dispatchers.Main) { AppEngine.startHeadless(applicationContext) }
            return if (BackgroundHub.broker.run(id, BackgroundPlan.RUN_TIMEOUT_MS)) Result.success() else Result.retry()
        } finally {
            AppEngine.onWork(active = false)
        }
    }

    companion object {
        const val KEY_ID = "id"
    }
}
