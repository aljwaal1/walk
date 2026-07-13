package com.explapp.walklegacy;

import android.media.AudioManager;
import android.media.ToneGenerator;
import android.os.Bundle;
import android.os.Handler;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

/** App-specific interaction and tracking sounds for the Android 4.4 walking companion. */
public class SoundMainActivity extends MainActivity {
    private final Handler observer = new Handler();
    private ToneGenerator tones;
    private float downX;
    private float downY;
    private long lastSoundAt;
    private String lastState = "";

    @Override public void onCreate(Bundle savedInstanceState) {
        tones = new ToneGenerator(AudioManager.STREAM_MUSIC, 48);
        super.onCreate(savedInstanceState);
        observer.post(statusWatcher);
    }

    @Override public boolean dispatchTouchEvent(MotionEvent event) {
        if (event.getAction() == MotionEvent.ACTION_DOWN) {
            downX = event.getRawX();
            downY = event.getRawY();
        } else if (event.getAction() == MotionEvent.ACTION_UP
                && Math.abs(event.getRawX() - downX) < 18f
                && Math.abs(event.getRawY() - downY) < 18f) {
            View target = findView(getWindow().getDecorView(), event.getRawX(), event.getRawY());
            if (target != null && target.isClickable()) playFor(target);
        }
        return super.dispatchTouchEvent(event);
    }

    private void playFor(View view) {
        String text = view instanceof TextView ? ((TextView) view).getText().toString() : "";
        if (containsAny(text, "بدء المشي", "متابعة المشي")) {
            play(ToneGenerator.TONE_PROP_ACK, 120);
        } else if (containsAny(text, "إيقاف مؤقت")) {
            play(ToneGenerator.TONE_PROP_BEEP2, 90);
        } else if (containsAny(text, "إنهاء وحفظ", "حفظ")) {
            play(ToneGenerator.TONE_CDMA_CONFIRM, 125);
        } else if (containsAny(text, "حذف", "تصفير", "مسح", "إلغاء")) {
            play(ToneGenerator.TONE_PROP_NACK, 115);
        } else if (containsAny(text, "المشي", "السجل", "الإنجازات", "الشارات")) {
            play(ToneGenerator.TONE_DTMF_6, 70);
        } else if (containsAny(text, "تغيير الهدف", "مدة التحدي")) {
            play(ToneGenerator.TONE_DTMF_5, 70);
        } else if (containsAny(text, "رجوع", "العودة")) {
            play(ToneGenerator.TONE_PROP_BEEP2, 80);
        } else {
            play(ToneGenerator.TONE_PROP_BEEP, 58);
        }
    }

    private final Runnable statusWatcher = new Runnable() {
        @Override public void run() {
            if (tones == null) return;
            String snapshot = collectText(getWindow().getDecorView());
            String state = stateFrom(snapshot);
            if (lastState.length() == 0) {
                lastState = state;
            } else if (state.length() > 0 && !state.equals(lastState)) {
                if ("active".equals(state)) {
                    play(ToneGenerator.TONE_CDMA_CONFIRM, 95);
                } else if ("paused".equals(state)) {
                    play(ToneGenerator.TONE_PROP_BEEP2, 95);
                } else if ("weak".equals(state)) {
                    play(ToneGenerator.TONE_CDMA_NETWORK_BUSY_ONE_SHOT, 120);
                } else if ("gps_off".equals(state)) {
                    play(ToneGenerator.TONE_PROP_NACK, 150);
                } else if ("history".equals(state) && "active".equals(lastState)) {
                    play(ToneGenerator.TONE_PROP_ACK, 150);
                }
                lastState = state;
            }
            observer.postDelayed(this, 320L);
        }
    };

    private String stateFrom(String text) {
        if (containsAny(text, "إشارة ضعيفة")) return "weak";
        if (containsAny(text, "التتبع نشط في الخلفية")) return "active";
        if (containsAny(text, "الجلسة متوقفة مؤقتاً")) return "paused";
        if (containsAny(text, "GPS متوقف", "يحتاج تتبع المسافة إلى إذن الموقع")) return "gps_off";
        if (containsAny(text, "سجل المشي", "الجلسات الأخيرة")) return "history";
        return "idle";
    }

    private String collectText(View view) {
        StringBuilder builder = new StringBuilder();
        appendText(view, builder);
        return builder.toString();
    }

    private void appendText(View view, StringBuilder builder) {
        if (view == null || view.getVisibility() != View.VISIBLE) return;
        if (view instanceof TextView) builder.append('|').append(((TextView) view).getText());
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) appendText(group.getChildAt(i), builder);
        }
    }

    private View findView(View view, float x, float y) {
        if (view == null || view.getVisibility() != View.VISIBLE) return null;
        int[] location = new int[2];
        view.getLocationOnScreen(location);
        if (x < location[0] || x > location[0] + view.getWidth()
                || y < location[1] || y > location[1] + view.getHeight()) return null;
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = group.getChildCount() - 1; i >= 0; i--) {
                View child = findView(group.getChildAt(i), x, y);
                if (child != null) return child;
            }
        }
        return view;
    }

    private void play(int tone, int durationMs) {
        if (tones == null || System.currentTimeMillis() - lastSoundAt < 75L) return;
        lastSoundAt = System.currentTimeMillis();
        tones.startTone(tone, durationMs);
    }

    private boolean containsAny(String text, String... words) {
        for (String word : words) if (text.contains(word)) return true;
        return false;
    }

    @Override public void onBackPressed() {
        play(ToneGenerator.TONE_PROP_BEEP2, 80);
        super.onBackPressed();
    }

    @Override protected void onDestroy() {
        observer.removeCallbacksAndMessages(null);
        if (tones != null) {
            tones.release();
            tones = null;
        }
        super.onDestroy();
    }
}
