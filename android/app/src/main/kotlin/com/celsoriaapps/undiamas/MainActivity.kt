package com.celsoriaapps.undiamas

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var locked = false
    private var privacyChannel: MethodChannel? = null
    private var notificationSettingsChannel: MethodChannel? = null
    private var lockedBackCallback: OnBackInvokedCallback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // The legacy SharedPreferences plugin uses this file and Flutter prefix.
        // Read before Flutter creates its first frame; a corrupt value fails closed.
        locked = try {
            getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .getBoolean("flutter.privacyAppLockEnabled", false)
        } catch (error: RuntimeException) {
            Log.e("UnDiaMasPrivacy", "Could not read privacy preference; keeping content protected.", error)
            true
        }
        super.onCreate(savedInstanceState)
        updateBackProtection()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // An app-local plugin is not registered by manifest metadata.
        if (!flutterEngine.plugins.has(TzPlugin::class.java)) {
            flutterEngine.plugins.add(TzPlugin())
        }
        notificationSettingsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "undiamas/notifications"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "openSettings") {
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(android.net.Uri.parse("package:$packageName"))
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (error: RuntimeException) {
                        result.error("settings_unavailable", "Notification settings are unavailable.", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
        }
        privacyChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "undiamas/privacy")
            .also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "setLocked" -> {
                            val value = call.arguments as? Boolean
                            if (value == null) {
                                result.error("invalid_argument", "Expected a boolean privacy state.", null)
                            } else {
                                locked = value
                                updateBackProtection()
                                result.success(null)
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    private fun updateBackProtection() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (locked && lockedBackCallback == null) {
                val callback = OnBackInvokedCallback { moveTaskToBack(true) }
                // The lock covers every Flutter route, so consume Back before Flutter.
                onBackInvokedDispatcher.registerOnBackInvokedCallback(
                    OnBackInvokedDispatcher.PRIORITY_OVERLAY,
                    callback,
                )
                lockedBackCallback = callback
            } else if (!locked) {
                lockedBackCallback?.let {
                    onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it)
                }
                lockedBackCallback = null
            }
        }
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (locked) {
            moveTaskToBack(true)
        } else {
            super.onBackPressed()
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        notificationSettingsChannel?.setMethodCallHandler(null)
        notificationSettingsChannel = null
        privacyChannel?.setMethodCallHandler(null)
        privacyChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            lockedBackCallback?.let {
                onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it)
            }
            lockedBackCallback = null
        }
        super.onDestroy()
    }
}
