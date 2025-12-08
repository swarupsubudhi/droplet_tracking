import tkinter as tk
from tkinter import ttk
import cv2
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from threading import Thread, Event, Lock
import time

# ----------------------------
# Simple threaded frame reader (single-frame buffer)
# ----------------------------
class FrameReader:
    def __init__(self, src_path):
        self.cap = cv2.VideoCapture(src_path)
        self.lock = Lock()
        self.frame = None
        self.pos = 0
        self.total = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT)) if self.cap.isOpened() else 0
        self.stop_event = Event()
        self.request_pos = None  # if set, seek to this frame
        self.thread = Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self):
        while not self.stop_event.is_set():
            if self.request_pos is not None:
                with self.lock:
                    try:
                        self.cap.set(cv2.CAP_PROP_POS_FRAMES, int(self.request_pos))
                    except Exception:
                        pass
                    self.request_pos = None
                time.sleep(0.01)
                continue
            ret, frm = self.cap.read()
            if not ret:
                time.sleep(0.05)
                continue
            with self.lock:
                self.frame = frm.copy()
                # CAP returns 1-based next pos; adjust to current frame index
                try:
                    self.pos = int(self.cap.get(cv2.CAP_PROP_POS_FRAMES)) - 1
                except Exception:
                    self.pos = 0
            time.sleep(0.01)

    def get_frame(self):
        with self.lock:
            return None if self.frame is None else self.frame.copy(), self.pos

    def seek(self, frame_idx):
        with self.lock:
            self.request_pos = int(frame_idx)

    def release(self):
        self.stop_event.set()
        self.thread.join(timeout=0.5)
        try:
            self.cap.release()
        except Exception:
            pass

# ----------------------------
# RangeSlider widget (two thumbs) for Tkinter
# ----------------------------
class RangeSlider(tk.Canvas):
    def __init__(self, master, from_=0, to=255, init_low=None, init_high=None,
                 width=300, height=36, step=1, **kwargs):
        super().__init__(master, width=width, height=height, highlightthickness=0, **kwargs)
        self.from_ = from_
        self.to = to
        self.step = step
        self.width = width
        self.height = height
        self.pad = 12
        self.track_y = height // 2
        self.radius = 8
        self.active = None
        self.callback = None

        if init_low is None:
            init_low = from_
        if init_high is None:
            init_high = to
        self.low = float(init_low)
        self.high = float(init_high)

        self.bind("<Button-1>", self._click)
        self.bind("<B1-Motion>", self._drag)
        self.bind("<ButtonRelease-1>", self._release)
        self._draw()

    def _val_to_x(self, v):
        frac = (v - self.from_) / (self.to - self.from_) if self.to != self.from_ else 0.0
        return int(self.pad + frac * (self.width - 2 * self.pad))

    def _x_to_val(self, x):
        frac = (x - self.pad) / (self.width - 2 * self.pad)
        frac = max(0.0, min(1.0, frac))
        val = self.from_ + frac * (self.to - self.from_)
        if self.step != 0:
            val = round(val / self.step) * self.step
        return float(val)

    def _draw(self):
        self.delete("all")
        x0 = self.pad
        x1 = self.width - self.pad
        self.create_line(x0, self.track_y, x1, self.track_y, fill="#ddd", width=4, capstyle="round")
        lx = self._val_to_x(self.low)
        hx = self._val_to_x(self.high)
        self.create_line(lx, self.track_y, hx, self.track_y, fill="#4caf50", width=6, capstyle="round")
        self.create_oval(lx - self.radius, self.track_y - self.radius, lx + self.radius, self.track_y + self.radius,
                         fill="#ffffff", outline="#333", width=1, tags="low_thumb")
        self.create_oval(hx - self.radius, self.track_y - self.radius, hx + self.radius, self.track_y + self.radius,
                         fill="#ffffff", outline="#333", width=1, tags="high_thumb")
        self.create_text(lx, self.track_y - 18, text=str(int(self.low)), font=("Segoe UI", 8), tags="low_text")
        self.create_text(hx, self.track_y - 18, text=str(int(self.high)), font=("Segoe UI", 8), tags="high_text")

    def _click(self, event):
        x = event.x
        lx = self._val_to_x(self.low)
        hx = self._val_to_x(self.high)
        if abs(x - lx) < abs(x - hx):
            self.active = "low"
        else:
            self.active = "high"
        self._move_to_x(x)

    def _drag(self, event):
        if not self.active:
            return
        self._move_to_x(event.x)

    def _release(self, event):
        self.active = None
        if self.callback:
            self.callback()

    def _move_to_x(self, x):
        val = self._x_to_val(x)
        if self.active == "low":
            self.low = min(max(self.from_, val), self.high)
        elif self.active == "high":
            self.high = max(min(self.to, val), self.low)
        self._draw()

    def get(self):
        return int(self.low), int(self.high)

    def set(self, low, high):
        self.low = float(max(self.from_, min(low, self.to)))
        self.high = float(max(self.from_, min(high, self.to)))
        if self.low > self.high:
            self.low, self.high = self.high, self.low
        self._draw()

    def set_callback(self, fn):
        self.callback = fn

