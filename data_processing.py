import numpy as np
import matplotlib.pyplot as plt
import os
import csv

def compute_metrics(circle_data):
    # circle_data: list of [x, y, r] per frame
    x = np.array([c[0] for c in circle_data])
    y = np.array([c[1] for c in circle_data])
    r = np.array([c[2] for c in circle_data])

    # Travel distance per frame
    dx = np.diff(x, prepend=x[0])
    dy = np.diff(y, prepend=y[0])
    distance = np.sqrt(dx**2 + dy**2)

    # Speed (moving average over 5 points)
    window = 5
    kernel = np.ones(window)/window
    speed = np.convolve(distance, kernel, mode='same')

    # Acceleration (difference of smoothed speed)
    acceleration = np.diff(speed, prepend=speed[0])

    return x, y, r, distance, speed, acceleration

def save_metrics_to_csv(x, y, r, distance, speed, acceleration, output_folder="results"):
    # Ensure results folder exists
    os.makedirs(output_folder, exist_ok=True)
    output_file = os.path.join(output_folder, "metrics.csv")

    # Write data to CSV
    with open(output_file, mode="w", newline="") as file:
        writer = csv.writer(file)
        # Header
        writer.writerow(["Frame", "X", "Y", "Radius", "Distance", "Speed", "Acceleration"])
        # Data rows
        for i in range(len(x)):
            writer.writerow([i, x[i], y[i], r[i], distance[i], speed[i], acceleration[i]])

    print(f"Metrics saved to {output_file}")

def plot_metric(data, title, ylabel):
    plt.figure(figsize=(8,4))
    plt.plot(data, marker='o', linestyle='-', color='steelblue')
    plt.title(title)
    plt.xlabel("Frame Index")
    plt.ylabel(ylabel)
    plt.grid(True)
    plt.show()

# Example usage with synthetic data
circle_data = [[i, i*0.5, 10] for i in range(50)]  # synthetic test
x, y, r, distance, speed, acceleration = compute_metrics(circle_data)

# Save to CSV
save_metrics_to_csv(x, y, r, distance, speed, acceleration)

# Plot examples
plot_metric(x, "Change in X over Time", "X Position")
plot_metric(y, "Change in Y over Time", "Y Position")
plot_metric(r, "Change in Radius over Time", "Radius")
plot_metric(distance, "Travel Distance over Time", "Distance")
plot_metric(speed, "Smoothed Speed over Time", "Speed")
plot_metric(acceleration, "Acceleration over Time", "Acceleration")