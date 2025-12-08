import cv2
import numpy as np
import matplotlib.pyplot as plt
import csv
import os

### STEP 1: Video Processing & Circle Detection ###

def preprocess_frame(frame):
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (9, 9), 2) #why blurring?
    return blurred

def detect_circles(frame):
    circles = cv2.HoughCircles(
        frame,
        cv2.HOUGH_GRADIENT,
        dp=1.2,
        minDist=50,
        param1=50,
        param2=30,
        minRadius=150,
        maxRadius=200
    )
    results = []
    if circles is not None:
        circles = np.round(circles[0, :]).astype("int")
        for (x, y, r) in circles:
            results.append([x, y, r])
    return results

def process_video(video_path):
    cap = cv2.VideoCapture(video_path)
    frame_idx = 0
    side_results, front_results = [], []

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        # Downscale by 2x → 1920x540
        frame = cv2.resize(frame, (1920, 540))

        # Split into side (left) and front (right)
        side_half = frame[:, :960]
        front_half = frame[:, 960:]

        # Crop center-aligned 240x540 region
        crop_w = 240
        start_x = (960 - crop_w) // 2
        side_crop = side_half[:, start_x:start_x+crop_w]
        front_crop = front_half[:, start_x:start_x+crop_w]

        # Preprocess and detect circles
        side_blur = preprocess_frame(side_crop)
        front_blur = preprocess_frame(front_crop)

        side_circles = detect_circles(side_blur)
        front_circles = detect_circles(front_blur)

        side_results.append({"frame": frame_idx, "circles": side_circles})
        front_results.append({"frame": frame_idx, "circles": front_circles})

        frame_idx += 1

    cap.release()
    return side_results, front_results

### STEP 2: Metric Computation & CSV Export ###

def extract_primary_circle(results):
    return [frame["circles"][0] if frame["circles"] else [np.nan, np.nan, np.nan] for frame in results]

def compute_metrics(circle_data):
    x = np.array([c[0] for c in circle_data])
    y = np.array([c[1] for c in circle_data])
    r = np.array([c[2] for c in circle_data])

    dx = np.diff(x, prepend=x[0])
    dy = np.diff(y, prepend=y[0])
    distance = np.sqrt(dx**2 + dy**2)

    window = 5
    kernel = np.ones(window)/window
    speed = np.convolve(distance, kernel, mode='same')
    acceleration = np.diff(speed, prepend=speed[0])

    return x, y, r, distance, speed, acceleration

def save_combined_metrics(side_results, front_results, output_folder="results"):
    os.makedirs(output_folder, exist_ok=True)
    output_file = os.path.join(output_folder, "combined_metrics.csv")

    side_data = extract_primary_circle(side_results)
    front_data = extract_primary_circle(front_results)

    sx, sy, sr, sd, ss, sa = compute_metrics(side_data)
    fx, fy, fr, fd, fs, fa = compute_metrics(front_data)

    with open(output_file, mode="w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["frame", "view", "x", "y", "radius", "distance", "speed", "acceleration"])
        for i in range(len(sx)):
            writer.writerow([i, "side", sx[i], sy[i], sr[i], sd[i], ss[i], sa[i]])
            writer.writerow([i, "front", fx[i], fy[i], fr[i], fd[i], fs[i], fa[i]])

    print(f"Combined metrics saved to {output_file}")
    return (sx, sy, sr, sd, ss, sa), (fx, fy, fr, fd, fs, fa)

### STEP 3: Dual-View Plotting ###

def plot_dual_metric(side_data, front_data, title, ylabel):
    frames = np.arange(len(side_data))
    plt.figure(figsize=(10, 5))
    plt.plot(frames, side_data, label="Side View", color="steelblue", marker='o')
    plt.plot(frames, front_data, label="Front View", color="darkorange", marker='x')
    plt.title(title)
    plt.xlabel("Frame Index")
    plt.ylabel(ylabel)
    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.show()

### MAIN EXECUTION ###

if __name__ == "__main__":
    video_file = "C:/Research_Files_Swarup/R11-DropsCT/Expt_Data/Raw_Data_Videos/S25.mp4"
    side_results, front_results = process_video(video_file)
    side_metrics, front_metrics = save_combined_metrics(side_results, front_results)

    sx, sy, sr, sd, ss, sa = side_metrics
    fx, fy, fr, fd, fs, fa = front_metrics

    plot_dual_metric(sx, fx, "X Position Over Time", "X Coordinate")
    plot_dual_metric(sy, fy, "Y Position Over Time", "Y Coordinate")
    plot_dual_metric(sr, fr, "Radius Over Time", "Radius")
    plot_dual_metric(sd, fd, "Travel Distance Over Time", "Distance")
    plot_dual_metric(ss, fs, "Smoothed Speed Over Time", "Speed")
    plot_dual_metric(sa, fa, "Acceleration Over Time", "Acceleration")