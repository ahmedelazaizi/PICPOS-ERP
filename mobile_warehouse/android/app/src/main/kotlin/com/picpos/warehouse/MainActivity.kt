package com.picpos.warehouse

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Bluetooth runtime permission for label printing (WH-015). Only
/// BLUETOOTH_CONNECT is asked (paired printers; no discovery, no location);
/// below Android 12 the legacy permissions are install-time.
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(if (granted()) "granted" else "denied")
                "request" -> request(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun granted(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun request(result: MethodChannel.Result) {
        if (granted()) return result.success("granted")
        if (pending != null) return result.success("denied")
        pending = result
        requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_CODE) return
        val result = pending ?: return
        pending = null
        result.success(
            when {
                granted() -> "granted"
                // Denied and the system will not show the prompt again.
                !shouldShowRequestPermissionRationale(Manifest.permission.BLUETOOTH_CONNECT) -> "blocked"
                else -> "denied"
            }
        )
    }

    companion object {
        const val CHANNEL = "com.picpos.warehouse/bluetooth_permission"
        const val REQUEST_CODE = 7341
    }
}