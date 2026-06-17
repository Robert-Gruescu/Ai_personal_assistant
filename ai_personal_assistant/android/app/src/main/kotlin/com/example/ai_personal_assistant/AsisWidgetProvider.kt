package com.example.ai_personal_assistant

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent

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

                // Deep-link: tap pe zona stângă (task-uri) / dreaptă (cumpărături)
                // deschide aplicația direct în panoul corespunzător.
                val tasksIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("asis://tasks")
                )
                views.setOnClickPendingIntent(R.id.widget_zone_tasks, tasksIntent)

                val shoppingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("asis://shopping")
                )
                views.setOnClickPendingIntent(R.id.widget_zone_shopping, shoppingIntent)

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}