#!/usr/bin/env python3
"""Run the production preset with motor/EEPROM stubs in a real LispBM REPL."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("lbm", help="Path to the LispBM REPL or CPS test executable (32 or 64 bit)")
parser.add_argument("--heap-cells", default=2740, type=int, help="Heap cell limit (default: VESC STM32 2740)")
parser.add_argument("--cps", action="store_true", help="Use LispBM test_lisp_code_cps instead of the REPL")
args = parser.parse_args()

stubs = """
(define test-time 0.0)
(define test-rpm 0.0)
(define test-vin 50.0)
(define test-adc 0.85)
(define test-current-command 0.0)
(define test-tones nil)
(define test-stops 0)
(define test-write-fails 0)
(define test-eeprom (list 99 nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                         nil nil nil nil nil nil nil nil nil nil nil))
(defun systime () test-time)
(defun secs-since (time) (- test-time time))
(defun get-rpm () test-rpm)
(defun get-vin () test-vin)
(defun get-current () 0.0)
(defun get-adc (channel) test-adc)
(defun set-current (current) (progn (setvar 'test-current-command current) t))
(defun conf-set (parameter value) t)
(defun foc-play-tone (channel frequency voltage)
    (progn (setvar 'test-tones (cons (list channel frequency voltage) test-tones)) t))
(defun foc-play-stop () (progn (setvar 'test-stops (+ test-stops 1)) t))
(defun eeprom-read-i (address) (ix test-eeprom address))
(defun eeprom-read-f (address) (ix test-eeprom address))
(defun eeprom-store-i (address value) (progn (setix test-eeprom address value) t))
(defun eeprom-store-f (address value)
    (if (= test-write-fails 1) nil (progn (setix test-eeprom address value) t)))
"""
preset = (ROOT / "res/LispBM/Presets/smart_throttle_traction_control.lbm").read_text()
# Load every production function; replace only hardware startup and the endless loop.
definitions, startup = preset.rsplit("\n(tc-load-config)\n", 1)
assert "(spawn 256 gs-loop)" in startup
tests = (ROOT / "tests/gearbox_sound.lbm").read_text()
with tempfile.TemporaryDirectory(prefix="vesc-gearbox-test-") as directory:
    source = Path(directory) / "test.lbm"
    program = stubs + definitions + "\n" + tests
    # The desktop REPL also has built-in clocks; substitute only these two
    # hardware functions so watchdog and smoothing checks use deterministic time.
    program = program.replace("systime", "test-systime").replace("secs-since", "test-secs-since")
    # The upstream CPS runner reserves the extension name 'check'.
    program = program.replace("(defun check ", "(defun gs-test-check ").replace("(check ", "(gs-test-check ")
    if args.cps:
        # The minimal CPS runner has no firmware print extension.
        program = "(defun print (value) t)\n" + program + "\n(check t)\n"
    source.write_text(program)
    executable = str(Path(args.lbm).resolve())
    command = ([executable, "-i", "-h", str(args.heap_cells), str(source)] if args.cps else
               [executable, "-H", str(args.heap_cells), "--src", str(source), "--terminate"])
    result = subprocess.run(
        command,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
    )
    print(result.stdout, end="")
    expected_status = 1 if args.cps else 0
    marker = "SUCCESS\n" if args.cps else "GEARBOX_SOUND_TESTS_PASSED"
    if result.returncode != expected_status or marker not in result.stdout:
        raise SystemExit(1)
