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

# Play Core (deferred components / splitinstall): OAgents tidak memakai
# dynamic feature delivery — API ini opsional di embedding, cukup di-dontwarn.
-dontwarn com.google.android.play.core.**

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
# Catatan: file .so di jniLibs tidak diproses R8 sama sekali (R8 hanya
# bekerja pada class Java/Kotlin); packagingOptions jniLibs di
# build.gradle.kts yang menjaga agar libproot.so terbundel utuh.
