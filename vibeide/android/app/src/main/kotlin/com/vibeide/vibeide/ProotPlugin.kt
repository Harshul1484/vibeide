package com.vibeide.vibeide

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*
import kotlinx.coroutines.delay
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import java.io.File
import java.util.zip.GZIPInputStream

class ProotPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var ctx: Context
    @Volatile private var prootProcess: Process? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ctx = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.vibeide/proot")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isExtracted"      -> result.success(isExtracted())
            "extractAlpine"    -> extractAlpine(result)
            "startSandbox"     -> startSandbox(result)
            "stopSandbox"      -> { prootProcess?.destroy(); prootProcess = null; result.success(true) }
            "isSandboxRunning" -> result.success(prootProcess?.isAlive == true)
            else               -> result.notImplemented()
        }
    }

    private fun alpineDir() = File(ctx.filesDir, "alpine")
    // A marker file written only after a full, successful extraction.
    private fun extractedMarker() = File(alpineDir(), ".extracted")
    private fun isExtracted() = extractedMarker().exists()

    private fun extractAlpine(result: Result) {
        scope.launch {
            try {
                val alpine = alpineDir()
                // Clean any partial/old extraction so we start fresh.
                if (alpine.exists()) alpine.deleteRecursively()
                alpine.mkdirs()

                // Named .dat (not .tar.gz) so aapt/Flutter don't auto-decompress
                // or rename it. The bytes are still a gzip-compressed tarball.
                val alpineAsset = ctx.assets.open("alpine-rootfs.dat")
                var fileCount = 0
                GZIPInputStream(alpineAsset).use { gz ->
                    TarArchiveInputStream(gz).use { tar ->
                        var entry = tar.nextTarEntry
                        while (entry != null) {
                            val out = File(alpine, entry.name)
                            when {
                                entry.isDirectory -> out.mkdirs()
                                entry.isSymbolicLink -> {
                                    // Alpine's rootfs relies heavily on symlinks
                                    // (e.g. /bin/sh -> busybox). Recreate them.
                                    out.parentFile?.mkdirs()
                                    runCatching {
                                        if (out.exists()) out.delete()
                                        android.system.Os.symlink(entry.linkName, out.absolutePath)
                                    }
                                }
                                entry.isLink -> {
                                    // Hard link — point at the already-extracted target.
                                    out.parentFile?.mkdirs()
                                    val target = File(alpine, entry.linkName)
                                    runCatching {
                                        if (out.exists()) out.delete()
                                        android.system.Os.link(target.absolutePath, out.absolutePath)
                                    }.onFailure { target.copyTo(out, overwrite = true) }
                                }
                                else -> {
                                    out.parentFile?.mkdirs()
                                    out.outputStream().use { tar.copyTo(it) }
                                    if (entry.mode and 0b001001001 != 0) out.setExecutable(true, false)
                                    fileCount++
                                }
                            }
                            entry = tar.nextTarEntry
                        }
                    }
                }

                // Alpine needs working DNS — write a resolver config.
                File(alpine, "etc").mkdirs()
                File(alpine, "etc/resolv.conf").writeText("nameserver 8.8.8.8\nnameserver 1.1.1.1\n")

                // Pin apk repositories to the bundled Alpine release (3.21).
                // musl 1.2.5 here exports `statx`, which Claude Code's native
                // build requires (older Alpine 3.19 musl 1.2.4 lacked it).
                File(alpine, "etc/apk").mkdirs()
                File(alpine, "etc/apk/repositories").writeText(
                    "https://dl-cdn.alpinelinux.org/alpine/v3.21/main\n" +
                    "https://dl-cdn.alpinelinux.org/alpine/v3.21/community\n"
                )

                extractedMarker().writeText("files=$fileCount\n")
                android.util.Log.i("VibeProot", "Alpine extracted: $fileCount files")
                withContext(Dispatchers.Main) { if (isActive) result.success(true) }
            } catch (e: Exception) {
                android.util.Log.e("VibeProot", "extract failed", e)
                withContext(Dispatchers.Main) { if (isActive) result.error("EXTRACT_ERR", e.message ?: e.toString(), null) }
            }
        }
    }

    // Android 10+ forbids exec() of files in filesDir (W^X). Executable
    // binaries MUST live in the app's nativeLibraryDir, which is mounted
    // exec-able. We ship proot + vibecli as "lib*.so" jniLibs so the installer
    // places them there, then exec from that path.
    private fun nativeLibDir() = ctx.applicationInfo.nativeLibraryDir
    private fun prootExec() = File(nativeLibDir(), "libproot.so")
    private fun vibecliExec() = File(nativeLibDir(), "libvibecli.so")

    // A dangling symlink reports exists()==false but still occupies the path,
    // so we detect it explicitly to clear stale links from prior installs.
    private fun isSymlink(f: File): Boolean =
        runCatching {
            android.system.Os.lstat(f.absolutePath)
            f.canonicalPath != f.absolutePath
        }.getOrDefault(false)

    private fun startSandbox(result: Result) {
        scope.launch {
            try {
                val alpine = alpineDir().absolutePath
                val proot = prootExec()
                val tmpDir = File(ctx.cacheDir, "proot-tmp").apply { mkdirs() }

                if (!proot.exists()) {
                    throw IllegalStateException(
                        "proot binary not found at ${proot.absolutePath}. " +
                        "It must be bundled as jniLibs/<abi>/libproot.so."
                    )
                }

                // proot args:
                //  -r rootfs   : the Alpine root
                //  -0          : fake root (uid 0) so apk/git work
                //  -b host:dst : bind mounts for /proc /sys /dev + DNS
                //  -w /root    : working dir
                //  then the command to run inside the guest
                val vibecli = vibecliExec()
                if (!vibecli.exists()) {
                    throw IllegalStateException(
                        "vibecli binary not found at ${vibecli.absolutePath}. " +
                        "It must be bundled as jniLibs/<abi>/libvibecli.so."
                    )
                }

                val cmd = arrayListOf(
                    proot.absolutePath,
                    "-r", alpine,
                    "-0",
                    // Spoof a modern kernel release so uname()-based checks pass.
                    "-k", "5.4.0",
                    "-b", "/proc",
                    "-b", "/sys",
                    "-b", "/dev",
                    // Map BOTH random devices to the host's working urandom.
                    "-b", "/dev/urandom:/dev/random",
                    "-b", "/dev/urandom:/dev/urandom",
                    "-b", "${tmpDir.absolutePath}:/tmp",
                    // Bind the host vibecli binary to a path inside the guest.
                    "-b", "${vibecli.absolutePath}:/usr/local/bin/vibecli",
                    "-w", "/root",
                    "/usr/bin/env",
                    "PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin",
                    "HOME=/root",
                    "/usr/local/bin/vibecli", "serve", "--port", "7700"
                )

                // proot links against libtalloc.so.2 at runtime, but Android
                // only extracts files named "lib*.so" into nativeLibDir. We
                // ship it as libtalloc.so, then symlink the versioned name it
                // wants into a writable dir and add that to LD_LIBRARY_PATH.
                // IMPORTANT: copy (don't symlink). nativeLibDir's path contains
                // an install-specific hash that changes on every reinstall, so a
                // symlink created by an earlier install dangles after an update
                // and proot fails with EROFS following the dead link.
                val libDir = File(ctx.filesDir, "proot-libs").apply { mkdirs() }
                val tallocSrc = File(nativeLibDir(), "libtalloc.so")
                val tallocDst = File(libDir, "libtalloc.so.2")
                if (tallocSrc.exists()) {
                    // Always refresh: delete any stale link/copy first.
                    if (tallocDst.exists() || isSymlink(tallocDst)) tallocDst.delete()
                    tallocSrc.copyTo(tallocDst, overwrite = true)
                    tallocDst.setReadable(true, false)
                }

                prootProcess = ProcessBuilder(cmd).redirectErrorStream(true).also {
                    it.environment()["PROOT_TMP_DIR"] = tmpDir.absolutePath
                    it.environment()["PROOT_LOADER"] =
                        File(nativeLibDir(), "libproot-loader.so").absolutePath
                    // NOTE: We intentionally do NOT set PROOT_NO_SECCOMP. With
                    // seccomp ENABLED (proot's default), proot correctly traps
                    // getrandom and emulates it. Disabling seccomp forces slow
                    // ptrace-only mode where some Samsung kernels fail to trap
                    // getrandom -> ENOSYS -> apk libcrypto load fails.
                    // Let proot's dynamic linker find libtalloc.so.2.
                    it.environment()["LD_LIBRARY_PATH"] =
                        "${libDir.absolutePath}:${nativeLibDir()}"
                }.start()
                val proc = prootProcess!!

                // Capture early output so we can surface the real failure.
                val output = StringBuilder()
                val reader = proc.inputStream.bufferedReader()
                val pump = launch {
                    try {
                        reader.forEachLine { line ->
                            synchronized(output) {
                                if (output.length < 4000) output.append(line).append('\n')
                            }
                        }
                    } catch (_: Exception) {}
                }

                // Give it ~1.5s to either crash or start listening.
                delay(1500)
                if (!proc.isAlive) {
                    pump.cancel()
                    val code = proc.exitValue()
                    val msg = synchronized(output) { output.toString().trim() }
                    android.util.Log.e("VibeProot",
                        "proot exited code=$code cmd=${cmd.joinToString(" ")}\nOUTPUT:\n$msg")
                    withContext(Dispatchers.Main) {
                        if (isActive) result.error(
                            "START_ERR",
                            "proot exited (code $code).\n${msg.ifEmpty { "no output" }}",
                            null
                        )
                    }
                } else {
                    withContext(Dispatchers.Main) { if (isActive) result.success(true) }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { if (isActive) result.error("START_ERR", e.message ?: e.toString(), null) }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        prootProcess?.destroy()
        scope.cancel()
    }
}
