package app.grit.grit

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.*
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

class TodayWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) { refresh(context) }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: android.os.Bundle) {
        refresh(context)
    }
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == COMPLETE) {
            WidgetState.complete(context, intent.getStringExtra("taskId") ?: return,
                intent.getStringExtra("workspace") ?: return, intent.getStringExtra("scheduled"))
            refresh(context)
        }
    }
    companion object {
        private const val COMPLETE = "app.grit.grit.COMPLETE_WIDGET_TASK"
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, TodayWidget::class.java))
            val state = WidgetState.read(context)
            val current = state.optString("day") == WidgetState.today()
            val tasks = if (current) state.optJSONArray("tasks") ?: JSONArray() else JSONArray()
            for (id in ids) {
                val view = RemoteViews(context.packageName, R.layout.today_widget)
                view.removeAllViews(R.id.widget_rows)
                val options = manager.getAppWidgetOptions(id)
                val limit = if (options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 250) < 240) 2 else 3
                for (i in 0 until minOf(tasks.length(), limit)) {
                    val task = tasks.getJSONObject(i)
                    val row = RemoteViews(context.packageName, R.layout.today_widget_row)
                    row.setTextViewText(R.id.widget_title, task.optString("title"))
                    row.setContentDescription(R.id.widget_complete, "Complete " + task.optString("title"))
                    val action = Intent(context, TodayWidget::class.java).setAction(COMPLETE)
                        .setData(Uri.Builder().scheme("grit").authority("complete").appendPath(state.optString("workspace"))
                            .appendPath(task.optString("id")).appendQueryParameter("scheduled", task.optString("scheduled")).build())
                        .putExtra("taskId", task.optString("id")).putExtra("workspace", state.optString("workspace"))
                        .putExtra("scheduled", if (task.isNull("scheduled")) null else task.optString("scheduled"))
                    row.setOnClickPendingIntent(R.id.widget_complete, PendingIntent.getBroadcast(context, 0, action,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                    view.addView(R.id.widget_rows, row)
                }
                view.setViewVisibility(R.id.widget_empty, if (tasks.length() == 0) View.VISIBLE else View.GONE)
                view.setTextViewText(R.id.widget_empty, if (current) "A little breathing room.\nPlan one thing that matters." else "A fresh start.\nOpen GRIT to update Today.")
                view.setTextViewText(R.id.widget_count, if (tasks.length() > limit) "${tasks.length()} tasks · +${tasks.length() - limit} more in GRIT" else "${tasks.length()} tasks · Today")
                val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java).setAction("grit.today"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val add = PendingIntent.getActivity(context, 1, Intent(context, MainActivity::class.java).setAction("grit.quickadd"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                view.setOnClickPendingIntent(R.id.widget_root, open)
                view.setOnClickPendingIntent(R.id.widget_add, add)
                manager.updateAppWidget(id, view)
            }
        }
    }
}
