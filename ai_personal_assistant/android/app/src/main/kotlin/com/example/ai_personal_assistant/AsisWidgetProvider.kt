package com.example.ai_personal_assistant

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

class AsisWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            try {
                val prefs = context.getSharedPreferences(
                    "HomeWidgetPreferences",
                    Context.MODE_PRIVATE
                )

                val views = RemoteViews(context.packageName, R.layout.asis_widget_layout)

                views.setTextViewText(
                    R.id.widget_tasks,
                    prefs.getString("widget_tasks", "Deschide aplicația")
                )
                views.setTextViewText(
                    R.id.widget_shopping,
                    prefs.getString("widget_shopping", "pentru date")
                )
                views.setTextViewText(
                    R.id.widget_updated,
                    prefs.getString("widget_updated", "")
                )

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}