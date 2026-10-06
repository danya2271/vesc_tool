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
acceleration, acceleration recovery band, TC intervention threshold in ERPM,
penalty factor, recovery rate, and TC reduction band in ERPM. The intervention
threshold is the point where TC starts reducing the requested current. The
configured reduction band brings the TC target toward the penalty factor; a
second equal band can then bring it down to zero for a severe ERPM runaway.

**Apply and save** updates RAM immediately. EEPROM is written only when motor
speed and current are near zero and the throttle is released. The application
distinguishes successful EEPROM saves, RAM-only updates, write failures, and
missing acknowledgements. EEPROM slots 0–8 are reserved for this preset; do not
share them with another script. Failed/incomplete writes invalidate the version
marker so the preset can fall back to defaults on restart.

## Smooth limiting and preload

The acceleration governor maintains a current ceiling instead of multiplying
the full throttle request by a factor that switches between 0 and 1. It leaves
the original throttle/ramp response untouched until measured acceleration
exceeds the configured maximum, then lowers the ceiling on new samples and
recovers it quickly after acceleration returns to normal. Disabling traction
control does not disable this independent acceleration governor; disabling the
acceleration governor resets its ceiling immediately.

With the throttle pressed, both governors preserve the configured `idle-current`
preload (default **1 A**), but never request more than the throttle/battery-limited
current demand. The startup interlock, battery cutoff and EEPROM-write interlock
still command zero. Releasing the throttle at standstill also requests zero;
above `min-erpm` the original coasting preload remains voltage-derated.

An unloaded wheel can accelerate faster than the configured limit even at 1 A.
A mandatory positive preload and a strict acceleration limit cannot both be
satisfied in that situation. This preset prioritizes preload over cutting to
zero during ordinary acceleration/traction limiting. Set `idle-current` to 0
in the script if positive preload is not wanted; safety cutoffs are unaffected.

## Diagnostics and limitations

Auto Poll defaults to compact `vt-*` telemetry: raw throttle voltage (`vt-adc`),
commanded current (`vt-current`), motor ERPM (`vt-erpm`), filtered acceleration
(`vt-accel`), startup interlock (`vt-armed`, 1 after throttle release), and the
persistent acceleration current ceiling (`vt-limit-current`). It also exposes
`vt-tc-on`, `vt-al-on`, and the smoothed TC multiplier (`vt-tc-cut`) so the
controller state can be verified independently of the Android checkboxes.
**All globals** also requests configuration and internal variables, but firmware
may truncate this list. Configuration readback does not depend on that list.

The current loop uses the original 0.5 ms period and ramp response. Acceleration
feedback is updated on motion samples rather than every current-loop iteration.
Repeated field-weakening configuration updates are rate-limited.
Battery cutoff inhibits both drive current and field weakening.

Motor ERPM alone cannot establish actual vehicle acceleration or true wheel
slip. These are soft current-limiting estimates, not guaranteed physical
acceleration limits, and cannot slow a vehicle accelerated by gravity. A
separate vehicle/wheel-speed reference is needed for true traction measurement.
