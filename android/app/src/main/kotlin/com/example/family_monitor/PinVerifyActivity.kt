package com.example.family_monitor

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.*
import android.util.Log

/**
 * Full-screen PIN verification gate shown when a child attempts to
 * remove Device Admin (prerequisite for uninstalling the app).
 *
 * PIN is stored in FlutterSharedPreferences under key "flutter.uninstall_pin"
 * by the Dart PinService. Three wrong attempts → go home.
 */
class PinVerifyActivity : Activity() {

    companion object {
        private const val TAG = "PinVerifyActivity"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val PIN_KEY = "flutter.uninstall_pin"
        private const val MAX_ATTEMPTS = 3

        fun launch(context: Context) {
            val intent = Intent(context, PinVerifyActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            context.startActivity(intent)
        }
    }

    private val enteredPin = StringBuilder()
    private var attempts = 0
    private lateinit var dotViews: List<View>
    private lateinit var statusText: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "PIN verify activity started")

        val stored = getStoredPin()
        if (stored == null) {
            Log.d(TAG, "No PIN set — allowing through")
            finish()
            return
        }

        buildUI(stored)
    }

    private fun getStoredPin(): String? {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val pin = prefs.getString(PIN_KEY, null)
        return if (pin != null && pin.length == 4) pin else null
    }

    private fun buildUI(storedPin: String) {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#F8FAFB"))
            setPadding(48, 64, 48, 64)
        }

        // Lock icon header
        val iconText = TextView(this).apply {
            text = "🔒"
            textSize = 52f
            gravity = Gravity.CENTER
        }
        root.addView(iconText)

        val space1 = Space(this).apply { minimumHeight = 24 }
        root.addView(space1)

        // Title
        val title = TextView(this).apply {
            text = "Enter Safety PIN"
            textSize = 22f
            setTextColor(Color.parseColor("#202124"))
            gravity = Gravity.CENTER
            setTypeface(null, Typeface.BOLD)
        }
        root.addView(title)

        val space2 = Space(this).apply { minimumHeight = 8 }
        root.addView(space2)

        // Subtitle
        val subtitle = TextView(this).apply {
            text = "Enter the PIN to allow this action"
            textSize = 14f
            setTextColor(Color.parseColor("#5F6368"))
            gravity = Gravity.CENTER
        }
        root.addView(subtitle)

        val space3 = Space(this).apply { minimumHeight = 40 }
        root.addView(space3)

        // PIN dots
        val dotsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        val dots = mutableListOf<View>()
        repeat(4) {
            val dot = View(this).apply {
                val size = 20
                minimumWidth = size.dpToPx()
                minimumHeight = size.dpToPx()
                layoutParams = LinearLayout.LayoutParams(
                    size.dpToPx(), size.dpToPx()
                ).apply { setMargins(10, 0, 10, 0) }
                background = circleDrawable(false)
            }
            dotsRow.addView(dot)
            dots.add(dot)
        }
        dotViews = dots
        root.addView(dotsRow)

        val space4 = Space(this).apply { minimumHeight = 16 }
        root.addView(space4)

        // Status text
        statusText = TextView(this).apply {
            text = ""
            textSize = 13f
            setTextColor(Color.parseColor("#EA4335"))
            gravity = Gravity.CENTER
        }
        root.addView(statusText)

        val space5 = Space(this).apply { minimumHeight = 32 }
        root.addView(space5)

        // Numpad
        val numpad = GridLayout(this).apply {
            columnCount = 3
            rowCount = 4
        }

        val keys = listOf("1","2","3","4","5","6","7","8","9","","0","⌫")
        keys.forEach { key ->
            val btn = buildKeyButton(key, storedPin)
            numpad.addView(btn)
        }
        root.addView(numpad)

        val scrollView = ScrollView(this)
        scrollView.addView(root)
        setContentView(scrollView)
    }

    private fun buildKeyButton(label: String, storedPin: String): View {
        if (label.isEmpty()) {
            val empty = View(this).apply {
                layoutParams = GridLayout.LayoutParams().apply {
                    width = 96.dpToPx()
                    height = 72.dpToPx()
                    setMargins(8, 8, 8, 8)
                }
            }
            return empty
        }

        return Button(this).apply {
            text = label
            textSize = if (label == "⌫") 20f else 22f
            setTextColor(Color.parseColor("#202124"))
            setBackgroundColor(Color.WHITE)
            layoutParams = GridLayout.LayoutParams().apply {
                width = 96.dpToPx()
                height = 72.dpToPx()
                setMargins(8, 8, 8, 8)
            }
            setOnClickListener {
                if (label == "⌫") {
                    if (enteredPin.isNotEmpty()) {
                        enteredPin.deleteCharAt(enteredPin.length - 1)
                        updateDots()
                    }
                } else {
                    if (enteredPin.length < 4) {
                        enteredPin.append(label)
                        updateDots()
                        if (enteredPin.length == 4) {
                            checkPin(enteredPin.toString(), storedPin)
                        }
                    }
                }
            }
        }
    }

    private fun checkPin(entered: String, stored: String) {
        if (entered == stored) {
            statusText.text = "✓ PIN correct — proceeding"
            statusText.setTextColor(Color.parseColor("#34A853"))
            Log.d(TAG, "PIN verified successfully")
            finish()
        } else {
            attempts++
            enteredPin.clear()
            updateDots()
            val remaining = MAX_ATTEMPTS - attempts
            if (remaining <= 0) {
                statusText.text = "Too many wrong attempts."
                Log.w(TAG, "Too many wrong PIN attempts — going home")
                goHome()
            } else {
                statusText.text = "Wrong PIN. $remaining attempt${if (remaining == 1) "" else "s"} left."
                statusText.setTextColor(Color.parseColor("#EA4335"))
            }
        }
    }

    private fun updateDots() {
        dotViews.forEachIndexed { index, view ->
            view.background = circleDrawable(index < enteredPin.length)
        }
    }

    private fun circleDrawable(filled: Boolean): android.graphics.drawable.ShapeDrawable {
        val shape = android.graphics.drawable.ShapeDrawable(
            android.graphics.drawable.shapes.OvalShape()
        )
        shape.paint.color = if (filled)
            Color.parseColor("#1A73E8")
        else
            Color.parseColor("#E8EAED")
        return shape
    }

    private fun goHome() {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(intent)
        finish()
    }

    private fun Int.dpToPx(): Int =
        (this * resources.displayMetrics.density).toInt()

    override fun onBackPressed() {
        goHome()
    }
}
