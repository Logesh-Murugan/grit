package app.grit.grit

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/** Single-process, durable queue. Never discard an action before Flutter saves it. */
object WidgetState {
    private fun prefs(context: Context) = context.getSharedPreferences("grit_widget", Context.MODE_PRIVATE)
    fun today() = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    @Synchronized fun read(context: Context): JSONObject = try {
        JSONObject(prefs(context).getString("state", "{}") ?: "{}")
    } catch (_: Exception) { JSONObject() }
    @Synchronized fun update(context: Context, workspace: String, day: String, tasks: JSONArray): Boolean {
        val state = read(context)
        val queue = state.optJSONArray("completions") ?: JSONArray()
        val pending = (0 until queue.length()).map { queue.getJSONObject(it) }
        val visible = JSONArray()
        for (i in 0 until tasks.length()) {
            val task = tasks.getJSONObject(i)
            if (pending.none { it.optString("workspace") == workspace &&
                it.optString("taskId") == task.optString("id") &&
                it.opt("scheduled") == task.opt("scheduled") }) visible.put(task)
        }
        state.put("workspace", workspace).put("day", day).put("tasks", visible)
        return prefs(context).edit().putString("state", state.toString()).commit()
    }
    @Synchronized fun complete(context: Context, taskId: String, workspace: String, scheduled: String?): Boolean {
        val state = read(context)
        if (state.optString("workspace") != workspace || state.optString("day") != today()) return false
        val tasks = state.optJSONArray("tasks") ?: JSONArray()
        val task = (0 until tasks.length()).map { tasks.getJSONObject(it) }.firstOrNull {
            it.optString("id") == taskId &&
                (if (it.isNull("scheduled")) null else it.optString("scheduled")) == scheduled
        } ?: return false
        val utc = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        utc.timeZone = TimeZone.getTimeZone("UTC")
        val queue = state.optJSONArray("completions") ?: JSONArray()
        queue.put(JSONObject().put("id", UUID.randomUUID().toString()).put("taskId", taskId)
            .put("workspace", workspace).put("scheduled", task.opt("scheduled") ?: JSONObject.NULL)
            .put("at", utc.format(Date())))
        val remaining = JSONArray()
        for (i in 0 until tasks.length()) if (tasks.getJSONObject(i).optString("id") != taskId) remaining.put(tasks.get(i))
        state.put("tasks", remaining).put("completions", queue)
        return prefs(context).edit().putString("state", state.toString()).commit()
    }
    @Synchronized fun acknowledge(context: Context, ids: List<String>): Boolean {
        val state = read(context)
        val queue = state.optJSONArray("completions") ?: JSONArray()
        val remaining = JSONArray()
        for (i in 0 until queue.length()) if (queue.getJSONObject(i).optString("id") !in ids) remaining.put(queue.get(i))
        state.put("completions", remaining)
        return prefs(context).edit().putString("state", state.toString()).commit()
    }
}
