package com.glimmora.oagents

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Callable
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Bridge native OAgents.
 *
 * MethodChannel : oagents/runtime  (rootfsStatus, installRootfs, startServer,
 *                                   stopServer, serverStatus, execInRootfs, httpProxy)
 * EventChannel  : oagents/progress ({stage, pct, detail})
 *
 * Kontrak: docs/BRIDGE_CONTRACT.md
 *  - Semua argumen & hasil JSON (org.json bundel Android).
 *  - Port hanya 127.0.0.1, tidak pernah 0.0.0.0.
 *  - Tidak ada UI / Toast / Snackbar; status inline ditangani Dart.
 *  - workDir aplikasi di-bind sebagai /work di dalam proot.
 */
class RuntimePlugin(private val context: Context) {

    companion object {
        const val METHOD_CHANNEL = "oagents/runtime"
        const val PROGRESS_CHANNEL = "oagents/progress"
        const val TAG = "OAgents"
        const val LOOPBACK = "127.0.0.1"
        const val ROOTFS_DIR_NAME = "rootfs"
        const val OPENCODE_RELATIVE_PATH = "bin/opencode"
        const val PROOT_LIBRARY = "libproot.so"
        const val MAX_AUTO_RESTARTS = 3
        const val HTTP_TIMEOUT_MS = 15_000
        private const val READ_CHUNK = 16 * 1024
        private const val BUFFER_SIZE = 64 * 1024

        /**
         * PID dari [Process], portabel lintas level API: java.lang.Process.pid()
         * hanya backport runtime di Android 14+ dan tidak ada di android.jar
         * publik, jadi baca lewat reflection; -1 bila tidak tersedia.
         */
        fun pidOf(p: Process): Long {
            return try {
                val m = Process::class.java.getMethod("pid")
                (m.invoke(p) as Number).toLong()
            } catch (t: Throwable) {
                -1L
            }
        }
    }

    // --- State server ------------------------------------------------------
    private var process: Process? = null
    private var serverPort: Int = -1
    private var startedAtMs: Long = 0L
    private var pid: Int = -1
    private val executor: ExecutorService = Executors.newCachedThreadPool { r ->
        Thread(r, "oagents-runtime").apply { isDaemon = true }
    }
    private val watcherStop = AtomicBoolean(false)
    private var restartCount = 0
    private val generation = AtomicLong(0)
    private var progressSink: EventChannel.EventSink? = null

    // --- Registrasi --------------------------------------------------------
    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(::handleMethodCall)
        EventChannel(engine.dartExecutor.binaryMessenger, PROGRESS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    progressSink = events
                }

