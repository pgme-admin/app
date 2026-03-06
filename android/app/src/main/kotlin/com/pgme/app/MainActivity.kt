package com.pgme.app

import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val STORAGE_CHANNEL = "com.pgme.app/storage_info"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Prevent screenshots and screen recording
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getFreeDiskSpace" -> result.success(getFreeDiskSpaceMB())
                    "getTotalDiskSpace" -> result.success(getTotalDiskSpaceMB())
                    else -> result.notImplemented()
                }
            }
    }

    private fun getFreeDiskSpaceMB(): Double {
        return try {
            val stat = StatFs(Environment.getDataDirectory().path)
            val availableBytes = stat.availableBlocksLong * stat.blockSizeLong
            availableBytes.toDouble() / (1024.0 * 1024.0)
        } catch (e: Exception) {
            -1.0
        }
    }

    private fun getTotalDiskSpaceMB(): Double {
        return try {
            val stat = StatFs(Environment.getDataDirectory().path)
            val totalBytes = stat.blockCountLong * stat.blockSizeLong
            totalBytes.toDouble() / (1024.0 * 1024.0)
        } catch (e: Exception) {
            -1.0
        }
    }
}
