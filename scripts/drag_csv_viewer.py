#!/usr/bin/env python3
"""Desktop viewer for CSV files exported by the VESC mobile drag test.

The viewer uses only Python's standard library (Tkinter); matplotlib and other
third-party packages are not required.

Usage:
    python3 scripts/drag_csv_viewer.py [drag-test.csv]
"""

from __future__ import annotations

import csv
import io
import math
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple, Union

try:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
except ImportError as exc:  # pragma: no cover - depends on the host Python
    raise SystemExit("Tkinter is required. Install the python-tk package.") from exc


BG = "#111017"
PANEL = "#1b1823"
GRID = "#3a3347"
TEXT = "#f2eef8"
DIM = "#a69daf"
GREEN = "#45d47b"
AMBER = "#ffc857"
BLUE = "#42a5f5"
CYAN = "#29b6f6"
VIOLET = "#b388ff"
RED = "#ff5252"


def number(value: object, default: float = 0.0) -> float:
    try:
        result = float(value)
        return result if math.isfinite(result) else default
    except (TypeError, ValueError):
        return default


@dataclass
class DragData:
    path: Path
    metadata: Dict[str, str]
    rows: List[Dict[str, object]]


def load_drag_csv(path: Union[str, os.PathLike]) -> DragData:
    file_path = Path(path)
    metadata: Dict[str, str] = {}
    data_lines: List[str] = []

    with file_path.open("r", encoding="utf-8-sig", newline="") as handle:
        for raw_line in handle:
            if raw_line.startswith("#"):
                meta_line = raw_line[1:].strip()
                if "," in meta_line:
                    key, value = meta_line.split(",", 1)
                    metadata[key.strip()] = value.strip()
                continue
            if raw_line.strip():
                data_lines.append(raw_line)

    if not data_lines:
        raise ValueError("CSV does not contain telemetry rows")

    reader = csv.DictReader(io.StringIO("".join(data_lines)))
    if not reader.fieldnames or "time_s" not in reader.fieldnames:
        raise ValueError("Not a VESC drag-test CSV: the time_s column is missing")

    numeric_columns = {
        "time_s", "speed_kmh", "speed_display", "acceleration_m_s2",
        "power_w", "energy_used_wh", "energy_regen_wh", "energy_net_wh",
        "battery_voltage_v", "mos_temp_c", "motor_temp_c", "distance_m",
    }
    rows: List[Dict[str, object]] = []
    for raw_row in reader:
        row: Dict[str, object] = dict(raw_row)
        for column in numeric_columns:
            if column in row:
                row[column] = number(row[column])
        rows.append(row)

    if not rows:
        raise ValueError("CSV contains a header but no telemetry samples")
    return DragData(file_path, metadata, rows)


def interpolate_crossing(rows: Sequence[Dict[str, object]], target_kmh: float) -> Optional[float]:
    for previous, current in zip(rows, rows[1:]):
        speed0 = number(previous.get("speed_kmh"))
        speed1 = number(current.get("speed_kmh"))
        if speed0 < target_kmh <= speed1 and speed1 > speed0:
            fraction = (target_kmh - speed0) / (speed1 - speed0)
            time0 = number(previous.get("time_s"))
            time1 = number(current.get("time_s"))
            return time0 + (time1 - time0) * fraction
    return None


