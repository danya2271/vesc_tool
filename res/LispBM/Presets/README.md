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

## Straight-cut gearbox sound

The Android **LispBM → Sound** tab configures four continuous motor tones in the
same preset. Upload and run the updated **Smart Traction Preset** once; the
application update alone cannot add sound to an older script on the controller.
The controller firmware must support `foc-play-tone` and `foc-play-stop`.

Sound is enabled by default. It starts whenever the preset supplies drive or
preload current and stops when that current stops, the startup interlock is
active, battery cutoff is reached, or sound is disabled. Releasing the throttle
keeps the sound playing if coasting preload is still active. The default
preload level is a very quiet **0.02 V**; set it to zero for silent preload.
Actual audibility depends on the motor and controller.

The throttle raises volume above the preload level. The ratio of delivered
commanded current to requested current, excluding preload, and the TC multiplier
reduce this extra volume when traction or acceleration limiting reduces drive.
The quieter preload tone continues during limiting. Current ramping is also
reflected in the volume, so holding full throttle does not hold full volume
while TC cuts power. Frequency continues to follow motor speed.

Below **10 km/h**, the fundamental stays at **220 Hz**. Above it, pitch follows
`ln(1 + curve * position) / ln(1 + curve)`, with speed position clamped between
the start and full-pitch speeds. Defaults reach **1720 Hz at 60 km/h**, with a
curve of **4**. The second and third harmonics and a slightly detuned subharmonic
produce the gear whine. Pitch and throttle volume are smoothed independently
of the current loop in a 50 Hz LispBM context. Function bodies are stored in
flash to leave the STM32 LispBM heap available for both running contexts.

The tab exposes enable, start and full-pitch speeds, logarithmic curve, speed
calibration in ERPM per km/h, preload and maximum voltage, base frequency,
frequency rise, and response time. Sound calibration defaults to the preset's
`erpm-per-kmh`; if you change wheel or reduction geometry, update both. The
maximum level defaults to **1.15 V** and is capped at **2 V** for the **sum**
of the four tone amplitudes, not each individual channel.

**Read from controller**, **Defaults**, and **Apply and save** work like the
Traction tab. Saving requires stopping and releasing the throttle. Changes
while moving apply in RAM; stop and apply again to save. EEPROM addresses
**16–26** hold sound settings independently of traction settings in **0–8**.
Invalid or incomplete stored sound settings fall back to defaults.

The equivalent REPL commands are:

```lisp
(gs-get-config)
(gs-set-config 1 10.0 60.0 4.0 358.0 0.02 1.15 220.0 1500.0 0.12)
```

Arguments follow the tab's order, beginning with enable. Disabling sound does
not disable traction control or the acceleration governor.

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
filtered throttle opening in percent (`vt-throttle`, before throttle expo and
current limiting),
commanded current (`vt-current`), motor ERPM (`vt-erpm`), filtered acceleration
(`vt-accel`), startup interlock (`vt-armed`, 1 after throttle release), and the
persistent acceleration current ceiling (`vt-limit-current`). It also exposes
`vt-tc-on`, `vt-al-on`, and the smoothed TC multiplier (`vt-tc-cut`) so the
controller state can be verified independently of the Android checkboxes.
**All globals** also requests configuration and internal variables, but firmware
may truncate this list. Configuration readback does not depend on that list.

The custom Black-Green-Red HUD displays throttle opening as a percentage and a
bar in full, minimal, and landscape views. While the HUD is active, it polls
compact LispBM statistics at 10 Hz independently of the LispBM tab. Upload and
run the updated preset to enable this indicator. Missing or stale telemetry,
or a disconnected controller, displays `—` rather than an old percentage.
This indicates throttle position, not motor current, duty cycle, or the amount
of power left after traction/acceleration limiting.

The current loop uses the original 0.5 ms period and ramp response. Acceleration
feedback is updated on motion samples rather than every current-loop iteration.
Repeated field-weakening configuration updates are rate-limited.
Battery cutoff inhibits both drive current and field weakening.

Motor ERPM alone cannot establish actual vehicle acceleration or true wheel
slip. These are soft current-limiting estimates, not guaranteed physical
acceleration limits, and cannot slow a vehicle accelerated by gravity. A
separate vehicle/wheel-speed reference is needed for true traction measurement.
