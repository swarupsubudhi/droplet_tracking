import tkinter as tk
from tkinter import ttk
import cv2
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
import os
import csv

# ----------------------------
# Detection (tune HSV yourself)
# ----------------------------
def detect_brown_circle(crop):
    """Detect the largest dark brown circle in a cropped frame.
    Returns (x, y, r) or (nan, nan, nan) if not found.
    """
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    # NOTE: Tune these thresholds to your droplet hue/saturation/value
    lower_brown = np.array([10, 100, 20])
    upper_brown = np.array([30, 255, 200])

    mask = cv2.inRange(hsv, lower_brown, upper_brown)
    masked = cv2.bitwise_and(crop, crop, mask=mask)

    gray = cv2.cvtColor(masked, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (9, 9), 2)

    circles = cv2.HoughCircles(
        blur, cv2.HOUGH_GRADIENT, dp=1.2, minDist=20,
        param1=50, param2=30, minRadius=5, maxRadius=100
    )

    if circles is not None:
        circles = np.round(circles[0, :]).astype("int")
        x, y, r = max(circles, key=lambda c: c[2])
        return (x, y, r)

    return (np.nan, np.nan, np.nan)


class DropletTrackerUI:
    def __init__(self, root, video_path, start_frame=0, output_folder="results"):
        self.root = root
        self.cap = cv2.VideoCapture(video_path)
        if start_frame > 0:
            self.cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
        self.frame_idx = start_frame

        self.running = False
        self.paused = False
        self.output_folder = output_folder

        self.front_metrics, self.side_metrics = [], []

        # Ensure output folders exist
        for view_name in ["front", "side"]:
            os.makedirs(os.path.join(self.output_folder, "frames", view_name, "raw"), exist_ok=True)
            os.makedirs(os.path.join(self.output_folder, "frames", view_name, "proc"), exist_ok=True)
        os.makedirs(self.output_folder, exist_ok=True)

        # ----------------------------
        # Layout: left = video+plots, right = controls+log
        # ----------------------------
        # Left column: two rows (Front on top, Side on bottom)
        left_column = ttk.Frame(root)
        left_column.grid(row=0, column=0, padx=10, pady=10, sticky="nw")

        self.front_frame = ttk.Frame(left_column)
        self.side_frame = ttk.Frame(left_column)
        self.front_frame.grid(row=0, column=0, padx=5, pady=5, sticky="w")
        self.side_frame.grid(row=1, column=0, padx=5, pady=5, sticky="w")

        # Video labels (processed frames only)
        self.front_label = tk.Label(self.front_frame)
        self.side_label = tk.Label(self.side_frame)
        self.front_label.pack(side=tk.LEFT)
        self.side_label.pack(side=tk.LEFT)

        # Matplotlib figures: 1x4 subplots per view (inline horizontally)
        self.front_fig, self.front_axes = plt.subplots(1, 4, figsize=(12, 3))
        self.side_fig, self.side_axes = plt.subplots(1, 4, figsize=(12, 3))
        self.front_canvas = FigureCanvasTkAgg(self.front_fig, master=self.front_frame)
        self.side_canvas = FigureCanvasTkAgg(self.side_fig, master=self.side_frame)
        self.front_canvas.get_tk_widget().pack(side=tk.RIGHT, padx=10)
        self.side_canvas.get_tk_widget().pack(side=tk.RIGHT, padx=10)

        # Right column: control panel + log (stacked vertically)
        right_column = ttk.Frame(root)
        right_column.grid(row=0, column=1, padx=10, pady=10, sticky="ne")

        control_frame = ttk.Frame(right_column)
        control_frame.pack(side=tk.TOP, fill=tk.X)

        self.start_btn = tk.Button(control_frame, text="Start", command=self.start_processing)
        self.pause_btn = tk.Button(control_frame, text="Pause", command=self.pause_processing)
        self.stop_btn = tk.Button(control_frame, text="Stop", command=self.stop_processing)
        self.start_btn.pack(side=tk.LEFT, padx=5)
        self.pause_btn.pack(side=tk.LEFT, padx=5)
        self.stop_btn.pack(side=tk.LEFT, padx=5)

        self.status_label = tk.Label(control_frame, text="Status: Idle", fg="blue")
        self.status_label.pack(side=tk.LEFT, padx=10)

        # Log box directly below control panel on the right
        log_frame = ttk.Frame(right_column)
        log_frame.pack(side=tk.TOP, fill=tk.BOTH, expand=True, pady=(10, 0))
        self.log_box = tk.Text(log_frame, height=25, width=50)
        self.log_box.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.log_box.configure(state="disabled")
        log_scroll = ttk.Scrollbar(log_frame, command=self.log_box.yview)
        log_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.log_box.configure(yscrollcommand=log_scroll.set)

    # ----------------------------
    # Controls
    # ----------------------------
    def start_processing(self):
        self.running = True
        self.paused = False
        self.status_label.config(text="Status: Processing", fg="green")
        self.log("Computation started")
        self.update_frame()

    def pause_processing(self):
        if not self.running:
            return
        self.paused = True
        self.status_label.config(text="Status: Paused", fg="orange")
        self.log("Computation paused")

    def stop_processing(self):
        if not self.running and not self.paused:
            return
        self.running = False
        self.paused = False
        self.status_label.config(text="Status: Stopped", fg="red")
        self.log("Computation stopped")
        self.log("Exporting metrics to CSV...")
        self.export_csv()
        try:
            self.cap.release()
        except Exception:
            pass

    # ----------------------------
    # Logging
    # ----------------------------
    def log(self, message):
        self.log_box.configure(state="normal")
        self.log_box.insert(tk.END, message + "\n")
        self.log_box.see(tk.END)  # auto-scroll to latest
        self.log_box.configure(state="disabled")

    # ----------------------------
    # Main update loop
    # ----------------------------
    def update_frame(self):
        if not self.running or self.paused:
            return

        ret, frame = self.cap.read()
        if not ret:
            self.stop_processing()
            return

        # Resize stitched video to expected size (adjust if different in your setup)
        frame = cv2.resize(frame, (1920, 540))
        side_crop = frame[:, 240:240+480]
        front_crop = frame[:, 1200:1200+480]

        # Process both views: save raw, detect, overlay, save processed, display
        for view_name, crop, metrics, label in [
            ("front", front_crop, self.front_metrics, self.front_label),
            ("side", side_crop, self.side_metrics, self.side_label),
        ]:
            # Save raw frame
            raw_path = os.path.join(self.output_folder, "frames", view_name, "raw", f"raw_{self.frame_idx:04d}.jpeg")
            cv2.imwrite(raw_path, crop.copy())

            # Detect droplet
            x, y, r = detect_brown_circle(crop)
            metrics.append((x, y, r))

            # Log per-frame with detection status
            if np.isnan(x):
                self.log(f"Processing frame {self.frame_idx}... Droplet not tracked")
            else:
                self.log(f"Processing frame {self.frame_idx}...")

                # Overlay circle and circumference text
                cv2.circle(crop, (int(x), int(y)), int(r), (0, 255, 0), 2)
                circ = 2 * np.pi * r
                cv2.putText(
                    crop, f"C={circ:.1f}", (int(x + r + 5), int(y)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1, cv2.LINE_AA
                )

            # Save processed frame
            proc_path = os.path.join(self.output_folder, "frames", view_name, "proc", f"proc_{self.frame_idx:04d}.jpeg")
            cv2.imwrite(proc_path, crop)

            # Display with aspect ratio preserved (fit into max box)
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

        # Update plots
        self.update_plots()

        # Next frame
        self.frame_idx += 1
        self.root.after(100, self.update_frame)

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
            (self.side_metrics, self.side_axes, self.side_canvas),
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
    # CSV Export
    # ----------------------------
    def export_csv(self):
        output_file = os.path.join(self.output_folder, "combined_metrics.csv")

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

        with open(output_file, mode="w", newline="") as file:
            writer = csv.writer(file)
            writer.writerow(["frame", "view", "x", "y", "radius", "distance", "speed", "acceleration"])

            for view_name, metrics in [("front", self.front_metrics), ("side", self.side_metrics)]:
                d = dist(metrics)
                s = smooth(d)
                a = accel(s)
                for i in range(len(metrics)):
                    x, y, r = metrics[i]
                    di = d[i] if i < len(d) else np.nan
                    si = s[i] if i < len(s) else np.nan
                    ai = a[i] if i < len(a) else np.nan
                    writer.writerow([i, view_name, x, y, r, di, si, ai])

        self.log(f"CSV saved to: {output_file}")


# ----------------------------
# Main execution
# ----------------------------
if __name__ == "__main__":
    # Configure these paths/params as needed
    VIDEO_PATH = "sourcefile.mp4"
    START_FRAME = 500  # set to 0 to start from the beginning
    OUTPUT_FOLDER = "results"

    root = tk.Tk()
    root.title("Droplet Tracker v0.2.2")

    app = DropletTrackerUI(
        root,
        video_path=VIDEO_PATH,
        start_frame=START_FRAME,
        output_folder=OUTPUT_FOLDER
    )

    root.mainloop()