class LineChart(ttk.Frame):
    def __init__(self, parent: tk.Misc, title: str, unit: str,
                 series: Sequence[Tuple[str, str, str]], include_zero: bool = False):
        super().__init__(parent)
        self.title = title
        self.unit = unit
        self.series = list(series)
        self.include_zero = include_zero
        self.rows: List[Dict[str, object]] = []
        self.points: List[Tuple[float, float, Dict[str, object]]] = []
        self.canvas = tk.Canvas(self, bg=BG, highlightthickness=0)
        self.canvas.pack(fill=tk.BOTH, expand=True)
        self.canvas.bind("<Configure>", lambda _event: self.redraw())
        self.canvas.bind("<Motion>", self.show_cursor)
        self.canvas.bind("<Leave>", lambda _event: self.canvas.delete("cursor"))

    def set_rows(self, rows: Iterable[Dict[str, object]]) -> None:
        self.rows = list(rows)
        self.redraw()

    def redraw(self) -> None:
        canvas = self.canvas
        canvas.delete("all")
        width = max(120, canvas.winfo_width())
        height = max(100, canvas.winfo_height())
        left, right, top, bottom = 64, 20, 38, 42
        plot_w = max(10, width - left - right)
        plot_h = max(10, height - top - bottom)

        canvas.create_text(left, 13, anchor="nw", text=self.title,
                           fill=TEXT, font=("TkDefaultFont", 11, "bold"))
        if not self.rows:
            canvas.create_text(width / 2, height / 2, text="Open a drag-test CSV",
                               fill=DIM, font=("TkDefaultFont", 12))
            return

        times = [number(row.get("time_s")) for row in self.rows]
        x_min, x_max = min(times), max(times)
        if x_max <= x_min:
            x_max = x_min + 1.0

        values: List[float] = []
        for field, _label, _color in self.series:
            values.extend(number(row.get(field)) for row in self.rows)
        y_min, y_max = min(values), max(values)
        if self.include_zero:
            y_min, y_max = min(0.0, y_min), max(0.0, y_max)
        y_pad = max((y_max - y_min) * 0.1, abs(y_max) * 0.02, 0.01)
        y_min -= y_pad
        y_max += y_pad
        if y_max <= y_min:
            y_max = y_min + 1.0

        def px(value: float) -> float:
            return left + (value - x_min) * plot_w / (x_max - x_min)

        def py(value: float) -> float:
            return top + (y_max - value) * plot_h / (y_max - y_min)

        for index in range(6):
            fraction = index / 5
            x = left + plot_w * fraction
            y = top + plot_h * fraction
            canvas.create_line(x, top, x, top + plot_h, fill=GRID)
            canvas.create_line(left, y, left + plot_w, y, fill=GRID)
            canvas.create_text(x, top + plot_h + 17, text=f"{x_min + (x_max - x_min) * fraction:.1f}",
                               fill=DIM, font=("TkDefaultFont", 8))
            canvas.create_text(left - 8, y, anchor="e",
                               text=f"{y_max - (y_max - y_min) * fraction:.2f}",
                               fill=DIM, font=("TkDefaultFont", 8))

        canvas.create_text(left + plot_w / 2, height - 9, text="time (s)", fill=DIM)
        canvas.create_text(8, top + plot_h / 2, text=self.unit, fill=DIM, angle=90)

        legend_x = width - right
        for _field, label, color in reversed(self.series):
            canvas.create_text(legend_x, 15, anchor="ne", text=label, fill=color,
                               font=("TkDefaultFont", 9, "bold"))
            legend_x -= max(65, len(label) * 7 + 14)

        self.points = []
        for field, _label, color in self.series:
            coords: List[float] = []
            for row in self.rows:
                x_value = number(row.get("time_s"))
                y_value = number(row.get(field))
                x_coord, y_coord = px(x_value), py(y_value)
                coords.extend((x_coord, y_coord))
                if field == self.series[0][0]:
                    self.points.append((x_coord, y_coord, row))
            if len(coords) >= 4:
                canvas.create_line(*coords, fill=color, width=2, smooth=False)

    def show_cursor(self, event: tk.Event) -> None:
        if not self.points:
            return
        x, y, row = min(self.points, key=lambda point: abs(point[0] - event.x))
        self.canvas.delete("cursor")
        self.canvas.create_line(x, 38, x, self.canvas.winfo_height() - 42,
                                fill=DIM, dash=(3, 3), tags="cursor")
        parts = [f"t={number(row.get('time_s')):.3f}s"]
        for field, label, _color in self.series:
            parts.append(f"{label}={number(row.get(field)):.3f}")
        text = "   ".join(parts)
        text_x = min(max(70, event.x + 8), max(70, self.canvas.winfo_width() - 310))
        self.canvas.create_rectangle(text_x - 4, event.y - 18, text_x + 300, event.y + 3,
                                     fill=PANEL, outline=GRID, tags="cursor")
        self.canvas.create_text(text_x, event.y - 8, anchor="w", text=text,
                                fill=TEXT, font=("TkDefaultFont", 8), tags="cursor")


