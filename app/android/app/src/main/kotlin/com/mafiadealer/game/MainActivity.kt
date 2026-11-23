package com.mafiadealer.game

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "mafia/keep": start / stop the service that keeps a hosted Wi-Fi room alive (KeepService)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mafia/keep").setMethodCallHandler { call, result ->
            val intent = Intent(this, KeepService::class.java)
            when (call.method) {
                "start" -> {
                    intent.putExtra("title", call.argument<String>("title")).putExtra("text", call.argument<String>("text"))
                    if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                    result.success(true)
                }
                "stop" -> { stopService(intent); result.success(true) }
                else -> result.notImplemented()
            }
        }
    }
}
