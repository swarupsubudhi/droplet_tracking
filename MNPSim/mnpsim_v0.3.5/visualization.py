# visualization.py
"""
Live plotting module for nanoparticle simulation.
Provides functions to visualize particle positions during simulation.
"""

import matplotlib.pyplot as plt
import numpy as np

# ============================================================
# Initialize live plot
# ============================================================
def init_plot(domain_radius: float):
    """
    Initialize the live plot figure and axes.
    Returns (fig, ax, scatter).
    """
    fig, ax = plt.subplots(figsize=(6,6))
    scatter = ax.scatter([], [], s=20, c='blue', alpha=0.7)

    # Domain circle
    circle = plt.Circle((0,0), domain_radius, color='black', fill=False, linestyle='--')
    ax.add_patch(circle)

    ax.set_xlim(-domain_radius, domain_radius)
    ax.set_ylim(-domain_radius, domain_radius)
    ax.set_aspect('equal')
    ax.set_title("Nanoparticle Simulation")
    ax.set_xlabel("x [m]")
    ax.set_ylabel("z [m]")

    plt.ion()  # interactive mode
    plt.show()

    return fig, ax, scatter

# ============================================================
# Update live plot
# ============================================================
def live_plot(pos: np.ndarray, step: int,
              fig=None, ax=None, scatter=None,
              domain_radius: float=1e-6):
    """
    Update the live plot with new particle positions.
    If fig/ax/scatter are None, initialize them.
    """
    if fig is None or ax is None or scatter is None:
        fig, ax, scatter = init_plot(domain_radius)

    # Update scatter data
    scatter.set_offsets(pos)

    ax.set_title(f"Nanoparticle Simulation - Step {step}")
    fig.canvas.draw()
    fig.canvas.flush_events()

    return fig, ax, scatter