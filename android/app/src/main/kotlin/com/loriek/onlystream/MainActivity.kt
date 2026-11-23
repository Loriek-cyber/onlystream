package com.loriek.onlystream

import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.loriek.onlystream/companion"
        private const val COMPANION_PACKAGE = "com.loriek.easystreamserver"
        private const val ACTION_START = "com.loriek.easystreamserver.ACTION_START"
        private const val ACTION_STOP = "com.loriek.easystreamserver.ACTION_STOP"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isInstalled" -> result.success(isCompanionInstalled())
                    "startServer" -> result.success(startCompanionServer())
                    "stopServer" -> result.success(stopCompanionServer())
                    else -> result.notImplemented()
                }
            }
    }

    private fun isCompanionInstalled(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    COMPANION_PACKAGE,
                    PackageManager.PackageInfoFlags.of(0L)
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(COMPANION_PACKAGE, 0)
            }
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        } catch (_: Throwable) {
            false
        }
    }

    private fun queryBroadcastReceiversCompat(intent: Intent): List<ResolveInfo> {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.queryBroadcastReceivers(
                    intent,
                    PackageManager.ResolveInfoFlags.of(0L)
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.queryBroadcastReceivers(intent, 0)
            }
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun startCompanionServer(): Boolean {
        if (!isCompanionInstalled()) return false

        val intent = Intent(ACTION_START).apply {
            setPackage(COMPANION_PACKAGE)
            addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
        }

        if (queryBroadcastReceiversCompat(intent).isNotEmpty()) {
            try {
                sendBroadcast(intent)
                return true
            } catch (_: Throwable) {
                // Fall back to launching the companion activity below.
            }
        }

        return try {
            val launchIntent = packageManager.getLaunchIntentForPackage(COMPANION_PACKAGE)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launchIntent)
                true
            } else {
                false
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun stopCompanionServer(): Boolean {
        if (!isCompanionInstalled()) return false
        return try {
            val intent = Intent(ACTION_STOP).apply {
                setPackage(COMPANION_PACKAGE)
            }
            sendBroadcast(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }
}