class DragCsvViewer(tk.Tk):
    CHARTS = (
        ("Speed", "SPEED", "km/h", (("speed_kmh", "Speed", GREEN),), True),
        ("Acceleration", "ACCELERATION", "m/s²", (("acceleration_m_s2", "Acceleration", AMBER),), True),
        ("Power", "BATTERY POWER", "W", (("power_w", "Power", CYAN),), True),
        ("Energy", "ENERGY", "Wh", (("energy_used_wh", "Used", GREEN),
                                      ("energy_regen_wh", "Regen", CYAN),
                                      ("energy_net_wh", "Net", VIOLET)), True),
        ("Battery", "BATTERY VOLTAGE", "V", (("battery_voltage_v", "Voltage", BLUE),), False),
        ("Temperatures", "TEMPERATURES", "°C", (("mos_temp_c", "MOS", RED),
                                                  ("motor_temp_c", "Motor", AMBER)), False),
    )

    def __init__(self) -> None:
        super().__init__()
        self.title("VESC Drag Test CSV Viewer")
        self.geometry("1180x760")
        self.minsize(820, 560)
        self.configure(bg=BG)
        self.data: Optional[DragData] = None
        self.charts: List[LineChart] = []
        self.summary_values: Dict[str, tk.StringVar] = {}
        self._configure_style()
        self._build_ui()

    def _configure_style(self) -> None:
        style = ttk.Style(self)
        if "clam" in style.theme_names():
            style.theme_use("clam")
        style.configure(".", background=BG, foreground=TEXT)
        style.configure("TFrame", background=BG)
        style.configure("Panel.TFrame", background=PANEL)
        style.configure("TLabel", background=BG, foreground=TEXT)
        style.configure("Dim.TLabel", background=BG, foreground=DIM)
        style.configure("TButton", background=PANEL, foreground=TEXT, padding=7)
        style.map("TButton", background=[("active", "#30283d")])
        style.configure("TNotebook", background=BG, borderwidth=0)
        style.configure("TNotebook.Tab", background=PANEL, foreground=DIM, padding=(12, 6))
        style.map("TNotebook.Tab", background=[("selected", "#30283d")],
                  foreground=[("selected", GREEN)])
        style.configure("Treeview", background=PANEL, fieldbackground=PANEL,
                        foreground=TEXT, rowheight=23)
        style.configure("Treeview.Heading", background="#30283d", foreground=TEXT)

    def _build_ui(self) -> None:
        toolbar = ttk.Frame(self)
        toolbar.pack(fill=tk.X, padx=10, pady=(10, 5))
        ttk.Button(toolbar, text="Open CSV…", command=self.open_dialog).pack(side=tk.LEFT)
        self.path_var = tk.StringVar(value="No CSV loaded")
        ttk.Label(toolbar, textvariable=self.path_var, style="Dim.TLabel").pack(
            side=tk.LEFT, padx=12, fill=tk.X, expand=True)

        summary = ttk.Frame(self, style="Panel.TFrame")
        summary.pack(fill=tk.X, padx=10, pady=5)
        for column, key in enumerate(("Max speed", "0–40", "Distance", "Energy used",
                                      "Min voltage", "Max MOS", "Max motor")):
            summary.columnconfigure(column, weight=1)
            card = tk.Frame(summary, bg=PANEL, padx=8, pady=5)
            card.grid(row=0, column=column, sticky="nsew")
            tk.Label(card, text=key.upper(), bg=PANEL, fg=DIM, font=("TkDefaultFont", 8)).pack()
            value = tk.StringVar(value="—")
            self.summary_values[key] = value
            tk.Label(card, textvariable=value, bg=PANEL, fg=TEXT,
                     font=("TkDefaultFont", 11, "bold")).pack()

        notebook = ttk.Notebook(self)
        notebook.pack(fill=tk.BOTH, expand=True, padx=10, pady=(5, 10))
        for tab_name, title, unit, series, include_zero in self.CHARTS:
            chart = LineChart(notebook, title, unit, series, include_zero)
            notebook.add(chart, text=tab_name)
            self.charts.append(chart)

        table_frame = ttk.Frame(notebook)
        notebook.add(table_frame, text="Data")
        self.table = ttk.Treeview(table_frame, show="headings")
        x_scroll = ttk.Scrollbar(table_frame, orient=tk.HORIZONTAL, command=self.table.xview)
        y_scroll = ttk.Scrollbar(table_frame, orient=tk.VERTICAL, command=self.table.yview)
        self.table.configure(xscrollcommand=x_scroll.set, yscrollcommand=y_scroll.set)
        self.table.grid(row=0, column=0, sticky="nsew")
        y_scroll.grid(row=0, column=1, sticky="ns")
        x_scroll.grid(row=1, column=0, sticky="ew")
        table_frame.rowconfigure(0, weight=1)
        table_frame.columnconfigure(0, weight=1)

        menu = tk.Menu(self)
        file_menu = tk.Menu(menu, tearoff=False)
        file_menu.add_command(label="Open CSV…", command=self.open_dialog, accelerator="Ctrl+O")
        file_menu.add_separator()
        file_menu.add_command(label="Exit", command=self.destroy)
        menu.add_cascade(label="File", menu=file_menu)
        self.configure(menu=menu)
        self.bind_all("<Control-o>", lambda _event: self.open_dialog())

    def open_dialog(self) -> None:
        path = filedialog.askopenfilename(
            title="Open VESC drag-test CSV",
            filetypes=(("CSV files", "*.csv"), ("All files", "*.*")),
        )
        if path:
            self.open_file(path)

    def open_file(self, path: str) -> None:
        try:
            self.data = load_drag_csv(path)
        except (OSError, ValueError) as exc:
            messagebox.showerror("Unable to open CSV", str(exc), parent=self)
            return

        self.path_var.set(str(self.data.path))
        for chart in self.charts:
            chart.set_rows(self.data.rows)
        self._update_summary()
        self._update_table()
        self.title(f"VESC Drag Test CSV Viewer — {self.data.path.name}")

    def _update_summary(self) -> None:
        assert self.data is not None
        rows = self.data.rows
        max_speed = max(number(row.get("speed_kmh")) for row in rows)
        crossing_40 = interpolate_crossing(rows, 40.0)
        distance = max(number(row.get("distance_m")) for row in rows)
        energy = number(rows[-1].get("energy_used_wh"))
        voltages = [number(row.get("battery_voltage_v")) for row in rows
                    if number(row.get("battery_voltage_v")) > 0]
        max_mos = max(number(row.get("mos_temp_c")) for row in rows)
        max_motor = max(number(row.get("motor_temp_c")) for row in rows)
        self.summary_values["Max speed"].set(f"{max_speed:.1f} km/h")
        self.summary_values["0–40"].set("—" if crossing_40 is None else f"{crossing_40:.2f} s")
        self.summary_values["Distance"].set(f"{distance:.1f} m")
        self.summary_values["Energy used"].set(f"{energy:.3f} Wh")
        self.summary_values["Min voltage"].set("—" if not voltages else f"{min(voltages):.1f} V")
        self.summary_values["Max MOS"].set(f"{max_mos:.1f} °C")
        self.summary_values["Max motor"].set(f"{max_motor:.1f} °C")

    def _update_table(self) -> None:
        assert self.data is not None
        columns = list(self.data.rows[0].keys())
        self.table.delete(*self.table.get_children())
        self.table.configure(columns=columns)
        for column in columns:
            self.table.heading(column, text=column)
            self.table.column(column, width=max(90, len(column) * 8), stretch=False, anchor=tk.E)
        for row in self.data.rows:
            values = []
            for column in columns:
                value = row.get(column, "")
                values.append(f"{value:.6f}" if isinstance(value, float) else value)
            self.table.insert("", tk.END, values=values)


def main(argv: Optional[Sequence[str]] = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    viewer = DragCsvViewer()
    if arguments:
        viewer.after(0, lambda: viewer.open_file(arguments[0]))
    viewer.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
