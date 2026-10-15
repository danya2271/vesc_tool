/*
    Copyright 2025 Benjamin Vedder	benjamin@vedder.se

    This file is part of VESC Tool.

    VESC Tool is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
*/

package com.vedder.vesc;

import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Looper;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.util.TypedValue;
import android.widget.TextView;

final class VFloatingWindow {
    private static TextView sView;
    private static WindowManager sWindowManager;
    private static WindowManager.LayoutParams sLayoutParams;

    private VFloatingWindow() {
    }

    static void show(final Context context, final String speed, final String power, final String voltage) {
        runOnUiThread(context, new Runnable() {
            @Override
            public void run() {
                if (!Utils.canDrawOverlays(context)) {
                    return;
                }

                ensureView(context);
                updateText(speed, power, voltage);

                if (sView.getParent() == null) {
                    try {
                        sWindowManager.addView(sView, sLayoutParams);
                    } catch (WindowManager.BadTokenException e) {
                        hideOnUiThread();
                    } catch (SecurityException e) {
                        hideOnUiThread();
                    }
                }
            }
        });
    }

    static void update(final Context context, final String speed, final String power, final String voltage) {
        runOnUiThread(context, new Runnable() {
            @Override
            public void run() {
                if (sView != null && sView.getParent() != null) {
                    updateText(speed, power, voltage);
                }
            }
        });
    }

    static void hide(final Context context) {
        runOnUiThread(context, new Runnable() {
            @Override
            public void run() {
                hideOnUiThread();
            }
        });
    }

    private static void ensureView(Context context) {
        if (sView != null) {
            return;
        }

        sWindowManager = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
        sView = new TextView(context.getApplicationContext());
        sView.setTextColor(Color.WHITE);
        sView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14.0f);
        sView.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        sView.setGravity(Gravity.CENTER_VERTICAL);
        int horizontalPadding = dp(context, 14);
        int verticalPadding = dp(context, 10);
        sView.setPadding(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding);
        sView.setMinWidth(dp(context, 170));

        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.argb(224, 24, 28, 34));
        background.setCornerRadius(dp(context, 12));
        background.setStroke(dp(context, 1), Color.argb(170, 180, 220, 255));
        sView.setBackground(background);
        sView.setOnTouchListener(new DragListener());

        int windowType = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ?
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY :
                WindowManager.LayoutParams.TYPE_PHONE;
        sLayoutParams = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                windowType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE |
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL |
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                android.graphics.PixelFormat.TRANSLUCENT);
        sLayoutParams.gravity = Gravity.TOP | Gravity.END;
        sLayoutParams.x = dp(context, 12);
        sLayoutParams.y = dp(context, 72);
    }

    private static void updateText(String speed, String power, String voltage) {
        if (sView != null) {
            sView.setText("SPEED   " + speed + "\nPOWER   " + power + "\nBATTERY " + voltage);
        }
    }

    private static void hideOnUiThread() {
        if (sView != null && sView.getParent() != null && sWindowManager != null) {
            sWindowManager.removeView(sView);
        }
        sView = null;
        sWindowManager = null;
        sLayoutParams = null;
    }

    private static void runOnUiThread(Context context, Runnable action) {
        Activity activity = Utils.getActivity(context);
        if (activity == null) {
            return;
        }

        if (Looper.myLooper() == Looper.getMainLooper()) {
            action.run();
        } else {
            activity.runOnUiThread(action);
        }
    }

    private static int dp(Context context, int value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }

    private static final class DragListener implements View.OnTouchListener {
        private float startRawX;
        private float startRawY;
        private int startX;
        private int startY;

        @Override
        public boolean onTouch(View view, MotionEvent event) {
            if (sLayoutParams == null || sWindowManager == null) {
                return false;
            }

            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    startRawX = event.getRawX();
                    startRawY = event.getRawY();
                    startX = sLayoutParams.x;
                    startY = sLayoutParams.y;
                    return true;
                case MotionEvent.ACTION_MOVE:
                    sLayoutParams.x = startX - Math.round(event.getRawX() - startRawX);
                    sLayoutParams.y = startY + Math.round(event.getRawY() - startRawY);
                    sWindowManager.updateViewLayout(view, sLayoutParams);
                    return true;
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    return true;
                default:
                    return true;
            }
        }
    }
}
