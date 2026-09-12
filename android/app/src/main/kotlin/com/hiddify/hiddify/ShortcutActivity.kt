package com.hiddify.hiddify

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutManager
import android.util.Base64
import android.os.Build
import android.os.Bundle
import androidx.core.content.getSystemService
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.hiddify.hiddify.bg.BoxService
import com.hiddify.hiddify.bg.ServiceConnection
import com.hiddify.hiddify.constant.Status
import java.security.MessageDigest
import java.security.SecureRandom

class ShortcutActivity : Activity(), ServiceConnection.Callback {

    private val connection = ServiceConnection(this, this, false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.action == Intent.ACTION_CREATE_SHORTCUT) {
            setResult(
                RESULT_OK, ShortcutManagerCompat.createShortcutResultIntent(
                    this,
                    ShortcutInfoCompat.Builder(this, "toggle")
                        .setIntent(
                            Intent(
                                this,
                                ShortcutActivity::class.java
                            ).setAction(Intent.ACTION_MAIN)
                                .putExtra(EXTRA_TOKEN, shortcutToken(this))
                        )
                        .setIcon(
                            IconCompat.createWithResource(
                                this,
                                R.mipmap.ic_launcher
                            )
                        )
                        .setShortLabel(getString(R.string.quick_toggle))
                        .build()
                )
            )
            finish()
        } else if (!isFromOurShortcut(intent)) {
            // This activity must stay exported for the launcher to create the
            // shortcut, so any app could otherwise fire a bare ACTION_MAIN at it
            // and silently stop the VPN - dropping the user to an unprotected
            // connection without a prompt. Only intents carrying the secret we
            // embedded in our own shortcut may toggle.
            finish()
            return
        } else {
            connection.connect()
            if (Build.VERSION.SDK_INT >= 25) {
                getSystemService<ShortcutManager>()?.reportShortcutUsed("toggle")
            }
        }
        moveTaskToBack(true)
    }

    private fun isFromOurShortcut(intent: Intent): Boolean {
        val presented = intent.getStringExtra(EXTRA_TOKEN) ?: return false
        // Constant time: this is a bearer secret.
        return MessageDigest.isEqual(
            presented.toByteArray(Charsets.UTF_8),
            shortcutToken(this).toByteArray(Charsets.UTF_8),
        )
    }

    override fun onServiceStatusChanged(status: Status) {
        when (status) {
            Status.Started -> BoxService.stop()
            Status.Stopped -> BoxService.start()
            else -> {}
        }
        finish()
    }

    override fun onDestroy() {
        connection.disconnect()
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_TOKEN = "com.hiddify.hiddify.shortcut.TOKEN"
        private const val PREFS_NAME = "shortcut_auth"
        private const val KEY_TOKEN = "toggle_token"

        /**
         * Per-install secret embedded in the quick-toggle shortcut. It lives in
         * our private SharedPreferences, so other apps cannot read it, and it is
         * generated once so shortcuts keep working across launches.
         */
        private fun shortcutToken(context: Context): String {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.getString(KEY_TOKEN, null)?.let { return it }
            val bytes = ByteArray(32)
            SecureRandom().nextBytes(bytes)
            val token = Base64.encodeToString(bytes, Base64.NO_WRAP or Base64.URL_SAFE)
            prefs.edit().putString(KEY_TOKEN, token).apply()
            return token
        }
    }
}