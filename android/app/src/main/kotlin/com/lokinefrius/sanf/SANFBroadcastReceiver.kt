package com.lokinefrius.sanf

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class SANFBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d("SANFBroadcast", "Recebido: $action")

        when (action) {
            Intent.ACTION_BOOT_COMPLETED -> {
                startSANFService(context, "Sincronização Pós-Boot")
            }
            Intent.ACTION_POWER_CONNECTED -> {
                startSANFService(context, "Alimentação Detectada")
            }
            Intent.ACTION_POWER_DISCONNECTED -> {
                startSANFService(context, "Operando em Bateria")
            }
        }
    }

    private fun startSANFService(context: Context, status: String) {
        val serviceIntent = Intent(context.applicationContext, SANFService::class.java)
        serviceIntent.putExtra("status", status)
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