# ----------------------------
# Detection using per-view parameters (RangeSliders)
# ----------------------------
def detect_circle_with_params_from_sliders(crop, params):
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    h_low, h_high = params['h_range']
    s_low, s_high = params['s_range']
    v_low, v_high = params['v_range']
    lower = np.array([h_low, s_low, v_low], dtype=np.uint8)
    upper = np.array([h_high, s_high, v_high], dtype=np.uint8)
    mask = cv2.inRange(hsv, lower, upper)
    masked = cv2.bitwise_and(crop, crop, mask=mask)
    cv2.imshow("Masked Output", mask)

    r_w, g_w, b_w = params['r_w'], params['g_w'], params['b_w']
    ssum = r_w + g_w + b_w
    if ssum == 0:
        r_n, g_n, b_n = 0.333, 0.333, 0.333
    else:
        r_n, g_n, b_n = r_w / ssum, g_w / ssum, b_w / ssum
    gray = (masked[..., 0] * b_n + masked[..., 1] * g_n + masked[..., 2] * r_n).astype(np.uint8)

    blur = cv2.GaussianBlur(gray, (9, 9), 2)

    circles = cv2.HoughCircles(
        blur, cv2.HOUGH_GRADIENT,
        dp=float(params['dp']), minDist=int(params['minDist']),
        param1=int(params['param1']), param2=int(params['param2']),
        minRadius=int(params['minRadius']), maxRadius=int(params['maxRadius'])
    )
    if circles is not None and len(circles) > 0:
        circles = np.round(circles[0, :]).astype("int")
        x, y, r = max(circles, key=lambda c: c[2])
        return (x, y, r)
    return (np.nan, np.nan, np.nan)