                override fun onCancel(args: Any?) {
                    progressSink = null
                }
            })
        Log.i(TAG, "RuntimePlugin registered ($METHOD_CHANNEL, $PROGRESS_CHANNEL)")
    }

    /**
     * Handler publik: HttpProxyPlugin mendaftar di channel yang sama dan
     * melimpahkan metode non-httpProxy kembali ke sini (chain-of-responsibility),
     * sehingga hanya ada satu handler aktif per channel.
     */
    fun handleMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "rootfsStatus" -> result.success(rootfsStatus())
            "installRootfs" -> executor.execute { installRootfs(call.arguments, result) }
            "startServer" -> executor.execute { startServer(call.arguments, result) }
            "stopServer" -> executor.execute { stopServer(result) }
            "serverStatus" -> executor.execute { serverStatus(result) }
            "execInRootfs" -> executor.execute { execInRootfs(call.arguments, result) }
            "httpProxy" -> executor.execute { httpProxy(call.arguments, result) }
            else -> result.notImplemented()
        }
    }

    // --- Helper JSON -------------------------------------------------------
    private fun okError(t: Throwable): JSONObject =
        JSONObject().put("ok", false).put("error", t.message ?: t.javaClass.simpleName)

    private fun ok(): JSONObject = JSONObject().put("ok", true)

    private fun emitProgress(stage: String, pct: Int, detail: String) {
        val event = JSONObject()
            .put("stage", stage)
            .put("pct", pct.coerceIn(0, 100))
            .put("detail", detail)
        Log.d(TAG, "progress $stage $pct% — $detail")
        try {
            progressSink?.success(event.toString())
        } catch (t: Throwable) {
            Log.w(TAG, "gagal emit progress: ${t.message}")
        }
    }

    // --- HTTP util ---------------------------------------------------------
    private fun newConnection(url: String): HttpURLConnection =
        URL(url).openConnection() as HttpURLConnection

    private fun readBody(connection: HttpURLConnection): String = try {
        val stream = if (connection.responseCode >= 400) connection.errorStream else connection.inputStream
        stream?.use { input ->
            val out = java.io.ByteArrayOutputStream()
            val buf = ByteArray(READ_CHUNK)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                out.write(buf, 0, n)
            }
            out.toString("UTF-8")
        } ?: ""
    } catch (t: Throwable) {
        ""
    }


    // --- rootfsStatus ------------------------------------------------------
    private fun rootfsStatus(): JSONObject = try {
        val rootfs = File(context.filesDir, ROOTFS_DIR_NAME)
        val opencode = File(rootfs, OPENCODE_RELATIVE_PATH)
        val versionFile = File(rootfs, "opencode.version")
        val installed = opencode.exists() && opencode.canExecute() && rootfs.isDirectory
        val version = if (versionFile.isFile) versionFile.readText().trim() else ""
        JSONObject()
            .put("installed", installed)
            .put("version", version)
            .put("sizeMB", if (rootfs.isDirectory) dirSize(rootfs) / (1024.0 * 1024.0) else 0.0)
            .put("ok", installed)
    } catch (t: Throwable) {
        okError(t)
    }

    private fun dirSize(dir: File): Long {
        var total = 0L
        val children = dir.listFiles() ?: return 0
        for (child in children) total += if (child.isDirectory) dirSize(child) else child.length()
        return total
    }

    // --- installRootfs -----------------------------------------------------
    // arg: {rootfsUrl, opencodeUrl, version}
    // stage: downloading(0-100) -> verifying(100) -> extracting(0-100) -> installing(100)
    // hasil akhir sebagai balasan method: {ok, stage, detail} — sesuai kontrak,
    // event progress dipancarkan selama proses berjalan.
    private fun installRootfs(arg: Any?, result: MethodChannel.Result) {
        try {
            val args = arg?.let { JSONObject(arg.toString()) } ?: JSONObject()
            val rootfsUrl = args.optString("rootfsUrl")
            val opencodeUrl = args.optString("opencodeUrl")
            val version = args.optString("version", "")
            if (rootfsUrl.isEmpty() || opencodeUrl.isEmpty()) {
                result.success(JSONObject()
                    .put("ok", false)
                    .put("stage", "downloading")
                    .put("detail", "argumen rootfsUrl/opencodeUrl kosong")
                    .toString())
                return
            }

            val rootfs = File(context.filesDir, ROOTFS_DIR_NAME)
            if (rootfs.exists()) deleteRecursively(rootfs)
            if (!rootfs.mkdirs()) throw IOException("gagal membuat ${rootfs.path}")

            // 1) Unduh rootfs Alpine + biner opencode (progress dibagi dua).
            emitProgress("downloading", 0, "mengunduh rootfs $rootfsUrl")
            val rootfsTar = File(rootfs.parentFile, "rootfs-download.tar.gz")
            downloadToFile(rootfsUrl, rootfsTar) { pct ->
                // 0-45 untuk rootfs, sisanya untuk opencode.
                emitProgress("downloading", pct / 2, "rootfs ${pct}%")
            }

            emitProgress("downloading", 50, "mengunduh biner opencode $opencodeUrl")
            val opencodeTar = File(rootfs.parentFile, "opencode-download.tgz")
            downloadToFile(opencodeUrl, opencodeTar) { pct ->
                emitProgress("downloading", 50 + pct / 2, "opencode ${pct}%")
            }

            // 2) Verifikasi ukuran (sha256 opsional; rootfs sha256 tersedia via
            //    rootfsUrl + ".sha256" jika mirror menyediakan).
            emitProgress("verifying", 0, "memverifikasi unduhan")
            if (rootfsTar.length() == 0L || opencodeTar.length() == 0L) {
                throw IOException("unduhan kosong (rootfs=${rootfsTar.length()}, opencode=${opencodeTar.length()})")
            }
            emitProgress("verifying", 100, "ukuran unduhan valid")

            // 3) Ekstrak rootfs tar.gz ke filesDir/rootfs.
            emitProgress("extracting", 0, "mengekstrak rootfs tar.gz")
            extractTarGz(rootfsTar, rootfs) { pct ->
                emitProgress("extracting", pct, "ekstraksi rootfs ${pct}%")
            }

            // 4) Pasang biner opencode ke rootfs/bin/opencode.
            emitProgress("installing", 0, "memasang biner opencode")
            val binDir = File(rootfs, "bin")
            if (!binDir.isDirectory && !binDir.mkdirs()) throw IOException("gagal membuat ${binDir.path}")
            val opencode = File(binDir, "opencode")
            extractSingleFileTar(opencodeTar, opencode)
            if (!opencode.setExecutable(true, false)) Log.w(TAG, "chmod +x gagal untuk ${opencode.path}")

            val versionFile = File(rootfs, "opencode.version")
            versionFile.writeText(version)

            rootfsTar.delete()
            opencodeTar.delete()

            emitProgress("installing", 100, "rootfs siap: ${dirSize(rootfs) / (1024 * 1024)} MB")
            result.success(JSONObject()
                .put("ok", true)
                .put("stage", "installing")
                .put("detail", "rootfs ${version} terpasang (${dirSize(rootfs) / (1024 * 1024)} MB)")
                .toString())
        } catch (t: Throwable) {
            Log.e(TAG, "installRootfs gagal", t)
            result.success(JSONObject()
                .put("ok", false)
                .put("stage", "installing")
                .put("detail", t.message ?: t.javaClass.simpleName)
                .toString())
        }
    }

    private fun downloadToFile(url: String, target: File, onProgress: (Int) -> Unit) {
        val connection = newConnection(url)
        connection.connectTimeout = HTTP_TIMEOUT_MS
        connection.readTimeout = 60_000
        connection.instanceFollowRedirects = true
        val status = connection.responseCode
        if (status !in 200..299) {
            connection.disconnect()
            throw IOException("HTTP $status saat mengunduh $url")
        }
        val total = connection.contentLengthLong // bisa -1 jika server tidak kirim length
        try {
            connection.inputStream.use { input ->
                FileOutputStream(target).use { out ->
                    val buf = ByteArray(BUFFER_SIZE)
                    var downloaded = 0L
                    var lastPct = -1
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        downloaded += n
                        if (total > 0) {
                            val pct = (downloaded * 100 / total).toInt().coerceIn(0, 100)
                            if (pct != lastPct) {
                                lastPct = pct
                                onProgress(pct)
                            }
                        } else if (downloaded % (5 * 1024 * 1024) < READ_CHUNK) {
                            // server tanpa content-length: progress per ~5MB
                            onProgress(minOf(90, (downloaded / (50 * 1024 * 1024)).toInt() * 10))
                        }
                    }
                }
            }
            onProgress(100)
        } finally {
            connection.disconnect()
        }
    }

    /** Ekstraksi tar.gz dengan GZIPInputStream + parser tar manual (stdlib + java.util.zip). */
    private fun extractTarGz(tarFile: File, destDir: File, onProgress: (Int) -> Unit) {
        val total = tarFile.length().toDouble()
        java.util.zip.GZIPInputStream(tarFile.inputStream(), BUFFER_SIZE).use { gz ->
            extractTar(gz, destDir, total, onProgress)
        }
    }

    /** Parser tar stream sederhana (ustar/GNU): header 512 byte + data + padding 512. */
    private fun extractTar(gz: java.io.InputStream, destDir: File, total: Double,
                            onProgress: (Int) -> Unit) {
        val header = ByteArray(512)
        var bytesRead: Long = 0
        while (true) {
            val n = readFully(gz, header)
            if (n < 512) break // EOF
            bytesRead += 512
            if (isAllZero(header)) break // end-of-archive
            var name = trimString(header, 0, 100)
            val sizeStr = trimString(header, 124, 12)
            val size = if (sizeStr.isEmpty()) 0L else parseOctalSafe(sizeStr)
            val typeFlag = header[156].toInt() and 0xFF
            val prefix = trimString(header, 345, 155)

            if (typeFlag == 76) {
                // 'L' GNU longname: blok berikut berisi nama panjang
                val nameBlock = ByteArray(size.toInt())
                readFully(gz, nameBlock)
                bytesRead += pad512(size)
                name = trimZero(nameBlock)
                // baca header berikutnya (entri asli)
                val n2 = readFully(gz, header)
                if (n2 < 512) break
                bytesRead += 512
                val size2 = trimString(header, 124, 12)
                val type2 = header[156].toInt() and 0xFF
                val prefix2 = trimString(header, 345, 155)
                val fsize = if (size2.isEmpty()) 0L else parseOctalSafe(size2)
                val finalName = if (prefix2.isNotEmpty()) "$prefix2/$name" else name
                if (finalName.isNotEmpty()) extractEntry(gz, File(destDir, sanitize(finalName)), fsize, type2)
                bytesRead += pad512(fsize)
            } else {
                val finalName = if (prefix.isNotEmpty()) "$prefix/$name" else name
                if (finalName.isNotEmpty()) {
                    extractEntry(gz, File(destDir, sanitize(finalName)), size, typeFlag)
                } else {
                    skipFully(gz, pad512(size))
                }
                bytesRead += pad512(size)
            }
            if (total > 0) onProgress(((bytesRead * 100 / total).toInt()).coerceIn(0, 99))
        }
        onProgress(100)
    }

    private fun extractEntry(gz: java.io.InputStream, outFile: File, size: Long, typeFlag: Int) {
        if (typeFlag == 53) { // '5' directory
            outFile.mkdirs()
            return
        }
        if (typeFlag == 50 || typeFlag == 0) { // '0'/'\0' file biasa
            outFile.parentFile?.mkdirs()
            FileOutputStream(outFile).use { out ->
                var remaining = size
                val buf = ByteArray(BUFFER_SIZE)
                while (remaining > 0) {
                    val toRead = minOf(buf.size.toLong(), remaining).toInt()
                    val n = gz.read(buf, 0, toRead)
                    if (n < 0) break
                    out.write(buf, 0, n)
                    remaining -= n
                }
            }
            return
        }
        // symlink ('2'), hardlink, fifo, dsb: skip data
        skipFully(gz, pad512(size))
    }

    private fun pad512(size: Long): Long = if (size == 0L) 0L else ((size + 511) / 512) * 512

    private fun readFully(input: java.io.InputStream, buf: ByteArray): Int {
        var off = 0
        while (off < buf.size) {
            val n = input.read(buf, off, buf.size - off)
            if (n < 0) return off
            off += n
        }
        return off
    }

    private fun skipFully(input: java.io.InputStream, count: Long) {
        var remaining = count
        while (remaining > 0) {
            val n = input.skip(remaining)
            if (n <= 0) {
                if (input.read() < 0) return
                remaining -= 1
            } else remaining -= n
        }
    }

    private fun isAllZero(buf: ByteArray): Boolean = buf.all { it == 0.toByte() }

    private fun trimString(buf: ByteArray, off: Int, len: Int): String {
        var end = off
        val hi = minOf(off + len, buf.size)
        while (end < hi && buf[end] != 0.toByte()) end++
        return String(buf, off, end - off, Charsets.UTF_8).trim()
    }

    private fun trimZero(buf: ByteArray): String {
        val end = buf.indexOf(0)
        return String(buf, 0, if (end < 0) buf.size else end, Charsets.UTF_8).trim()
    }

    private fun parseOctalSafe(s: String): Long = try {
        java.lang.Long.parseLong(s.trim().replace(" ", ""), 8)
    } catch (t: Throwable) {
        s.filter { it.isDigit() }.toLongOrNull()?.let {
            // fallback desimal jika header aneh
            it
        } ?: 0L
    }

    /** Hindari path traversal ("../") keluar rootfs. */
    private fun sanitize(name: String): String {
        var out = name.replace('\\', '/')
        while (out.startsWith("/")) out = out.removePrefix("/").removePrefix("/")
        // buang komponen ".." dan "." 
        val parts = out.split('/').filter { it.isNotEmpty() && it != "." && it != ".." }
        return parts.joinToString("/")
    }

    private fun extractSingleFileTar(tarFile: File, target: File) {
        // opencode-linux-arm64-musl.tgz: satu berkas executable di dalam tar.
        java.util.zip.GZIPInputStream(tarFile.inputStream(), BUFFER_SIZE).use { gz ->
            val header = ByteArray(512)
            while (true) {
                val n = readFully(gz, header)
                if (n < 512) return
                if (isAllZero(header)) return
                var name = trimString(header, 0, 100)
                val sizeStr = trimString(header, 124, 12)
                var size = if (sizeStr.isEmpty()) 0L else parseOctalSafe(sizeStr)
                val typeFlag = header[156].toInt() and 0xFF
                if (typeFlag == 76) { // GNU longname: blok berikutnya berisi nama panjang
                    val nameBlock = ByteArray(size.toInt())
                    readFully(gz, nameBlock)
                    skipFully(gz, pad512(size) - size)
                    name = trimZero(nameBlock)
                    // baca header entri asli setelah blok longname
                    val n2 = readFully(gz, header)
                    if (n2 < 512) return
                    val size2 = trimString(header, 124, 12)
                    size = if (size2.isEmpty()) 0L else parseOctalSafe(size2)
                    val type2 = header[156].toInt() and 0xFF
                    if (type2 == 50 || type2 == 0) {
                        writeFileFromStream(gz, target, size)
                        return
                    }
                    skipFully(gz, pad512(size))
                    continue
                }
                if (typeFlag == 50 || typeFlag == 0) {
                    // ambil entri reguler pertama (executable opencode)
                    writeFileFromStream(gz, target, size)
                    return
                }
                skipFully(gz, pad512(size))
            }
        }
    }

    private fun writeFileFromStream(input: java.io.InputStream, target: File, size: Long) {
        target.parentFile?.mkdirs()
        FileOutputStream(target).use { out ->
            var remaining = size
            val buf = ByteArray(BUFFER_SIZE)
            while (remaining > 0) {
                val toRead = minOf(buf.size.toLong(), remaining).toInt()
                val n = input.read(buf, 0, toRead)
                if (n < 0) break
                out.write(buf, 0, n)
                remaining -= n
            }
        }
    }

    private fun deleteRecursively(file: File) {
        val children = file.listFiles() ?: arrayOf()
        for (child in children) deleteRecursively(child)
        file.delete()
    }

    // --- proot helpers ------------------------------------------------------
    private fun prootBinary(): File? {
        val nativeDir = context.applicationInfo.nativeLibraryDir
        val proot = File(nativeDir, PROOT_LIBRARY)
        if (!proot.exists()) {
            Log.w(TAG, "$proot tidak ditemukan — jniLibs arm64-v8a belum dibundel")
            return null
        }
        return proot
    }

    private fun rootfsDir(): File = File(context.filesDir, ROOTFS_DIR_NAME)

    private fun opencodeBinary(): File = File(rootfsDir(), OPENCODE_RELATIVE_PATH)

    // --- startServer -------------------------------------------------------
    // arg: {port, env:{K1:V1,...}, workDir}
    // Menjalankan: proot -R <rootfs> -b <workDir>:/work /bin/opencode serve
    //              --port <port> --hostname 127.0.0.1
    private fun startServer(arg: Any?, result: MethodChannel.Result) {
        try {
            val args = arg?.let { JSONObject(arg.toString()) } ?: JSONObject()
            val port = args.optInt("port", 4096)
            if (port <= 0 || port > 65535) throw IllegalArgumentException("port tidak valid: $port")
            val workDirPath = args.optString("workDir")
            val envJson = args.optJSONObject("env") ?: JSONObject()

            val proot = prootBinary()
                ?: throw IllegalStateException("libproot.so belum ada di nativeLibraryDir (build CI build-proot)")
            val rootfs = rootfsDir()
            val opencode = opencodeBinary()
            if (!opencode.exists() || !opencode.canExecute()) {
                throw IllegalStateException("rootfs/opencode belum terpasang — panggil installRootfs dulu")
            }
            val workDir = if (workDirPath.isEmpty()) context.filesDir else File(workDirPath)
            if (!workDir.isDirectory) throw IllegalArgumentException("workDir tidak ada: $workDir")

            stopInternal(killForcibly = false)

            val cmd = mutableListOf(
                proot.absolutePath,
                "-R", rootfs.absolutePath,
                "-b", "${workDir.absolutePath}:/work",
                "/bin/opencode",
                "serve",
                "--port", port.toString(),
                "--hostname", LOOPBACK
            )
            Log.i(TAG, "startServer: ${cmd.joinToString(" ")}")

            val pb = ProcessBuilder(cmd).apply {
                redirectErrorStream(false)
                environment().apply {
                    put("HOME", "/root")
                    put("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
                    put("TERM", "xterm-256color")
                    put("PROOT_NO_SECCOMP", "1")
                }
                // Suntik env dari arg (kredensial dsb) ke dalam proses.
                val keys = envJson.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    environment()[k] = envJson.optString(k)
                }
            }

            val p = pb.start()
            process = p
            serverPort = port
            startedAtMs = System.currentTimeMillis()
            pid = pidOf(p).toInt()
            restartCount = 0
            watcherStop.set(false)

            // Salurkan log opencode ke logcat (debuggability tanpa UI).
            executor.execute {
                try {
                    p.inputStream.bufferedReader().forEachLine { Log.i(TAG, "opencode: $it") }
                } catch (ignored: Throwable) {
                }
            }
            executor.execute {
                try {
                    p.errorStream.bufferedReader().forEachLine { Log.w(TAG, "opencode-err: $it") }
                } catch (ignored: Throwable) {
                }
            }

            startWatcher()

            result.success(JSONObject()
                .put("ok", true)
                .put("pid", pid)
                .put("port", port)
                .toString())
        } catch (t: Throwable) {
            Log.e(TAG, "startServer gagal", t)
            result.success(okError(t).toString())
        }
    }

    /** Awasi proses; jika mati tak disengaja, restart otomatis maks 3x dengan event "booting". */
    private fun startWatcher() {
        val myGeneration = generation.incrementAndGet()
        Thread({
            while (!watcherStop.get()) {
                val p = process ?: return@Thread
                try {
                    p.waitFor()
                } catch (ignored: Throwable) {
                }
                if (watcherStop.get()) return@Thread
                if (generation.get() != myGeneration) return@Thread
                // mati tak disengaja (bukan dari stopServer)
                if (restartCount < MAX_AUTO_RESTARTS) {
                    restartCount++
                    Log.w(TAG, "server mati tak disengaja — restart #${restartCount}/${MAX_AUTO_RESTARTS}")
                    emitProgress("booting", 0, "server mati tak disengaja, restart #$restartCount")
                    try {
                        val cmd = mutableListOf(
                            prootBinary()?.absolutePath ?: return@Thread,
                            "-R", rootfsDir().absolutePath,
                            "-b", "${context.filesDir.absolutePath}:/work",
                            "/bin/opencode", "serve",
                            "--port", serverPort.toString(),
                            "--hostname", LOOPBACK
                        )
                        val pb = ProcessBuilder(cmd)
                        pb.environment().put("PROOT_NO_SECCOMP", "1")
                        pb.environment().put("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
                        val p2 = pb.start()
                        process = p2
                        pid = pidOf(p2).toInt()
                        startedAtMs = System.currentTimeMillis()
                        emitProgress("booting", 100, "server dinyalakan ulang (pid $pid)")
                        executor.execute {
                            try {
                                p2.inputStream.bufferedReader().forEachLine { Log.i(TAG, "opencode: $it") }
                            } catch (ignored: Throwable) {
                            }
                        }
                        executor.execute {
                            try {
                                p2.errorStream.bufferedReader().forEachLine { Log.w(TAG, "opencode-err: $it") }
                            } catch (ignored: Throwable) {
                            }
                        }
                    } catch (t: Throwable) {
                        Log.e(TAG, "restart gagal", t)
                        emitProgress("booting", 0, "restart gagal: ${t.message}")
                        return@Thread
                    }
                } else {
                    Log.e(TAG, "restart maksimum tercapai ($MAX_AUTO_RESTARTS) — berhenti")
                    emitProgress("booting", 0, "restart maksimum tercapai, server dibiarkan mati")
                    return@Thread
                }
            }
        }, "oagents-watcher").apply {
            isDaemon = true
            start()
        }
    }
    // --- stopServer ---------------------------------------------------------
    private fun stopInternal(killForcibly: Boolean) {
        watcherStop.set(true)
        generation.incrementAndGet() // membatalkan watcher lama
        val p = process
        process = null
        if (p != null) {
            try {
                // Destroy process tree: proot + anak-anaknya.
                // Android tidak punya Process.destroyForcibly untuk tree, jadi
                // SIGKILL group via kill -9 -PID bila tersedia, lalu destroy().
                val pidToKill = pidOf(p)
                try {
                    val killer = ProcessBuilder("sh", "-c", "kill -TERM -${pidToKill} 2>/dev/null || kill -TERM ${pidToKill}")
                        .start()
                    killer.waitFor(5, TimeUnit.SECONDS)
                } catch (ignored: Throwable) {
                }
                Thread.sleep(300)
                if (p.isAlive) {
                    if (killForcibly) {
                        try {
                            ProcessBuilder("sh", "-c", "kill -9 -${pidToKill} 2>/dev/null || kill -9 ${pidToKill}").start()
                        } catch (ignored: Throwable) {
                        }
                    }
                    p.destroy()
                }
                p.waitFor(3, TimeUnit.SECONDS)
                if (p.isAlive) {
                    p.destroyForcibly()
                    p.waitFor(2, TimeUnit.SECONDS)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "stopServer cleanup: ${t.message}")
            }
        }
    }

    private fun stopServer(result: MethodChannel.Result) {
        try {
            stopInternal(killForcibly = true)
            serverPort = -1
            pid = -1
            startedAtMs = 0L
            result.success(ok().toString())
        } catch (t: Throwable) {
            result.success(okError(t).toString())
        }
    }

    // --- serverStatus -------------------------------------------------------
    private fun serverStatus(result: MethodChannel.Result) {
        try {
            val p = process
            val running = p != null && p.isAlive
            var healthy = false
            var version = ""
            if (running && serverPort > 0) {
                healthy = try {
                    val c = newConnection("http://$LOOPBACK:$serverPort/api/info")
                    c.connectTimeout = 5_000
                    c.readTimeout = 5_000
                    c.requestMethod = "GET"
                    val code = c.responseCode
                    val body = readBody(c)
                    c.disconnect()
                    if (code == 200) {
                        version = try {
                            JSONObject(body).optString("version", "")
                        } catch (ignored: Throwable) { "" }
                        true
                    } else false
                } catch (t: Throwable) {
                    Log.d(TAG, "healthcheck /api/info gagal: ${t.message}")
                    false
                }
            }
            result.success(JSONObject()
                .put("running", running && healthy)
                .put("pid", if (running) pid else -1)
                .put("port", if (serverPort > 0) serverPort else -1)
                .put("upMs", if (running && startedAtMs > 0) System.currentTimeMillis() - startedAtMs else 0)
                .toString())
        } catch (t: Throwable) {
            result.success(okError(t).toString())
        }
    }

    // --- execInRootfs -------------------------------------------------------
    // arg: {cmd, timeoutMs}
    private fun execInRootfs(arg: Any?, result: MethodChannel.Result) {
        try {
            val args = arg?.let { JSONObject(arg.toString()) } ?: JSONObject()
            val cmd = args.optString("cmd")
            if (cmd.isEmpty()) throw IllegalArgumentException("cmd kosong")
            val timeoutMs = args.optLong("timeoutMs", 60_000L)

            val proot = prootBinary()
                ?: throw IllegalStateException("libproot.so belum ada (build CI build-proot)")

            val pb = ProcessBuilder(
                proot.absolutePath,
                "-R", rootfsDir().absolutePath,
                "-b", "${context.filesDir.absolutePath}:/work",
                "/bin/sh", "-c", cmd
            ).apply {
                environment().put("PROOT_NO_SECCOMP", "1")
            }

            val p = pb.start()
            val stdout = StringBuilder()
            val stderr = StringBuilder()
            val tOut = executor.submit {
                p.inputStream.bufferedReader().forEachLine { stdout.appendLine(it) }
            }
            val tErr = executor.submit {
                p.errorStream.bufferedReader().forEachLine { stderr.appendLine(it) }
            }
            var finished = false
            val watcherF = executor.submit(Callable<Boolean> {
                try {
                    p.waitFor()
                    true
                } catch (t: Throwable) {
                    false
                }
            })
            finished = try {
                watcherF.get(timeoutMs, TimeUnit.MILLISECONDS)
            } catch (t: TimeoutException) {
                false
            }
            if (!finished) {
                p.destroyForcibly()
                tOut.cancel(true)
                tErr.cancel(true)
                result.success(JSONObject()
                    .put("ok", false)
                    .put("exitCode", -1)
                    .put("stdout", stdout.toString())
                    .put("stderr", stderr.toString() + "\n[timeout setelah ${timeoutMs}ms]")
                    .toString())
                return
            }
            tOut.get(2, TimeUnit.SECONDS)
            tErr.get(2, TimeUnit.SECONDS)
            val exitCode = try { p.exitValue() } catch (ignored: Throwable) { -1 }
            result.success(JSONObject()
                .put("ok", exitCode == 0)
                .put("exitCode", exitCode)
                .put("stdout", stdout.toString())
                .put("stderr", stderr.toString())
                .toString())
        } catch (t: Throwable) {
            Log.e(TAG, "execInRootfs gagal", t)
            result.success(JSONObject()
                .put("ok", false)
                .put("exitCode", -1)
                .put("stdout", "")
                .put("stderr", t.message ?: t.javaClass.simpleName)
                .toString())
        }
    }

    // --- httpProxy ----------------------------------------------------------
    // arg: {method, path, body, headers}
    // Dipakai juga oleh HttpProxyPlugin (channel sama).
    fun httpProxy(arg: Any?, result: MethodChannel.Result) {
        try {
            val args = arg?.let { JSONObject(arg.toString()) } ?: JSONObject()
            val method = args.optString("method", "GET").uppercase()
            val path = args.optString("path", "/")
            val body = if (args.isNull("body")) null else args.opt("body")
            val headersJson = args.optJSONObject("headers") ?: JSONObject()

            if (serverPort <= 0 || process == null || process?.isAlive != true) {
                result.success(JSONObject()
                    .put("status", 0)
                    .put("body", JSONObject()
                        .put("ok", false)
                        .put("error", "server belum berjalan")
                        .toString())
                    .toString())
                return
            }

            val url = "http://$LOOPBACK:$serverPort${if (path.startsWith("/")) path else "/$path"}"
            val c = newConnection(url)
            c.connectTimeout = HTTP_TIMEOUT_MS
            c.readTimeout = 60_000
            c.requestMethod = method
            val keys = headersJson.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                c.setRequestProperty(k, headersJson.optString(k))
            }
            val bodyStr = when (body) {
                null -> null
                is String -> body
                else -> body.toString() // JSONObject/JSONArray dari Dart
            }
            if (bodyStr != null && method != "GET" && method != "HEAD") {
                c.doOutput = true
                c.setRequestProperty("Content-Type", "application/json")
                c.outputStream.use { it.write(bodyStr.toByteArray(Charsets.UTF_8)) }
            }
            val status = try { c.responseCode } catch (t: Throwable) { throw t }
            val responseBody = readBody(c)
            c.disconnect()
            result.success(JSONObject()
                .put("status", status)
                .put("body", responseBody)
                .toString())
        } catch (t: Throwable) {
            Log.e(TAG, "httpProxy gagal", t)
            result.success(JSONObject()
                .put("status", 0)
                .put("body", JSONObject().put("ok", false).put("error", t.message ?: "httpProxy gagal").toString())
                .toString())
        }
    }

    // dipakai HttpProxyPlugin untuk arahkan ke handler yang sama
    fun httpProxyJson(arg: Any?): JSONObject {
        var json: JSONObject = JSONObject()
        val latch = java.util.concurrent.CountDownLatch(1)
        httpProxy(arg, object : MethodChannel.Result {
            override fun success(res: Any?) {
                json = try { JSONObject(res.toString()) } catch (ignored: Throwable) { JSONObject() }
                latch.countDown()
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                json = JSONObject().put("status", 0).put("body", errorMessage ?: errorCode)
                latch.countDown()
            }

            override fun notImplemented() {
                json = JSONObject().put("status", 0).put("body", "notImplemented")
                latch.countDown()
            }
        })
        latch.await(90, TimeUnit.SECONDS)
        return json
    }

    /** State server untuk dipakai plugin lain (mis. HttpProxyPlugin). */
    fun isServerRunning(): Boolean = process?.isAlive == true && serverPort > 0

    fun currentPort(): Int = serverPort
}
