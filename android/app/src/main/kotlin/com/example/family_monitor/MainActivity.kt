package com.example.family_monitor
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
class MainActivity : FlutterActivity() {
    private val SMS_CHANNEL = "family_monitor/sms"
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "readSms") {
                    val limit = call.argument<Int>("limit") ?: 100
                    result.success(readSms(limit))
                } else result.notImplemented()
            }
    }
    private fun readSms(limit: Int): List<Map<String, Any>> {
        val msgs = mutableListOf<Map<String, Any>>()
        try {
            val cursor = contentResolver.query(
                Uri.parse("content://sms"), arrayOf("address","body","date","type"),
                null, null, "date DESC LIMIT $limit")
            cursor?.use {
                val ai=it.getColumnIndex("address"); val bi=it.getColumnIndex("body")
                val di=it.getColumnIndex("date"); val ti=it.getColumnIndex("type")
                while (it.moveToNext()) msgs.add(mapOf(
                    "address" to (it.getString(ai)?:""),
                    "body" to (it.getString(bi)?:""),
                    "date" to it.getLong(di), "type" to it.getInt(ti)))
            }
        } catch (e: Exception) {}
        return msgs
    }
}
