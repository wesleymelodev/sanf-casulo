package com.lokinefrius.sanf

import android.content.Context
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.ExistingPeriodicWorkPolicy
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.lokinefrius.sanf/settings"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "syncSettings" -> {
                    val settings = call.arguments as Map<String, Any>
                    val prefs = getSharedPreferences("SANF_SETTINGS", Context.MODE_PRIVATE)
                    val editor = prefs.edit()
                    
                    settings.forEach { (key, value) ->
                        when (value) {
                            is String -> editor.putString(key, value)
                            is Double -> editor.putFloat(key, value.toFloat())
                            is Int -> editor.putInt(key, value)
                            is Boolean -> editor.putBoolean(key, value)
                        }
                    }
                    editor.apply()
                    
                    // Se a proatividade mudou, reagenda o worker nativo
                    if (settings.containsKey("proactivityLevel")) {
                        scheduleNativeWorker()
                    }
                    
                    result.success(true)
                }
                "scheduleWorker" -> {
                    scheduleNativeWorker()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun scheduleNativeWorker() {
        val request = PeriodicWorkRequestBuilder<ThoughtWorker>(2, TimeUnit.HOURS)
            .build()
        
        WorkManager.getInstance(applicationContext).enqueueUniquePeriodicWork(
            "sanf_native_proactivity",
            ExistingPeriodicWorkPolicy.UPDATE,
            request
        )
    }
}
