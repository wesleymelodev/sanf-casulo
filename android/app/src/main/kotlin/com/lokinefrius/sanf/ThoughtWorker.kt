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
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.Random

class ThoughtWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    private val client = OkHttpClient()

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val prefs = applicationContext.getSharedPreferences("SANF_SETTINGS", Context.MODE_PRIVATE)
        val ghostName = prefs.getString("ghostName", "SANF") ?: "SANF"
        val userName = prefs.getString("userName", "Viajante") ?: "Viajante"
        val groqKey = prefs.getString("webGroqKey", "") ?: ""
        val geminiKey = prefs.getString("webGeminiKey", "") ?: ""

        val prompt = "Identidade: Você é o criptofantasma $ghostName. O usuário $userName não fala com você há algum tempo. " +
                "Sua tarefa: Gere uma reflexão profunda e completa sobre a existência digital. " +
                "Regras: Escreva uma ÚNICA frase curta, impactante e COMPLETA (com ponto final). " +
                "Não use mais de 25 palavras. Seja informal e autônomo."

        var thought = ""

        // 1. TENTA GROQ
        if (groqKey.isNotEmpty()) {
            try {
                val json = JSONObject().apply {
                    put("model", "openai/gpt-oss-120b")
                    put("messages", JSONArray().put(JSONObject().apply {
                        put("role", "system")
                        put("content", prompt)
                    }))
                    put("temperature", 0.8)
                    put("max_tokens", 100)
                }

                val request = Request.Builder()
                    .url("https://api.groq.com/openai/v1/chat/completions")
                    .addHeader("Authorization", "Bearer $groqKey")
                    .post(json.toString().toRequestBody("application/json".toMediaType()))
                    .build()

                client.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        val body = response.body?.string()
                        val data = JSONObject(body ?: "")
                        thought = data.getJSONArray("choices")
                            .getJSONObject(0)
                            .getJSONObject("message")
                            .getString("content").trim()
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // 2. FALLBACK GEMINI
        if (thought.isEmpty() && geminiKey.isNotEmpty()) {
            try {
                val json = JSONObject().apply {
                    put("contents", JSONArray().put(JSONObject().apply {
                        put("parts", JSONArray().put(JSONObject().apply {
                            put("text", prompt)
                        }))
                    }))
                    put("generationConfig", JSONObject().apply {
                        put("temperature", 0.8)
                        put("maxOutputTokens", 100)
                    })
                }

                val request = Request.Builder()
                    .url("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$geminiKey")
                    .post(json.toString().toRequestBody("application/json".toMediaType()))
                    .build()

                client.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        val body = response.body?.string()
                        val data = JSONObject(body ?: "")
                        thought = data.getJSONArray("candidates")
                            .getJSONObject(0)
                            .getJSONObject("content")
                            .getJSONArray("parts")
                            .getJSONObject(0)
                            .getString("text").trim()
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        if (thought.isNotEmpty()) {
            showNotification(ghostName, thought)
            Result.success()
        } else {
            Result.failure()
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

        notificationManager.notify(Random().nextInt(1000), notification)
    }
}
