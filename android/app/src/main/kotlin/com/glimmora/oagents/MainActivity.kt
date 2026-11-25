package com.glimmora.oagents

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Activity utama OAgents.
 * Hanya mendaftarkan plugin native bridge; seluruh UI ada di sisi Flutter/Dart.
 * Tanpa Toast/Snackbar native — status ditampilkan Dart via channel.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // HttpProxyPlugin mendaftar TERAKHIR pada channel oagents/runtime:
        // ia meng-handle httpProxy dan melimpahkan metode lain ke RuntimePlugin.
        val runtime = RuntimePlugin(applicationContext)
        runtime.register(flutterEngine)
        HttpProxyPlugin(applicationContext, runtime).register(flutterEngine)
    }
}
