# OAgents — keep rules untuk plugin native bridge.

# org.json (bundel Android) dipakai intensif lewat refleksi nama field oleh
# Flutter method channel (JSONObject pada platform thread); jangan di-strip.
-keep class org.json.** { *; }

# Plugin OAgents: method channel handler dipanggil refleksi dari Flutter engine.
-keep class com.glimmora.oagents.** {
    public *;
    private *;
}

# Flutter embedding (sudah ada keep bawaan, tetap dipertahankan).
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }

# Kotlin stdlib & kotlin.Metadata — aman default, tapi pastikan tidak
# dihapus untuk MethodChannel result callback anonim.
-keepclassmembers class com.glimmora.oagents.RuntimePlugin* {
    <methods>;
}
-keepclassmembers class com.glimmora.oagents.HttpProxyPlugin* {
    <methods>;
}
-keepclassmembers class com.glimmora.oagents.MainActivity* {
    <methods>;
}

# Jangan mengubah nama native lib proot (RuntimePlugin membaca
# applicationInfo.nativeLibraryDir/libproot.so).
-keep native **.so
