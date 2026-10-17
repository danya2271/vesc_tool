/*
    Copyright 2025 Benjamin Vedder	benjamin@vedder.se

    This file is part of VESC Tool.

    VESC Tool is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
*/

package com.vedder.vesc;

import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.WindowManager;
import android.util.TypedValue;
import android.widget.TextView;

final class VFloatingWindow {
    private static TextView sView;
    private static WindowManager sWindowManager;
    private static WindowManager.LayoutParams sLayoutParams;
    private static final Handler sMainHandler = new Handler(Looper.getMainLooper());
    private static volatile boolean sOpenHudRequested;

    private VFloatingWindow() {
    }

    static void show(final Context context, final String speed, final String power, final String voltage) {
        runOnUiThread(context, new Runnable() {
            @Override
            public void run() {
                if (context == null || !Utils.canDrawOverlays(context)) {
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
                    } catch (RuntimeException e) {
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

        Context applicationContext = context.getApplicationContext();
        if (applicationContext == null) {
            applicationContext = context;
        }

        sWindowManager = (WindowManager) applicationContext.getSystemService(Context.WINDOW_SERVICE);
        sView = new TextView(applicationContext);
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
        sView.setOnTouchListener(new DragListener(applicationContext));

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
        if (context == null) {
            return;
        }
        sMainHandler.post(action);
    }

    static boolean consumeOpenHudRequest() {
        boolean requested = sOpenHudRequested;
        sOpenHudRequested = false;
        return requested;
    }

    private static void openApplication(Context context) {
        sOpenHudRequested = true;
        Intent launchIntent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (launchIntent == null) {
            sOpenHudRequested = false;
            return;
        }

        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK |
                              Intent.FLAG_ACTIVITY_REORDER_TO_FRONT |
                              Intent.FLAG_ACTIVITY_SINGLE_TOP);
        try {
            context.startActivity(launchIntent);
        } catch (RuntimeException e) {
            sOpenHudRequested = false;
        }
    }

    private static int dp(Context context, int value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }

    private static final class DragListener implements View.OnTouchListener {
        private final Context context;
        private final int touchSlop;
        private float startRawX;
        private float startRawY;
        private int startX;
        private int startY;
        private boolean moved;

        DragListener(Context context) {
            this.context = context;
            touchSlop = ViewConfiguration.get(context).getScaledTouchSlop();
        }

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
                    moved = false;
                    return true;
                case MotionEvent.ACTION_MOVE:
                    if (Math.abs(event.getRawX() - startRawX) > touchSlop ||
                            Math.abs(event.getRawY() - startRawY) > touchSlop) {
                        moved = true;
                    }
                    sLayoutParams.x = startX - Math.round(event.getRawX() - startRawX);
                    sLayoutParams.y = startY + Math.round(event.getRawY() - startRawY);
                    sWindowManager.updateViewLayout(view, sLayoutParams);
                    return true;
                case MotionEvent.ACTION_UP:
                    if (!moved) {
                        openApplication(context);
                    }
                    return true;
                case MotionEvent.ACTION_CANCEL:
                    return true;
                default:
                    return true;
            }
        }
    }
}
