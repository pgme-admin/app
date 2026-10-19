package com.pgme.app

import android.app.ActivityManager
import android.content.Context
import android.os.Bundle
import android.os.Debug
import android.os.Environment
import android.os.StatFs
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val STORAGE_CHANNEL = "com.pgme.app/storage_info"
    private val MEMORY_CHANNEL = "com.pgme.app/memory_info"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block screenshots and screen recording for this activity.
        //
        // Applied here rather than only from Dart because onCreate runs on
        // every activity recreation (rotation, config change), whereas Dart
        // main() runs once per process — without this the window would be
        // unprotected for the first frames after a recreation.
        //
        // BuildConfig.ALLOW_SCREEN_CAPTURE is false unless the build set
        // PGME_ALLOW_SCREEN_CAPTURE=true; see app/build.gradle.kts.
        if (!BuildConfig.ALLOW_SCREEN_CAPTURE) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        }
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEMORY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getHeapInfo" -> result.success(getHeapInfo())
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

    /// Returns a snapshot of this process's memory state.
    /// All sizes in bytes — Dart side converts to MB for display.
    ///
    /// - dartHeapMaxBytes / dartHeapUsedBytes: the JVM (Dalvik) heap that
    ///   holds Java/Kotlin allocations. This is the cap that triggers OOM.
    /// - nativeHeapAllocatedBytes: malloc'd memory (decoded video frames,
    ///   loaded PDF buffers, image bitmaps). Counts against process RSS but
    ///   not against the JVM heap cap.
    /// - memoryClassMb / largeMemoryClassMb: Android's nominal per-app heap
    ///   class for this device. largeMemoryClass applies because the manifest
    ///   sets android:largeHeap="true".
    /// - isLowMemory: system-reported low-memory state.
    private fun getHeapInfo(): Map<String, Any> {
        val runtime = Runtime.getRuntime()
        val maxBytes = runtime.maxMemory()
        val totalBytes = runtime.totalMemory()
        val freeBytes = runtime.freeMemory()
        val usedBytes = totalBytes - freeBytes

        val nativeAllocated = Debug.getNativeHeapAllocatedSize()
        val nativeSize = Debug.getNativeHeapSize()

        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        am.getMemoryInfo(memInfo)

        return mapOf(
            "dartHeapMaxBytes" to maxBytes,
            "dartHeapUsedBytes" to usedBytes,
            "dartHeapTotalBytes" to totalBytes,
            "nativeHeapAllocatedBytes" to nativeAllocated,
            "nativeHeapSizeBytes" to nativeSize,
            "memoryClassMb" to am.memoryClass,
            "largeMemoryClassMb" to am.largeMemoryClass,
            "systemAvailMemBytes" to memInfo.availMem,
            "systemTotalMemBytes" to memInfo.totalMem,
            "systemThresholdBytes" to memInfo.threshold,
            "isLowMemory" to memInfo.lowMemory
        )
    }
}
