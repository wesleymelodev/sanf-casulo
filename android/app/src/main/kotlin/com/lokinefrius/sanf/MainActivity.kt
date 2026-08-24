package com.lokinefrius.sanf

import android.content.Context
import android.content.Intent
import android.os.BatteryManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.AlarmClock
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
                    
                    if (settings.containsKey("proactivityLevel")) {
                        scheduleNativeWorker()
                    }
                    
                    result.success(true)
                }
                "scheduleWorker" -> {
                    scheduleNativeWorker()
                    result.success(true)
                }
                "device_vibrate" -> {
                    val duration = (call.argument<Int>("duration") ?: 500).toLong()
                    vibrateDevice(duration)
                    result.success(true)
                }
                "device_set_alarm" -> {
                    val hour = call.argument<Int>("hour") ?: 8
                    val minutes = call.argument<Int>("minutes") ?: 0
                    val message = call.argument<String>("message") ?: "Alarme do SANF"
                    val success = setAlarm(hour, minutes, message)
                    result.success(success)
                }
                "device_get_battery" -> {
                    val level = getBatteryLevel()
                    result.success(level)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun vibrateDevice(durationMs: Long) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                val vibrator = vibratorManager.defaultVibrator
                vibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(durationMs)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun setAlarm(hour: Int, minutes: Int, message: String): Boolean {
        return try {
            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(AlarmClock.EXTRA_HOUR, hour)
                putExtra(AlarmClock.EXTRA_MINUTES, minutes)
                putExtra(AlarmClock.EXTRA_MESSAGE, message)
                putExtra(AlarmClock.EXTRA_SKIP_UI, true)
            }
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun getBatteryLevel(): Int {
        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        return batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
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
