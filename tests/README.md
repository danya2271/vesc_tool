# Gearbox sound checks

Run the Qt Quick tests with Qt 5.15 and QtTest installed:

```sh
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qmltestrunner -input tests/qml -import mobile
qmllint mobile/GearboxSound.qml mobile/Lisp.qml tests/qml/tst_GearboxSound.qml
```

Run the actual preset definitions in a built LispBM REPL, or in upstream
LispBM's `test_lisp_code_cps` runner:

```sh
python3 tests/run_gearbox_sound.py /path/to/lispBM/repl/repl
python3 tests/run_gearbox_sound.py /path/to/lispBM/tests/test_lisp_code_cps --cps
```

The default heap limit is 2740 cells, matching a standard STM32 VESC build.
The checks cover logarithmic pitch, quiet continuous preload, throttle and
limiter response, total tone amplitude, interlocks, stale control state, the
256-word audio context stack, independent EEPROM persistence, invalid or
partial settings, and control-loop integration after moving functions to flash.
The Python harness replaces hardware access and time with deterministic stubs;
the minimal CPS runner also uses a print stub. Qt tests cover controller replies,
save acknowledgements, disconnects, validation, and input/readback synchronization.
These checks do not measure sound on a physical motor.
