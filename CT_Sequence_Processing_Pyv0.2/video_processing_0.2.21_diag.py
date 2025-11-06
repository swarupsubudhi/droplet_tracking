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
        setattr(self, f"{view}_dp",        add_slider(8,  "dp",        1.0, 3.0, 0.1, 1.2))
        setattr(self, f"{view}_minDist",   add_slider(9,  "minDist",   5,   250, 1,   20))
        setattr(self, f"{view}_param1",    add_slider(10, "param1",    10,  300, 1,   50))
        setattr(self, f"{view}_param2",    add_slider(11, "param2",    10,  200, 1,   50))
        setattr(self, f"{view}_minRadius", add_slider(12, "minRadius", 1,   300, 1,   30))
        setattr(self, f"{view}_maxRadius", add_slider(13, "maxRadius", 1,   400, 1,   100))

        ttk.Label(parent, text="Grayscale Weights (R, G, B)").grid(row=14, column=0, columnspan=2, sticky="w", pady=(10, 2))
        setattr(self, f"{view}_r_w", add_slider(15, "R weight", 0.0, 1.0, 0.05, 0.33))
        setattr(self, f"{view}_g_w", add_slider(16, "G weight", 0.0, 1.0, 0.05, 0.33))
        setattr(self, f"{view}_b_w", add_slider(17, "B weight", 0.0, 1.0, 0.05, 0.33))

        parent.columnconfigure(1, weight=1)

    # ----------------------------
    # Read parameters from sliders
    # ----------------------------
    def get_params(self, view="front"):
        def gv(name): return getattr(self, f"{view}_{name}").get()
        return {
            "lower_h": gv("lower_h"), "lower_s": gv("lower_s"), "lower_v": gv("lower_v"),
            "upper_h": gv("upper_h"), "upper_s": gv("upper_s"), "upper_v": gv("upper_v"),
            "dp": gv("dp"), "minDist": gv("minDist"),
            "param1": gv("param1"), "param2": gv("param2"),
            "minRadius": gv("minRadius"), "maxRadius": gv("maxRadius"),
            "r_w": gv("r_w"), "g_w": gv("g_w"), "b_w": gv("b_w"),
        }

    # ----------------------------
    # Controls: Start from 0, Play from seek, Pause/Resume, Stop
    # ----------------------------
    def start_from_zero(self):
        if not self.cap.isOpened():
            self.log("Video not opened.")
            return
        self.frame_idx = 0
        self.cap.set(cv2.CAP_PROP_POS_FRAMES, self.frame_idx)
        self.seek_slider.set(self.frame_idx)
        self.front_metrics.clear()
        self.side_metrics.clear()
        self.running = True
        self.paused = False
        self.status_label.config(text="Status: Processing", fg="green")
        self.pause_btn.config(text="Pause")
        self.log("Computation started from frame 0")
        self.log_resume_params()
        self.update_frame()

    def play_from_seek(self):
        if not self.cap.isOpened():
            self.log("Video not opened.")
            return
        # Start from the frame set via seek slider
        target = self.seek_slider.get()
        self.frame_idx = target
        self.cap.set(cv2.CAP_PROP_POS_FRAMES, self.frame_idx)
        self.front_metrics.clear()
        self.side_metrics.clear()
        self.running = True
        self.paused = False
        self.status_label.config(text="Status: Processing", fg="green")
        self.pause_btn.config(text="Pause")
        self.log(f"Computation started from seek frame {target}")
        self.log_resume_params()
        self.update_frame()

    def toggle_pause(self):
        if not self.running:
            # If stopped/idle, toggling pause acts as resume from seek
            self.play_from_seek()
            return
        if self.paused:
            # Resume
            self.paused = False
            self.status_label.config(text="Status: Processing", fg="green")
            self.pause_btn.config(text="Pause")
            self.log("Computation resumed")
            self.log_resume_params()
            self.update_frame()
        else:
            # Pause
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

    # ----------------------------
    # Seek handler (active only when paused or stopped)
    # ----------------------------
    def seek_to_frame(self, event=None):
        if self.running and not self.paused:
            # Ignore seeks during active processing
            return
        if not self.cap.isOpened():
            self.log("Video not opened.")
            return
        frame_num = self.seek_slider.get()
        self.frame_idx = frame_num
        self.cap.set(cv2.CAP_PROP_POS_FRAMES, frame_num)
        self.log(f"Seeked to frame {frame_num}")
        # Show processed single frame using current parameters
        self.show_single_frame()

    # ----------------------------
    # Logging
    # ----------------------------
    def log(self, message):
        self.log_box.configure(state="normal")
        self.log_box.insert(tk.END, message + "\n")
        self.log_box.see(tk.END)  # auto-scroll to latest
        self.log_box.configure(state="disabled")

    def log_resume_params(self):
        fp = self.get_params("front")
        sp = self.get_params("side")
        self.log(
            "Parameters on start/resume:\n"
            f"  Front: HSV=({fp['lower_h']}-{fp['upper_h']}, {fp['lower_s']}-{fp['upper_s']}, {fp['lower_v']}-{fp['upper_v']}), "
            f"Hough(dp={fp['dp']:.1f}, minDist={fp['minDist']}, p1={fp['param1']}, p2={fp['param2']}, r=[{fp['minRadius']}-{fp['maxRadius']}]), "
            f"Gray(R={fp['r_w']:.2f}, G={fp['g_w']:.2f}, B={fp['b_w']:.2f})\n"
            f"  Side:  HSV=({sp['lower_h']}-{sp['upper_h']}, {sp['lower_s']}-{sp['upper_s']}, {sp['lower_v']}-{sp['upper_v']}), "
            f"Hough(dp={sp['dp']:.1f}, minDist={sp['minDist']}, p1={sp['param1']}, p2={sp['param2']}, r=[{sp['minRadius']}-{sp['maxRadius']}]), "
            f"Gray(R={sp['r_w']:.2f}, G={sp['g_w']:.2f}, B={sp['b_w']:.2f})"
        )

    # ----------------------------
    # Main update loop (processing)
    # ----------------------------
    def update_frame(self):
        if not self.running or self.paused:
            return

        ret, frame = self.cap.read()
        if not ret:
            self.log("End of video or read error.")
            self.stop_processing()
            return

        # Resize stitched video to expected size (adjust if different in your setup)
        frame = cv2.resize(frame, (1920, 540))
        side_crop = frame[:, 240:240+480]
        front_crop = frame[:, 1200:1200+480]

        # Process both views: save raw, detect, overlay, save processed, display
        self._process_and_display_view("front", front_crop, self.front_label, self.front_metrics)
        self._process_and_display_view("side", side_crop, self.side_label, self.side_metrics)

        # Update plots
        self.update_plots()

        # Next frame
        self.frame_idx += 1
        self.root.after(100, self.update_frame)

    # ----------------------------
    # Single frame preview for seek
    # ----------------------------
    def show_single_frame(self):
        # Read the exact frame set via CAP_PROP_POS_FRAMES (do not advance)
        pos_before = int(self.cap.get(cv2.CAP_PROP_POS_FRAMES))
        ret, frame = self.cap.read()
        if not ret:
            self.log("Seek frame read error.")
            return
        # Reset CAP position to current frame index to avoid advancing
        self.cap.set(cv2.CAP_PROP_POS_FRAMES, pos_before)

        frame = cv2.resize(frame, (1920, 540))
        side_crop = frame[:, 240:240+480]
        front_crop = frame[:, 1200:1200+480]

        # Display processed previews without updating metrics or plots
        self._process_and_display_view("front", front_crop, self.front_label, None)
        self._process_and_display_view("side", side_crop, self.side_label, None)

    # ----------------------------
    # Shared view processing
    # ----------------------------
    def _process_and_display_view(self, view_name, crop, label, metrics_list):
        # Detect with current per-view parameters
        params = self.get_params(view_name)
        x, y, r = detect_circle_with_params(crop, params)

        # Log per-frame with detection status
        if metrics_list is not None:
            if np.isnan(x):
                self.log(f"Processing frame {self.frame_idx} ({view_name})... Droplet not tracked")
            else:
                self.log(f"Processing frame {self.frame_idx} ({view_name})...")

        # Overlay circle and circumference text if found
        if not np.isnan(x):
            cv2.circle(crop, (int(x), int(y)), int(r), (0, 255, 0), 2)
            circ = 2 * np.pi * r
            cv2.putText(
                crop, f"C={circ:.1f}", (int(x + r + 5), int(y)),
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1, cv2.LINE_AA
            )

        # Preserve aspect ratio for display
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

        # Update metrics list if provided
        if metrics_list is not None:
            metrics_list.append((x, y, r))

    # ----------------------------
    # Plot updates
    # ----------------------------
    def update_plots(self):
        def dist(arr):
            xs = [p[0] for p in arr]
            ys = [p[1] for p in arr]
            return np.sqrt(np.diff(xs, prepend=0)**2 + np.diff(ys, prepend=0)**2)

        def smooth(arr):
            if len(arr) == 0:
                return arr
            return np.convolve(arr, np.ones(5)/5, mode='same')

        def accel(arr):
            if len(arr) == 0:
                return arr
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
                dist(metrics),
                smooth(dist(metrics)),
                accel(smooth(dist(metrics))),
                radius(metrics),
            ]

            for ax, label, data in zip(axes, labels, series):
                ax.cla()
                ax.plot(data, label=label, color="steelblue")
                if label == "Radius":
                    ax.plot(circumference(metrics), label="Circumference", linestyle="--", color="darkorange")
                ax.set_title(label + " vs Time")
                ax.legend()
                ax.grid(True)

            canvas.draw()


# ----------------------------
# Main execution
# ----------------------------
if __name__ == "__main__":
    # Configure as needed
    VIDEO_PATH = "source_video.mp4"  # set to your stitched video path
    START_FRAME = 0

    root = tk.Tk()
    root.title("Droplet Tracker v0.2.22 — Diagnostic")

    app = DropletTrackerUI(
        root,
        video_path=VIDEO_PATH,
        start_frame=START_FRAME
    )

    root.mainloop()
