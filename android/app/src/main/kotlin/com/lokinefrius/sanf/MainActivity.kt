package com.lokinefrius.sanf

import android.content.Context
import android.content.Intent
import android.os.BatteryManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.AlarmClock
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.ExistingPeriodicWorkPolicy
import java.util.concurrent.TimeUnit
import android.appwidget.AppWidgetManager
import android.content.ComponentName

class MainActivity : FlutterActivity(), SensorEventListener {
    private val CHANNEL = "com.lokinefrius.sanf/settings"
    private val SENSOR_CHANNEL = "com.lokinefrius.sanf/sensors"

    private lateinit var sensorManager: SensorManager
    private var lightSensor: Sensor? = null
    private var proximitySensor: Sensor? = null
    private var accelerometer: Sensor? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        lightSensor = sensorManager.getDefaultSensor(Sensor.TYPE_LIGHT)
        proximitySensor = sensorManager.getDefaultSensor(Sensor.TYPE_PROXIMITY)
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SENSOR_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    registerSensors()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    unregisterSensors()
                }
            }
        )
        
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
                    
                    val ghost = settings["ghostName"] as? String ?: "SANF"
                    startPersistentService(ghost, "Sincronizado com o núcleo.")

                    if (settings.containsKey("ghostName") || settings.containsKey("eyeColor")) {
                        updateWidget()
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
                "device_flashlight" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    toggleFlashlight(enabled)
                    result.success(true)
                }
                "device_set_brightness" -> {
                    val brightness = call.argument<Double>("brightness")?.toFloat() ?: 0.5f
                    setBrightness(brightness)
                    result.success(true)
                }
                "device_set_volume" -> {
                    val volume = call.argument<Int>("volume") ?: 50
                    setVolume(volume)
                    result.success(true)
                }
                "bringToForeground" -> {
                    bringToForeground()
                    result.success(true)
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

    private fun toggleFlashlight(enabled: Boolean) {
        try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraId = cameraManager.cameraIdList[0]
            cameraManager.setTorchMode(cameraId, enabled)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun setBrightness(value: Float) {
        this@MainActivity.runOnUiThread {
            try {
                val layoutParams = this@MainActivity.window.attributes
                layoutParams.screenBrightness = value.coerceIn(0.01f, 1.0f)
                this@MainActivity.window.attributes = layoutParams
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun setVolume(value: Int) {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val targetVolume = (maxVolume * (value / 100.0)).toInt()
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetVolume, 0)
        } catch (e: Exception) {
            e.printStackTrace()
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

    private fun bringToForeground() {
        val intent = Intent(applicationContext, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        
        startActivity(intent)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            (this as android.app.Activity).setShowWhenLocked(true)
            (this as android.app.Activity).setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
            keyguardManager.requestDismissKeyguard(this as android.app.Activity, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
    }

    private fun startPersistentService(ghostName: String, status: String) {
        val serviceIntent = Intent(applicationContext, SANFService::class.java)
        serviceIntent.putExtra("ghostName", ghostName)
        serviceIntent.putExtra("status", status)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun updateWidget() {
        val intent = Intent(applicationContext, SANFWidget::class.java)
        intent.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
        val ids = AppWidgetManager.getInstance(applicationContext)
            .getAppWidgetIds(ComponentName(applicationContext, SANFWidget::class.java))
        intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        sendBroadcast(intent)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        
        val sensorData = mutableMapOf<String, Any>()
        when (event.sensor.type) {
            Sensor.TYPE_LIGHT -> {
                sensorData["type"] = "light"
                sensorData["value"] = event.values[0]
            }
            Sensor.TYPE_PROXIMITY -> {
                sensorData["type"] = "proximity"
                sensorData["value"] = event.values[0]
            }
            Sensor.TYPE_ACCELEROMETER -> {
                sensorData["type"] = "accelerometer"
                sensorData["x"] = event.values[0]
                sensorData["y"] = event.values[1]
                sensorData["z"] = event.values[2]
            }
        }
        
        if (sensorData.isNotEmpty()) {
            this@MainActivity.runOnUiThread {
                eventSink?.success(sensorData)
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Not needed for now
    }

    private fun registerSensors() {
        lightSensor?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
        }
        proximitySensor?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
        }
        accelerometer?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
        }
    }

    private fun unregisterSensors() {
        sensorManager.unregisterListener(this)
    }

    override fun onResume() {
        super.onResume()
        if (eventSink != null) {
            registerSensors()
        }
    }

    override fun onPause() {
        super.onPause()
        unregisterSensors()
    }
}
