# simulation.py
"""
Main simulation control loop for nanoparticle dynamics.
Handles initialization, brute-force → neighbor-list transition,
integration, logging, and visualization hooks.
"""

import numpy as np
import tkinter as tk
from tkinter import filedialog
import os
from config import log_interval, r_cutoff, neighbor_buffer, neighbor_rebuild_interval
from forces import total_forces
from neighbors import build_neighbor_list, update_neighbor_list, filter_by_force
from integrator import milstein_step
from utils import load_field, create_field_interpolator, interpolate_field
from visualization import live_plot

# ============================================================
# Initialize system
# ============================================================
def initialize_system(N: int, domain_radius: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Initialize positions, velocities, and dipole moments.
    Positions are uniformly distributed in a circular domain.
    Velocities start at zero. Moments initialized along z-axis.
    """
    pos = np.zeros((N,2))
    vel = np.zeros((N,2))
    moments = np.zeros((N,2))

    for i in range(N):
        # Random position inside circle of radius domain_radius
        r = domain_radius * np.sqrt(np.random.rand())
        theta = 2.0 * np.pi * np.random.rand()
        pos[i,0] = r * np.cos(theta)
        pos[i,1] = r * np.sin(theta)
        # Velocities start at zero
        vel[i,:] = 0.0
        # Initial dipole moments aligned with external field (z-axis)
        moments[i,1] = 1.0

    return pos, vel, moments

# ============================================================
# Run one simulation step
# ============================================================
def run_step(pos: np.ndarray, vel: np.ndarray, moments: np.ndarray,
             step: int, mode: str, neighbor_list: list,
             field_interp, dt: float) -> tuple[np.ndarray, np.ndarray, np.ndarray, list]:
    """
    Run one timestep in either brute-force or neighbor-list mode.
    Returns updated (pos, vel, moments, neighbor_list).
    """
    # Interpolate external field at particle positions
    B_values = interpolate_field(field_interp, pos)

    if mode == "brute_force":
        forces = total_forces(pos, vel, moments, B_values, dt)
    elif mode == "neighbor_list":
        # Filter neighbor list by force cutoff
        neighbor_list = filter_by_force(pos, moments, neighbor_list)
        forces = total_forces(pos, vel, moments, B_values, dt)
    else:
        raise ValueError("Unknown mode: {}".format(mode))

    # Integrate positions and velocities
    pos, vel = milstein_step(pos, vel, forces, dt)

    # Update dipole moments (simple alignment with external field for now)
    for i in range(pos.shape[0]):
        moments[i,1] = 1.0

    return pos, vel, moments, neighbor_list

# ============================================================
# Logging
# ============================================================
def log_state(step: int, pos: np.ndarray, vel: np.ndarray, forces: np.ndarray) -> None:
    """
    Log positions, velocities, and forces every log_interval steps.
    """
    if step % log_interval == 0:
        print(f"Step {step}:")
        print("Positions:\n", pos)
        print("Velocities:\n", vel)
        print("Forces:\n", forces)

# ============================================================
# Main simulation loop
# ============================================================
def simulate(N: int, steps: int, dt: float, domain_radius: float,
             field_interp) -> None:
    """
    Main simulation loop controlling transitions and logging.
    """
    pos, vel, moments = initialize_system(N, domain_radius)
    neighbor_list = []
    old_pos = pos.copy()

    for step in range(1, steps+1):
        # Mode selection
        if step <= 5:
            mode = "brute_force"
        else:
            # Update neighbor list periodically
            neighbor_list = update_neighbor_list(pos, old_pos, neighbor_list, step,
                                                 buffer=neighbor_buffer, r_c=r_cutoff)
            mode = "neighbor_list"

        # Run one step
        pos, vel, moments, neighbor_list = run_step(pos, vel, moments, step, mode,
                                                    neighbor_list, field_interp, dt)

        # Forces for logging
        B_values = interpolate_field(field_interp, pos)
        forces = total_forces(pos, vel, moments, B_values, dt)

        # Logging
        log_state(step, pos, vel, forces)

        # Visualization hook every 5 steps
        # Initialize plot once before loop
        fig, ax, scatter = None, None, None

        for step in range(1, steps+1):
            ...
            if step % 5 == 0:
                fig, ax, scatter = live_plot(pos, step, fig, ax, scatter, domain_radius)


# ============================================================
# Entry point
# ============================================================
if __name__ == "__main__":
    # Ask user for number of particles
    N = int(input("Enter number of particles: "))
    steps = 1000
    dt = 1e-6
    domain_radius = 1e-6  # 1 micron domain

    # File dialog to select magnetic field file
    root = tk.Tk()
    root.withdraw()  # Hide main window
    field_file = filedialog.askopenfilename(title="Select magnetic field file",
                                            filetypes=[("NumPy files", "*.npy")])

    # Updated integration with utils.py
    field_dict = load_field(os.path.splitext(os.path.basename(field_file))[0])
    field_interp = create_field_interpolator(field_dict)

    simulate(N, steps, dt, domain_radius, field_interp)