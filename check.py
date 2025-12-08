import tkinter as tk
from tkinter import ttk
import cv2
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg

# ----------------------------
# Detection using per-view parameters
# ----------------------------
def detect_circle_with_params(crop, params):
    """Detect circle using HSV thresholds, custom grayscale weights, and HoughCircles."""
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    lower = np.array([params["lower_h"], params["lower_s"], params["lower_v"]], dtype=np.uint8)
    upper = np.array([params["upper_h"], params["upper_s"], params["upper_v"]], dtype=np.uint8)
    mask = cv2.inRange(hsv, lower, upper)
    masked = cv2.bitwise_and(crop, crop, mask=mask)

    # Custom grayscale conversion with normalized coefficients
    r_w, g_w, b_w = params["r_w"], params["g_w"], params["b_w"]
    s = r_w + g_w + b_w
    if s == 0:
        r_w_n, g_w_n, b_w_n = 0.333, 0.333, 0.333
    else:
        r_w_n, g_w_n, b_w_n = r_w / s, g_w / s, b_w / s
    gray = (masked[..., 0] * b_w_n + masked[..., 1] * g_w_n + masked[..., 2] * r_w_n).astype(np.uint8)

    blur = cv2.GaussianBlur(gray, (9, 9), 2)

    circles = cv2.HoughCircles(
        blur, cv2.HOUGH_GRADIENT,
        dp=params["dp"], minDist=int(params["minDist"]),
        param1=int(params["param1"]), param2=int(params["param2"]),
        minRadius=int(params["minRadius"]), maxRadius=int(params["maxRadius"])
    )

    if circles is not None:
        circles = np.round(circles[0, :]).astype("int")
        x, y, r = max(circles, key=lambda c: c[2])
        return (x, y, r)
    return (np.nan, np.nan, np.nan)


class DropletTrackerUI:
    def __init__(self, root, video_path, start_frame=0):
        self.root = root
        self.cap = cv2.VideoCapture(video_path)
        self.total_frames = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))
        if start_frame > 0:
            self.cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
        self.frame_idx = start_frame

        self.running = False
        self.paused = False

        self.front_metrics, self.side_metrics = [], []

        # ----------------------------
        # Layout: left = video+plots+log, right = controls+params
        # ----------------------------
        left_column = ttk.Frame(root)
        left_column.grid(row=0, column=0, padx=10, pady=10, sticky="nw")

        self.front_frame = ttk.Frame(left_column)
        self.side_frame = ttk.Frame(left_column)
        self.front_frame.grid(row=0, column=0, padx=5, pady=5, sticky="w")
        self.side_frame.grid(row=1, column=0, padx=5, pady=5, sticky="w")

        self.front_label = tk.Label(self.front_frame)
        self.side_label = tk.Label(self.side_frame)
        self.front_label.pack(side=tk.LEFT)
        self.side_label.pack(side=tk.LEFT)

        self.front_fig, self.front_axes = plt.subplots(1, 4, figsize=(12, 3))
        self.side_fig, self.side_axes = plt.subplots(1, 4, figsize=(12, 3))
        self.front_canvas = FigureCanvasTkAgg(self.front_fig, master=self.front_frame)
        self.side_canvas = FigureCanvasTkAgg(self.side_fig, master=self.side_frame)
        self.front_canvas.get_tk_widget().pack(side=tk.RIGHT, padx=10)
        self.side_canvas.get_tk_widget().pack(side=tk.RIGHT, padx=10)

        # Log box below graphs
        log_frame = ttk.Frame(left_column)
        log_frame.grid(row=2, column=0, sticky="ew", pady=(10, 0))
        self.log_box = tk.Text(log_frame, height=10, width=120)
        self.log_box.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.log_box.configure(state="disabled")
        log_scroll = ttk.Scrollbar(log_frame, command=self.log_box.yview)
        log_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.log_box.configure(yscrollcommand=log_scroll.set)

        # Right column: controls + params
        right_column = ttk.Frame(root)
        right_column.grid(row=0, column=1, padx=10, pady=10, sticky="ne")

        control_frame = ttk.Frame(right_column)
        control_frame.pack(side=tk.TOP, fill=tk.X)

        # Seek slider
        self.seek_slider = tk.Scale(control_frame, from_=0, to=self.total_frames-1,
                                    orient=tk.HORIZONTAL, length=300, label="Seek Frame")
        self.seek_slider.set(self.frame_idx)
        self.seek_slider.pack(side=tk.TOP, fill=tk.X, padx=5, pady=5)
        self.seek_slider.bind("<ButtonRelease-1>", self.seek_to_frame)

        # Buttons
        self.start0_btn = tk.Button(control_frame, text="Start from 0", command=self.start_from_zero)
        self.play_btn   = tk.Button(control_frame, text="Play", command=self.play_from_seek)
        self.pause_btn  = tk.Button(control_frame, text="Pause", command=self.toggle_pause)
        self.stop_btn   = tk.Button(control_frame, text="Stop", command=self.stop_processing)
        self.start0_btn.pack(side=tk.LEFT, padx=5)
        self.play_btn.pack(side=tk.LEFT, padx=5)
        self.pause_btn.pack(side=tk.LEFT, padx=5)
        self.stop_btn.pack(side=tk.LEFT, padx=5)

        self.status_label = tk.Label(control_frame, text="Status: Idle", fg="blue")
        self.status_label.pack(side=tk.LEFT, padx=10)

        # Parameter tabs
        params_container = ttk.Notebook(right_column)
        params_container.pack(side=tk.TOP, fill=tk.BOTH, expand=True, pady=(10, 10))
        self.front_params_frame = ttk.Frame(params_container)
        self.side_params_frame = ttk.Frame(params_container)
        params_container.add(self.front_params_frame, text="Front View Params")
        params_container.add(self.side_params_frame, text="Side View Params")
        self._build_param_sliders(self.front_params_frame, view="front")
        self._build_param_sliders(self.side_params_frame, view="side")

    # ----------------------------
    # Build parameter sliders
    # ----------------------------
    def _build_param_sliders(self, parent, view="front"):
        def add_slider(row, label, from_, to_, resolution, initial):
            lbl = ttk.Label(parent, text=label)
            lbl.grid(row=row, column=0, sticky="w", padx=4, pady=2)
            s = tk.Scale(parent, from_=from_, to=to_, resolution=resolution,
                         orient=tk.HORIZONTAL, length=220)
            s.set(initial)
            s.grid(row=row, column=1, sticky="ew", padx=4, pady=2)
            return s

        ttk.Label(parent, text="HSV Thresholds").grid(row=0, column=0, columnspan=2, sticky="w", pady=(6, 2))
        setattr(self, f"{view}_lower_h", add_slider(1, "Lower H", 0, 180, 1, 170))
        setattr(self, f"{view}_lower_s", add_slider(2, "Lower S", 0, 255, 1, 30))
        setattr(self, f"{view}_lower_v", add_slider(3, "Lower V", 0, 255, 1, 40))
        setattr(self, f"{view}_upper_h", add_slider(4, "Upper H", 0, 180, 1, 180))
        setattr(self, f"{view}_upper_s", add_slider(5, "Upper S", 0, 255, 1, 100))
        setattr(self, f"{view}_upper_v", add_slider(6, "Upper V", 0, 255, 1, 150))

        ttk.Label(parent, text="HoughCircles").grid(row=7, column=0, columnspan=2, sticky="w", pady=(10, 2))
        setattr(self, f"{view}_dp",        add_slider(8,