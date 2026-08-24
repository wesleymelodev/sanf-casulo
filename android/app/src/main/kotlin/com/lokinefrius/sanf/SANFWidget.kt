package com.lokinefrius.sanf

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import android.graphics.Color
import com.lokinefrius.sanf.R

class SANFWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val prefs = context.getSharedPreferences("SANF_SETTINGS", Context.MODE_PRIVATE)
            val eyeColorHex = prefs.getString("eyeColor", "#00FFFF") ?: "#00FFFF"
            
            val views = RemoteViews(context.packageName, R.layout.sanf_widget)
            try {
                views.setInt(R.id.widget_eye, "setColorFilter", Color.parseColor(eyeColorHex))
            } catch (e: Exception) {
                // Fallback safe
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
