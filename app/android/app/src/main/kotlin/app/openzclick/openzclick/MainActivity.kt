package app.openzclick.openzclick

import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openzclick/multicast")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        if (multicastLock == null) {
                            val wifi = applicationContext
                                .getSystemService(Context.WIFI_SERVICE) as WifiManager
                            multicastLock = wifi.createMulticastLock("openzclick").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(true)
                    }
                    "release" -> {
                        multicastLock?.let { if (it.isHeld) it.release() }
                        multicastLock = null
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // The link has to survive the rider switching to the training
        // application: Android suspends a background application, and a suspended
        // one loses its Bluetooth link and its socket.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openzclick/keepalive")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        KeepAliveService.start(applicationContext)
                        result.success(true)
                    }
                    "stop" -> {
                        KeepAliveService.stop(applicationContext)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Opens MyWhoosh for the rider: the simple screen offers the press
        // instead of asking them to leave the application and find an icon.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openzclick/launcher")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        val packageName = call.argument<String>("package")
                        if (packageName == null) {
                            result.success(false)
                        } else {
                            val intent = packageManager.getLaunchIntentForPackage(packageName)
                            if (intent == null) {
                                // Not installed: no shortcut, and no dialog.
                                result.success(false)
                            } else {
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                try {
                                    startActivity(intent)
                                    result.success(true)
                                } catch (e: Exception) {
                                    result.success(false)
                                }
                            }
                        }
                    }
                    "openUri" -> {
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.success(false)
                        } else {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url))
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Taps towards the training application, performed by the accessibility
        // service the user has to enable once.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, InjectionService.CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "settings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    else -> InjectionService.handle(call, result)
                }
            }
    }
}
