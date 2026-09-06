package com.lokinefrius.sanf

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

class ThoughtWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val prefs = applicationContext.getSharedPreferences("SANF_SETTINGS", Context.MODE_PRIVATE)
        val ghostName = prefs.getString("ghostName", "SANF") ?: "SANF"
        val bankJson = prefs.getString("proactiveBank", "[]") ?: "[]"
        
        val bank = try {
            val arr = JSONArray(bankJson)
            val list = mutableListOf<String>()
            for (i in 0 until arr.length()) {
                list.add(arr.getString(i))
            }
            list
        } catch (_: Exception) {
            mutableListOf<String>()
        }

        if (bank.isNotEmpty()) {
            val thought = bank.removeAt(0)
            
            // Salva a lista atualizada
            val newArr = JSONArray()
            bank.forEach { newArr.put(it) }
            prefs.edit().putString("proactiveBank", newArr.toString()).apply()
            
            showNotification(ghostName, thought)
            Result.success()
        } else {
            Result.success() // Não há o que fazer, mas não é falha
        }
    }

    private fun showNotification(title: String, body: String) {
        val channelId = "sanf_proactive_channel"
        val notificationManager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "SANF Proatividade", NotificationManager.IMPORTANCE_HIGH)
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(applicationContext, 0, intent, PendingIntent.FLAG_IMMUTABLE)

        val notification = NotificationCompat.Builder(applicationContext, channelId)
            .setSmallIcon(applicationContext.resources.getIdentifier("ic_launcher", "mipmap", applicationContext.packageName))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(2000, notification)
    }
}
