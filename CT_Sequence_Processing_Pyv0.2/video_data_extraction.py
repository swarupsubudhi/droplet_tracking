import cv2
import numpy as np

def process_video(video_path, output_folder=None):
    """
    Reads a video, extracts frames, detects circles, and stores results.
    
    Parameters:
        video_path (str): Path to input video file
        output_folder (str): Optional folder to save frames as images
    
    Returns:
        circles_data (list of dict): Each entry contains frame index, centers, and radii
    """
    cap = cv2.VideoCapture(video_path)
    frame_idx = 0
    circles_data = []

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        # Convert to grayscale
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        # Apply Gaussian blur to reduce noise
        blurred = cv2.GaussianBlur(gray, (9, 9), 2)

        # Detect circles using Hough Transform
        circles = cv2.HoughCircles(
            blurred,
            cv2.HOUGH_GRADIENT,
            dp=1.2,              # Inverse ratio of accumulator resolution
            minDist=20,          # Minimum distance between circle centers
            param1=50,           # Upper threshold for Canny edge detector
            param2=30,           # Threshold for center detection
            minRadius=5,
            maxRadius=100
        )

        frame_circles = []
        if circles is not None:
            circles = np.round(circles[0, :]).astype("int")
            for (x, y, r) in circles:
                frame_circles.append({"center": (x, y), "radius": r})

        # Save frame if requested
        if output_folder:
            frame_filename = f"{output_folder}/frame_{frame_idx:04d}.png"
            cv2.imwrite(frame_filename, frame)

        # Append results
        circles_data.append({
            "frame": frame_idx,
            "circles": frame_circles
        })

        frame_idx += 1

    cap.release()
    return circles_data


# Example usage
video_file = "source_folder/sample_video.mp4"
results = process_video(video_file, output_folder="frames")

# Inspect first few results
for entry in results[:5]:
    print(f"Frame {entry['frame']}: {entry['circles']}")