# ----------------------------
# Main UI with threaded reader and RangeSlider (patched layout using grid)
# ----------------------------
class DropletTrackerUI:
    def __init__(self, root, video_path, start_frame=0):
        self.root = root
        self.root.title("Droplet Tracker v0.2.22 — Diagnostic (threaded + ranges)")

        # Frame reader
        self.reader = FrameReader(video_path)
        self.total_frames = self.reader.total
        self.frame_idx = max(0, min(start_frame, self.total_frames - 1)) if self.total_frames > 0 else 0
        if self.total_frames > 0:
            self.reader.seek(self.frame_idx)

        # Running state
        self.running = False
        self.paused = False

        # metrics
        self.front_metrics, self.side_metrics = [], []

        # Layout (left analysis, right controls)
        left_column = ttk.Frame(root)
        left_column.grid(row=0, column=0, padx=8, pady=8, sticky="nw")

        self.front_frame = ttk.Frame(left_column)
        self.side_frame = ttk.Frame(left_column)
        self.front_frame.grid(row=0, column=0, padx=4, pady=4, sticky="w")
        self.side_frame.grid(row=1, column=0, padx=4, pady=4, sticky="w")

        # video display labels
        self.front_label = tk.Label(self.front_frame)
        self.side_label = tk.Label(self.side_frame)
        self.front_label.pack(side=tk.LEFT)
        self.side_label.pack(side=tk.LEFT)

        # compact plots
        self.front_fig, self.front_axes = plt.subplots(1, 4, figsize=(9, 2.6))
        self.side_fig, self.side_axes = plt.subplots(1, 4, figsize=(9, 2.6))
        self.front_canvas = FigureCanvasTkAgg(self.front_fig, master=self.front_frame)
        self.side_canvas = FigureCanvasTkAgg(self.side_fig, master=self.side_frame)
        self.front_canvas.get_tk_widget().pack(side=tk.RIGHT, padx=6)
        self.side_canvas.get_tk_widget().pack(side=tk.RIGHT, padx=6)

        # log under plots
        log_frame = ttk.Frame(left_column)
        log_frame.grid(row=2, column=0, sticky="ew", pady=(6, 0))
        self.log_box = tk.Text(log_frame, height=8, width=120)
        self.log_box.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.log_box.configure(state="disabled")
        log_scroll = ttk.Scrollbar(log_frame, command=self.log_box.yview)
        log_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.log_box.configure(yscrollcommand=log_scroll.set)

        # Right column controls
        right_column = ttk.Frame(root)
        right_column.grid(row=0, column=1, padx=8, pady=8, sticky="ne")

        control_frame = ttk.Frame(right_column)
        control_frame.pack(side=tk.TOP, fill=tk.X)

        # Seek slider
        self.seek_slider = tk.Scale(control_frame, from_=0, to=max(0, self.total_frames - 1),
                                    orient=tk.HORIZONTAL, length=400, label="Seek Frame")
        self.seek_slider.set(self.frame_idx)
        self.seek_slider.pack(side=tk.TOP, fill=tk.X, padx=5, pady=5)
        self.seek_slider.bind("<ButtonRelease-1>", self.seek_to_frame)

        # Buttons
        btns = ttk.Frame(control_frame)
        btns.pack(side=tk.TOP, fill=tk.X, pady=(4, 4))
        self.start0_btn = tk.Button(btns, text="Start from 0", command=self.start_from_zero)
        self.play_btn   = tk.Button(btns, text="Play", command=self.play_from_seek)
        self.pause_btn  = tk.Button(btns, text="Pause", command=self.toggle_pause)
        self.stop_btn   = tk.Button(btns, text="Stop", command=self.stop_processing)
        self.start0_btn.pack(side=tk.LEFT, padx=4)
        self.play_btn.pack(side=tk.LEFT, padx=4)
        self.pause_btn.pack(side=tk.LEFT, padx=4)
        self.stop_btn.pack(side=tk.LEFT, padx=4)

        self.status_label = tk.Label(control_frame, text="Status: Idle", fg="blue")
        self.status_label.pack(side=tk.LEFT, padx=10)

        # Params notebook
        params_container = ttk.Notebook(right_column)
        params_container.pack(side=tk.TOP, fill=tk.BOTH, expand=True, pady=(8, 8))
        self.front_params_frame = ttk.Frame(params_container)
        self.side_params_frame = ttk.Frame(params_container)
        params_container.add(self.front_params_frame, text="Front View Params")
        params_container.add(self.side_params_frame, text="Side View Params")

        # Build slider controls with RangeSliders for H,S,V using grid layout
        self._build_param_sliders_grid(self.front_params_frame, view="front")
        self._build_param_sliders_grid(self.side_params_frame, view="side")

        # Start UI updater
        self._ui_update_loop()

    # ----------------------------
    # Build param sliders using grid (patched)
    # ----------------------------
    def _build_param_sliders_grid(self, parent, view="front"):
        inner = ttk.Frame(parent)
        inner.pack(fill="both", expand=True, padx=8, pady=8)

        row = 0
        ttk.Label(inner, text="HSV Ranges (H, S, V)", font=("Segoe UI", 9, "bold")).grid(row=row, column=0, columnspan=2, sticky="w")
        row += 1

        ttk.Label(inner, text="H range").grid(row=row, column=0, sticky="w", pady=4)
        h_range = RangeSlider(inner, from_=0, to=180, init_low=170, init_high=180, width=300)
        h_range.grid(row=row, column=1, sticky="w", padx=6)
        row += 1

        ttk.Label(inner, text="S range").grid(row=row, column=0, sticky="w", pady=4)
        s_range = RangeSlider(inner, from_=0, to=255, init_low=30, init_high=100, width=300)
        s_range.grid(row=row, column=1, sticky="w", padx=6)
        row += 1

        ttk.Label(inner, text="V range").grid(row=row, column=0, sticky="w", pady=4)
        v_range = RangeSlider(inner, from_=0, to=255, init_low=40, init_high=150, width=300)
        v_range.grid(row=row, column=1, sticky="w", padx=6)
        row += 1

        ttk.Label(inner, text="HoughCircles", font=("Segoe UI", 9, "bold")).grid(row=row, column=0, columnspan=2, sticky="w", pady=(8,4))
        row += 1

        def add_slider_grid(label_text, default, rng):
            nonlocal row
            ttk.Label(inner, text=label_text).grid(row=row, column=0, sticky="w", pady=4)
            s = tk.Scale(inner, from_=rng[0], to=rng[1], orient=tk.HORIZONTAL, length=300)
            s.set(default)
            s.grid(row=row, column=1, sticky="w", padx=6)
            row += 1
            return s

        dp_s = add_slider_grid("dp", 1.2, (1.0, 3.0))
        minDist_s = add_slider_grid("minDist", 20, (5, 250))
        p1_s = add_slider_grid("param1", 50, (10, 300))
        p2_s = add_slider_grid("param2", 50, (10, 200))
        minR_s = add_slider_grid("minRadius", 30, (1, 300))
        maxR_s = add_slider_grid("maxRadius", 100, (1, 400))

        ttk.Label(inner, text="Grayscale weights (R,G,B)", font=("Segoe UI", 9, "bold")).grid(row=row, column=0, columnspan=2, sticky="w", pady=(8,4))
        row += 1

        ttk.Label(inner, text="R").grid(row=row, column=0, sticky="w", pady=4)
        r_w = tk.Scale(inner, from_=0.0, to=1.0, orient=tk.HORIZONTAL, resolution=0.05, length=300)
        r_w.set(0.33); r_w.grid(row=row, column=1, sticky="w", padx=6); row += 1

        ttk.Label(inner, text="G").grid(row=row, column=0, sticky="w", pady=4)
        g_w = tk.Scale(inner, from_=0.0, to=1.0, orient=tk.HORIZONTAL, resolution=0.05, length=300)
        g_w.set(0.33); g_w.grid(row=row, column=1, sticky="w", padx=6); row += 1

        ttk.Label(inner, text="B").grid(row=row, column=0, sticky="w", pady=4)
        b_w = tk.Scale(inner, from_=0.0, to=1.0, orient=tk.HORIZONTAL, resolution=0.05, length=300)
        b_w.set(0.33); b_w.grid(row=row, column=1, sticky="w", padx=6); row += 1

        setattr(self, f"{view}_h_range", h_range)
        setattr(self, f"{view}_s_range", s_range)
        setattr(self, f"{view}_v_range", v_range)
        setattr(self, f"{view}_dp", dp_s); setattr(self, f"{view}_minDist", minDist_s)
        setattr(self, f"{view}_param1", p1_s); setattr(self, f"{view}_param2", p2_s)
        setattr(self, f"{view}_minRadius", minR_s); setattr(self, f"{view}_maxRadius", maxR_s)
        setattr(self, f"{view}_r_w", r_w); setattr(self, f"{view}_g_w", g_w); setattr(self, f"{view}_b_w", b_w)

    # ----------------------------
    # Read parameters from controls
    # ----------------------------
    def get_params(self, view="front"):
        h_low, h_high = getattr(self, f"{view}_h_range").get()
        s_low, s_high = getattr(self, f"{view}_s_range").get()
        v_low, v_high = getattr(self, f"{view}_v_range").get()
        return {
            'h_range': (h_low, h_high),
            's_range': (s_low, s_high),
            'v_range': (v_low, v_high),
            'dp': getattr(self, f"{view}_dp").get(),
            'minDist': getattr(self, f"{view}_minDist").get(),
            'param1': getattr(self, f"{view}_param1").get(),
            'param2': getattr(self, f"{view}_param2").get(),
            'minRadius': getattr(self, f"{view}_minRadius").get(),
            'maxRadius': getattr(self, f"{view}_maxRadius").get(),
            'r_w': getattr(self, f"{view}_r_w").get(),
            'g_w': getattr(self, f"{view}_g_w").get(),
            'b_w': getattr(self, f"{view}_b_w").get(),
        }

    # ----------------------------
    # Controls (Start0, Play, Pause, Stop)
    # ----------------------------
    def start_from_zero(self):
        if self.total_frames == 0:
            self.log("Video not opened.")
            return
        self.frame_idx = 0
        self.reader.seek(self.frame_idx)
        self.seek_slider.set(self.frame_idx)
        self.front_metrics.clear(); self.side_metrics.clear()
        self.running = True; self.paused = False
        self.status_label.config(text="Status: Processing", fg="green")
        self.pause_btn.config(text="Pause")
        self.log("Computation started from frame 0")
        self.log_resume_params()
        self._process_loop_once()

    def play_from_seek(self):
        if self.total_frames == 0:
            self.log("Video not opened.")
            return
        target = self.seek_slider.get()
        self.frame_idx = target
        self.reader.seek(self.frame_idx)
        self.front_metrics.clear(); self.side_metrics.clear()
        self.running = True; self.paused = False
        self.status_label.config(text="Status: Processing", fg="green")
        self.pause_btn.config(text="Pause")
        self.log(f"Computation started from seek frame {target}")
        self.log_resume_params()
        self._process_loop_once()

    def toggle_pause(self):
        if not self.running:
            self.play_from_seek()
            return
        if self.paused:
            self.paused = False
            self.status_label.config(text="Status: Processing", fg="green")
            self.pause_btn.config(text="Pause")
            self.log("Computation resumed")
            self.log_resume_params()
            self._process_loop_once()
        else:
            self.paused = True
            self.status_label.config(text="Status: Paused", fg="orange")
            self.pause_btn.config(text="Resume")
            self.log("Computation paused")

    def stop_processing(self):
        if not self.running and not self.paused:
            return
        self.running = False
        self.paused = False
        self.status_label.config(text="Status: Stopped", fg="red")
        self.pause_btn.config(text="Pause")
        self.log("Computation stopped")

    # Seek handler only when paused/stopped
    def seek_to_frame(self, event=None):
        if self.running and not self.paused:
            return
        if self.total_frames == 0:
            self.log("Video not opened.")
            return
        frame_num = self.seek_slider.get()
        self.frame_idx = frame_num
        self.reader.seek(frame_num)
        self.log(f"Seeked to frame {frame_num}")
        self.show_single_frame()

    # ----------------------------
    # Logging helpers
    # ----------------------------
    def log(self, message):
        self.log_box.configure(state="normal")
        self.log_box.insert(tk.END, message + "\n")
        self.log_box.see(tk.END)
        self.log_box.configure(state="disabled")

    def log_resume_params(self):
        fp = self.get_params("front"); sp = self.get_params("side")
        self.log(
            "Parameters on start/resume:\n"
            f"  Front: H={fp['h_range']}, S={fp['s_range']}, V={fp['v_range']}, "
            f"Hough(dp={fp['dp']},minD={fp['minDist']},p1={fp['param1']},p2={fp['param2']},r=[{fp['minRadius']}-{fp['maxRadius']}]), "
            f"Gray(R={fp['r_w']:.2f},G={fp['g_w']:.2f},B={fp['b_w']:.2f})\n"
            f"  Side:  H={sp['h_range']}, S={sp['s_range']}, V={sp['v_range']}, "
            f"Hough(dp={sp['dp']},minD={sp['minDist']},p1={sp['param1']},p2={sp['param2']},r=[{sp['minRadius']}-{sp['maxRadius']}]), "
            f"Gray(R={sp['r_w']:.2f},G={sp['g_w']:.2f},B={sp['b_w']:.2f})"
        )

    # ----------------------------
    # Processing loop
    # ----------------------------
    def _process_loop_once(self):
        if not self.running or self.paused:
            return
        frm, pos = self.reader.get_frame()
        if frm is None:
            self.root.after(25, self._process_loop_once)
            return
        self.frame_idx = pos
        frm_resized = cv2.resize(frm, (1920, 540))
        side_crop = frm_resized[:, 240:240+480]
        front_crop = frm_resized[:, 1200:1200+480]

        self._process_and_display_view("front", front_crop, self.front_label, self.front_metrics)
        self._process_and_display_view("side", side_crop, self.side_label, self.side_metrics)
        self.update_plots()

        self.seek_slider.set(self.frame_idx)
        self.root.after(30, self._process_loop_once)

    # UI preview loop (when not running)
    def _ui_update_loop(self):
        if not self.running:
            frm, pos = self.reader.get_frame()
            if frm is not None:
                frm_resized = cv2.resize(frm, (1920, 540))
                side_crop = frm_resized[:, 240:240+480]
                front_crop = frm_resized[:, 1200:1200+480]
                self._process_and_display_view("front", front_crop, self.front_label, None)
                self._process_and_display_view("side", side_crop, self.side_label, None)
        self.root.after(100, self._ui_update_loop)

    def show_single_frame(self):
        frm, pos = self.reader.get_frame()
        if frm is None:
            self.log("Seek frame read error.")
            return
        frm_resized = cv2.resize(frm, (1920, 540))
        side_crop = frm_resized[:, 240:240+480]
        front_crop = frm_resized[:, 1200:1200+480]
        self._process_and_display_view("front", front_crop, self.front_label, None)
        self._process_and_display_view("side", side_crop, self.side_label, None)

    # Shared view processing
    def _process_and_display_view(self, view_name, crop, label, metrics_list):
        params = self.get_params(view_name)
        x, y, r = detect_circle_with_params_from_sliders(crop, params)
        if metrics_list is not None:
            if np.isnan(x):
                self.log(f"Processing frame {self.frame_idx} ({view_name})... Droplet not tracked")
            else:
                self.log(f"Processing frame {self.frame_idx} ({view_name})...")
        if not np.isnan(x):
            cv2.circle(crop, (int(x), int(y)), int(r), (0, 255, 0), 2)
            circ = 2 * np.pi * r
            cv2.putText(crop, f"C={circ:.1f}", (int(x + r + 5), int(y)),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1, cv2.LINE_AA)
        if metrics_list is not None:
            metrics_list.append((x, y, r))

        h, w = crop.shape[:2]
        max_width, max_height = 480, 270
        scale = min(max_width / w, max_height / h)
        new_size = (int(w * scale), int(h * scale))
        disp = cv2.resize(crop, new_size)
        disp = cv2.cvtColor(disp, cv2.COLOR_BGR2RGB)
        success, png = cv2.imencode('.png', disp)
        if success:
            img = tk.PhotoImage(master=self.root, data=png.tobytes())
            label.configure(image=img)
            label.image = img

    # Plot updates
    def update_plots(self):
        def dist(arr):
            xs = [p[0] if not np.isnan(p[0]) else 0 for p in arr]
            ys = [p[1] if not np.isnan(p[1]) else 0 for p in arr]
            return np.sqrt(np.diff(xs, prepend=xs[0] if xs else 0)**2 +
                           np.diff(ys, prepend=ys[0] if ys else 0)**2)
        def smooth(arr):
            if len(arr) == 0: return arr
            return np.convolve(arr, np.ones(5)/5, mode='same')
        def accel(arr):
            if len(arr) == 0: return arr
            return np.diff(arr, prepend=arr[0])
        def radius(arr):
            return [p[2] for p in arr]
        def circumference(arr):
            return [2*np.pi*p[2] if not np.isnan(p[2]) else np.nan for p in arr]

        for metrics, axes, canvas in [
            (self.front_metrics, self.front_axes, self.front_canvas),
            (self.side_metrics,  self.side_axes,  self.side_canvas),
        ]:
            labels = ["Distance", "Velocity", "Acceleration", "Radius"]
            series = [
                dist(metrics), smooth(dist(metrics)), accel(smooth(dist(metrics))), radius(metrics)
            ]
            for ax, label, data in zip(axes, labels, series):
                ax.cla()
                ax.plot(data, label=label, color="steelblue")
                if label == "Radius":
                    ax.plot(circumference(metrics), label="Circumference", linestyle="--", color="darkorange")
                ax.set_title(label)
                ax.legend(fontsize=7)
                ax.grid(True)
            canvas.draw()

    def close(self):
        try:
            self.reader.release()
        except Exception:
            pass

# ----------------------------
# Main execution
# ----------------------------
if __name__ == "__main__":
    VIDEO_PATH = "C:/Research_Files_Swarup/R11-DropsCT/Expt_Data/Raw_Data_Videos/S25.mp4"
    START_FRAME = 0

    root = tk.Tk()
    app = DropletTrackerUI(root, VIDEO_PATH, START_FRAME)
    root.protocol("WM_DELETE_WINDOW", lambda: (app.close(), root.destroy()))
    root.mainloop()