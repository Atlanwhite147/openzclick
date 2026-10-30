package app.openzclick.openzclick

import android.content.Context
import android.net.wifi.WifiManager
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
    }

}
