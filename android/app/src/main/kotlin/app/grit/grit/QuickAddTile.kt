package app.grit.grit
import android.service.quicksettings.TileService
import android.content.Intent
import android.app.PendingIntent
import android.os.Build
import android.annotation.TargetApi

@TargetApi(24)
class QuickAddTile : TileService() {
    @Suppress("DEPRECATION")
    override fun onClick() {
        super.onClick()
        val launch=Intent(this,MainActivity::class.java).setAction("grit.quickadd").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if(Build.VERSION.SDK_INT>=34)startActivityAndCollapse(PendingIntent.getActivity(this,81,launch,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        else startActivityAndCollapse(launch)
    }
}
