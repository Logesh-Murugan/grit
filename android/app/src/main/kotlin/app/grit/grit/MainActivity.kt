package app.grit.grit

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.*
import android.content.*
import android.os.Build
import android.provider.OpenableColumns
import android.util.Base64
import android.Manifest
import android.content.pm.PackageManager
import org.json.JSONObject
import org.json.JSONArray

class MainActivity : FlutterActivity() {
    private lateinit var bridge: MethodChannel
    private var pending: MethodChannel.Result? = null
    private var exportBytes: ByteArray? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        bridge = MethodChannel(engine.dartExecutor.binaryMessenger, "grit/platform")
        bridge.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeQuickAdd" -> result.success(takeCapture())
                "updateWidget" -> {
                    val json = JSONArray(call.argument<List<Map<String, Any?>>>("tasks") ?: emptyList<Map<String,Any?>>())
                    if (WidgetState.update(this, call.argument<String>("workspace") ?: "grit.v1.local",
                            call.argument<String>("day") ?: WidgetState.today(), json)) {
                        TodayWidget.refresh(this); result.success(null)
                    } else result.error("widget", "Cannot save widget state", null)
                }
                "widgetCompletions" -> {
                    val queue = WidgetState.read(this).optJSONArray("completions") ?: JSONArray()
                    result.success((0 until queue.length()).map { index ->
                        val entry = queue.getJSONObject(index)
                        entry.keys().asSequence().associateWith { key -> if (entry.isNull(key)) null else entry.get(key) }
                    })
                }
                "ackWidgetCompletions" -> {
                    if (WidgetState.acknowledge(this, call.arguments as? List<String> ?: emptyList())) result.success(null)
                    else result.error("widget", "Cannot acknowledge completion", null)
                }
                "pickAttachment" -> {
                    if (pending != null) {result.error("busy","Another file dialog is open",null);return@setMethodCallHandler}
                    pending=result
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {type="*/*";addCategory(Intent.CATEGORY_OPENABLE)}, 801)
                }
                "saveFile" -> {
                    if(pending!=null){result.error("busy","Another file dialog is open",null);return@setMethodCallHandler}
                    pending=result;exportBytes=call.argument<ByteArray>("bytes")
                    startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {type=call.argument<String>("mime")?:"application/octet-stream";addCategory(Intent.CATEGORY_OPENABLE);putExtra(Intent.EXTRA_TITLE,call.argument<String>("name"))},802)
                }
                "enableQuickAddNotification" -> {
                    if(Build.VERSION.SDK_INT>=33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),803)
                    else showCaptureNotification()
                    result.success(null)
                }
                "disableQuickAddNotification" -> {getSystemService(NotificationManager::class.java).cancel(71);result.success(null)}
                else -> result.notImplemented()
            }
        }
    }
    private fun takeCapture(): String? {
        val text=if(intent.action==Intent.ACTION_SEND) intent.getStringExtra(Intent.EXTRA_TEXT) ?: "" else if(intent.action=="grit.quickadd") "" else null
        if(text!=null) intent.action=Intent.ACTION_MAIN
        return text
    }
    override fun onNewIntent(value: Intent) {
        super.onNewIntent(value);intent=value
        if (value.action == "grit.today" && ::bridge.isInitialized) {
            bridge.invokeMethod("showToday", null)
            intent.action = Intent.ACTION_MAIN
        }
        val text=takeCapture();if(text!=null && ::bridge.isInitialized)bridge.invokeMethod("quickAdd",text)
    }
    @Deprecated("Legacy activity callback used by document picker")
    override fun onActivityResult(requestCode: Int,resultCode: Int,data: Intent?) {
        super.onActivityResult(requestCode,resultCode,data)
        if(requestCode!=801 && requestCode!=802)return
        val result=pending;pending=null
        val uri=data?.data
        if(resultCode!=RESULT_OK || uri==null){result?.success(null);return}
        try {
            if(requestCode==802){val stream=contentResolver.openOutputStream(uri)?:throw IllegalStateException("Cannot save file");stream.use {it.write(exportBytes?:byteArrayOf())};exportBytes=null;result?.success(null);return}
            var name="Attachment"
            contentResolver.query(uri,null,null,null,null)?.use {cursor->if(cursor.moveToFirst()){val idx=cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);if(idx>=0)name=cursor.getString(idx)}}
            val input=contentResolver.openInputStream(uri)?:throw IllegalStateException("Cannot read file")
            val bytes=input.use {
                val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(8192)
                while(out.size()<=1024*1024){val count=it.read(buffer);if(count<0)break;out.write(buffer,0,count)}
                out.toByteArray()
            }
            if(bytes.size>1024*1024)throw IllegalArgumentException("Choose a file up to 1 MB")
            result?.success(mapOf("name" to name,"size" to bytes.size,"mime" to (contentResolver.getType(uri)?:"application/octet-stream"),"data" to Base64.encodeToString(bytes,Base64.NO_WRAP)))
        }catch(e:Exception){result?.error("file",e.message,null)}
    }
    private fun showCaptureNotification() {
        val manager=getSystemService(NotificationManager::class.java)
        val channel="grit_capture"
        if(Build.VERSION.SDK_INT>=26)manager.createNotificationChannel(NotificationChannel(channel,"Quick capture",NotificationManager.IMPORTANCE_LOW))
        val open=PendingIntent.getActivity(this,71,Intent(this,MainActivity::class.java).setAction("grit.quickadd"),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder=if(Build.VERSION.SDK_INT>=26)Notification.Builder(this,channel)else Notification.Builder(this)
        manager.notify(71,builder.setSmallIcon(R.drawable.ic_grit_capture).setContentTitle("Capture a thought").setContentText("Tap to add a GRIT task").setContentIntent(open).setOngoing(true).build())
    }
    override fun onRequestPermissionsResult(code:Int,permissions:Array<out String>,results:IntArray){
        super.onRequestPermissionsResult(code,permissions,results)
        if(code==803 && results.firstOrNull()==PackageManager.PERMISSION_GRANTED)showCaptureNotification()
    }
}
