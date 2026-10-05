# Smart throttle and traction preset

`smart_throttle_traction_control.lbm` controls forward motor current from ADC 0.
Acceleration is configured in **m/s²**, not m/s. Both the acceleration governor
and ERPM-based traction control can be switched off independently.

## Installing an update

1. Install the updated Android application.
2. Open **LispBM → Editor → Open Smart Traction Preset**, then upload it and run it.
   Installing the application alone does not replace a script stored on the ESC.
3. Release the throttle once after starting the script. Until then motor output
   is inhibited, including when a script is uploaded with the throttle held.
4. Initially test with the drive wheel safely unloaded. Check the throttle
   calibration, battery limits, motor limits, and `erpm-per-kmh` before riding.
   The defaults use 380 ERPM per km/h and throttle voltages 0.85–2.67 V.

## Settings and persistence

The Android **Traction** tab uses LispBM REPL commands rather than the firmware's
size-limited global-variable statistics packet:

```lisp
(tc-get-config)
(tc-set-config 1 1 1.5 0.5 400.0 0.10 0.02 200.0)
```

Arguments are traction enabled, acceleration governor enabled, maximum
acceleration, acceleration soft band, slip threshold in ERPM, penalty factor,
recovery rate, and speed-envelope soft band in ERPM.

**Apply and save** updates RAM immediately. EEPROM is written only when motor
speed and current are near zero and the throttle is released. The application
distinguishes successful EEPROM saves, RAM-only updates, write failures, and
missing acknowledgements. EEPROM slots 0–8 are reserved for this preset; do not
share them with another script. Failed/incomplete writes invalidate the version
marker so the preset can fall back to defaults on restart.

## Diagnostics and limitations

Auto Poll defaults to compact `vt-*` telemetry: raw throttle voltage (`vt-adc`),
commanded current (`vt-current`), motor ERPM (`vt-erpm`), filtered acceleration
(`vt-accel`), and startup interlock (`vt-armed`, 1 after throttle release).
**All globals** also requests configuration and internal variables, but firmware
may truncate this list. Configuration readback does not depend on that list.

The governor uses elapsed wall-clock time for ramping and acceleration
estimation, and limits repeated field-weakening configuration updates.
Battery cutoff inhibits both drive current and field weakening.

Motor ERPM alone cannot establish actual vehicle acceleration or true wheel
slip. These are soft current-limiting estimates, not guaranteed physical
acceleration limits, and cannot slow a vehicle accelerated by gravity. A
separate vehicle/wheel-speed reference is needed for true traction measurement.
