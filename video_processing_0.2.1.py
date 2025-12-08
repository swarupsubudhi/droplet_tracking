import cv2
import numpy as np
import matplotlib.pyplot as plt
import csv
import os

def live_diagnostics(video_path, output_folder="results0.2.1"):
    cap = cv2.VideoCapture(video_path)
    frame_idx = 0
    paused = False

    # Buffers for metrics
    side_metrics, front_metrics = [], []

    # Setup live plots
    fig, axs = plt.subplots(2, 3, figsize=(12, 6))
    plt.ion()

    while cap.isOpened():
        if not paused:
            ret, frame = cap.read()
            if not ret:
                break

            # Downscale stitched video (3840x1080 → 1920x540)
            frame = cv2.resize(frame, (1920, 540))

            # Crop side and front views (center-aligned 480x540)
            side_crop = frame[:, 240:240+480]
            front_crop = frame[:, 1200:1200+480]

            for view_name, crop, metrics, window_name in [
                ("side", side_crop, side_metrics, "Side View"),
                ("front", front_crop, front_metrics, "Front View")
            ]:
                # --- Save raw cropped frame BEFORE processing ---
                raw_folder = os.path.join(output_folder, "frames", view_name, "raw")
                os.makedirs(raw_folder, exist_ok=True)
                raw_path = os.path.join(raw_folder, f"raw_{frame_idx:04d}.jpeg")
                cv2.imwrite(raw_path, crop.copy())

                # --- Processing step ---
                gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
                blur = cv2.GaussianBlur(gray, (9, 9), 2)
                circles = cv2.HoughCircles(blur, cv2.HOUGH_GRADIENT, 1.2, 20,
                                           param1=50, param2=30, minRadius=5, maxRadius=100)

                if circles is not None:
                    x, y, r = np.round(circles[0][0]).astype(int)
                    metrics.append((x, y, r))
                    cv2.circle(crop, (x, y), r, (0, 255, 0), 2)
                    for i in range(1, len(metrics)):
                        cv2.line(crop, (metrics[i-1][0], metrics[i-1][1]),
                                 (metrics[i][0], metrics[i][1]), (255, 0, 0), 1)
                else:
                    metrics.append((np.nan, np.nan, np.nan))

                # --- Save processed frame AFTER overlays ---
                proc_folder = os.path.join(output_folder, "frames", view_name, "proc")
                os.makedirs(proc_folder, exist_ok=True)
                proc_path = os.path.join(proc_folder, f"proc_{frame_idx:04d}.jpeg")
                cv2.imwrite(proc_path, crop)

                # Show live frame
                cv2.imshow(window_name, crop)

            # --- Live plot updates ---
            def extract(arr, idx): return [a[idx] for a in arr]
            def dist(arr): return np.sqrt(np.diff(extract(arr, 0), prepend=0)**2 +
                                          np.diff(extract(arr, 1), prepend=0)**2)
            def smooth(arr): return np.convolve(arr, np.ones(5)/5, mode='same')
            def accel(arr): return np.diff(arr, prepend=arr[0])

            for i, (label, f) in enumerate([
                ("X", lambda m: extract(m, 0)),
                ("Y", lambda m: extract(m, 1)),
                ("Radius", lambda m: extract(m, 2)),
                ("Distance", dist),
                ("Speed", lambda m: smooth(dist(m))),
                ("Acceleration", lambda m: accel(smooth(dist(m))))
            ]):
                axs[i//3][i%3].cla()
                axs[i//3][i%3].plot(f(side_metrics), label="Side", color="steelblue")
                axs[i//3][i%3].plot(f(front_metrics), label="Front", color="darkorange")
                axs[i//3][i%3].set_title(label)
                axs[i//3][i%3].legend()
                axs[i//3][i%3].grid(True)

            plt.pause(0.01)
            frame_idx += 1

        # --- Toggle controls ---
        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            break
        elif key == ord('p'):
            paused = not paused
        elif key == ord('s'):
            continue

    cap.release()
    cv2.destroyAllWindows()
    plt.ioff()
    plt.show()

    # --- CSV Export ---
    os.makedirs(output_folder, exist_ok=True)
    output_file = os.path.join(output_folder, "combined_metrics.csv")
    with open(output_file, mode="w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["frame", "view", "x", "y", "radius", "distance", "speed", "acceleration"])

        def dist(arr): return np.sqrt(np.diff([p[0] for p in arr], prepend=0)**2 +
                                      np.diff([p[1] for p in arr], prepend=0)**2)
        def smooth(arr): return np.convolve(arr, np.ones(5)/5, mode='same')
        def accel(arr): return np.diff(arr, prepend=arr[0])

        side_d = dist(side_metrics)
        front_d = dist(front_metrics)
        side_s = smooth(side_d)
        front_s = smooth(front_d)
        side_a = accel(side_s)
        front_a = accel(front_s)

        for i in range(len(side_metrics)):
            sx, sy, sr = side_metrics[i]
            fx, fy, fr = front_metrics[i]
            writer.writerow([i, "side", sx, sy, sr, side_d[i], side_s[i], side_a[i]])
            writer.writerow([i, "front", fx, fy, fr, front_d[i], front_s[i], front_a[i]])

    print(f"Metrics saved to {output_file}")


# --- MAIN EXECUTION ---
if __name__ == "__main__":
    video_file = "C:/Research_Files_Swarup/R11-DropsCT/Expt_Data/Raw_Data_Videos/S25.mp4"
    live_diagnostics(video_file)