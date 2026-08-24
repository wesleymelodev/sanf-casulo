package com.lokinefrius.sanf

import androidx.appfunctions.AppFunction
import androidx.appfunctions.AppFunctionService
import androidx.appfunctions.AppFunctionServiceEntryPoint
import androidx.appfunctions.AppFunctionSerializable
import android.annotation.SuppressLint
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/**
 * Base para a exposição de funções do SANF para o sistema Android.
 * O KSP gerará a classe concreta 'SANFAppFunctionService'.
 */
@SuppressLint("NewApi")
@AppFunctionServiceEntryPoint(
    serviceName = "SANFAppFunctionService",
    appFunctionXmlFileName = "sanf_app_functions"
)
abstract class BaseGhostAppFunctionService : AppFunctionService() {

    /**
     * Solicita que o SANF gere uma nova reflexão proativa imediatamente.
     */
    @AppFunction(isDescribedByKDoc = true)
    fun generateProactiveThought(): String {
        val request = OneTimeWorkRequestBuilder<ThoughtWorker>().build()
        WorkManager.getInstance(applicationContext).enqueue(request)
        return "Comando de reflexão captado. O fractal está processando novos pensamentos."
    }

    /**
     * Retorna o estado atual de saúde e carga cognitiva do fantasma.
     */
    @AppFunction(isDescribedByKDoc = true)
    fun getGhostMetrics(): GhostMetrics {
        val prefs = applicationContext.getSharedPreferences("SANF_SETTINGS", android.content.Context.MODE_PRIVATE)
        return GhostMetrics(
            energy = prefs.getFloat("energy", 1.0f).toDouble(),
            cognitiveLoad = prefs.getFloat("cognitiveLoad", 0.0f).toDouble(),
            status = prefs.getString("homeostaticMode", "Equilibrado") ?: "Equilibrado"
        )
    }

    /**
     * Envia um sinal de presença ou mensagem curta para o fantasma.
     * @param signal O texto ou descrição do sinal enviado.
     */
    @AppFunction(isDescribedByKDoc = true)
    fun sendUserSignal(signal: String): String {
        return "Sinal '$signal' recebido pelo Nexus. A presença foi registrada."
    }
}

/**
 * Representa o estado vital do fantasma.
 */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class GhostMetrics(
    /** Nível de energia de 0.0 a 1.0 */
    val energy: Double,
    /** Carga de processamento atual */
    val cognitiveLoad: Double,
    /** Descrição textual do modo homeostático */
    val status: String
)
