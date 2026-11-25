package com.glimmora.oagents

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * HttpProxyPlugin — meneruskan permintaan HTTP Dart ke server opencode lokal.
 *
 * MethodChannel yang dipakai SAMA dengan RuntimePlugin (`oagents/runtime`,
 * metode `httpProxy`) supaya Dart hanya mengenal satu channel. Plugin ini
 * meng-handle metode `httpProxy` dan melimpahkan semua metode lain ke
 * RuntimePlugin (chain handler); hanya ada satu handler aktif per channel
 * sehingga tidak saling menimpa.
 *
 * Tidak ada UI; tidak ada Toast/Snackbar (kontrak BRIDGE_CONTRACT.md).
 * Target hanya 127.0.0.1 — Dart tidak pernah membuka soket lokal sendiri.
 */
class HttpProxyPlugin(
    private val context: Context,
    private val runtime: RuntimePlugin
) {

    companion object {
        const val METHOD_CHANNEL = RuntimePlugin.METHOD_CHANNEL
        const val TAG = "OAgents"
        const val METHOD_HTTP_PROXY = "httpProxy"
    }

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(::onMethodCall)
        Log.i(TAG, "HttpProxyPlugin registered pada channel $METHOD_CHANNEL (metode $METHOD_HTTP_PROXY)")
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_HTTP_PROXY -> {
                // {method, path, body, headers} -> {status, body}
                runtime.httpProxy(call.arguments, result)
            }
            else -> {
                // Metode lain tetap ditangani RuntimePlugin (channel yang sama).
                runtime.handleMethodCall(call, result)
            }
        }
    }

    /** Alternatif non-channel untuk pemanggilan internal Kotlin. */
    fun proxy(arg: JSONObject): JSONObject = runtime.httpProxyJson(arg.toString())
}
