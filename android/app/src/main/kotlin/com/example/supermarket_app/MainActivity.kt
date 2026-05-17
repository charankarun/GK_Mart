package com.example.supermarket_app

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CUSTOMER_SUPPORT_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "dialPhone" -> {
                    val phoneNumber = call.argument<String>("phoneNumber").orEmpty()
                    if (phoneNumber.isBlank()) {
                        result.error("invalid_phone", "Phone number is required", null)
                        return@setMethodCallHandler
                    }

                    val intent = Intent(Intent.ACTION_DIAL).apply {
                        data = Uri.parse("tel:$phoneNumber")
                    }
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val CUSTOMER_SUPPORT_CHANNEL = "gk_mart/customer_support"
    }
}
