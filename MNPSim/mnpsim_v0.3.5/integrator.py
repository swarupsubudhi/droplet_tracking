# integrator.py
"""
Integration schemes for nanoparticle simulation.
Implements Milstein and Euler–Maruyama methods for overdamped Langevin dynamics.
"""

import numpy as np
from numba import njit
from config import D, zeta

# ============================================================
# Milstein integrator step
# ============================================================
@njit
def milstein_step(pos: np.ndarray, vel: np.ndarray, forces: np.ndarray,
                  dt: float, D: float = D) -> tuple[np.ndarray, np.ndarray]:
    """
    Perform one Milstein integration step for overdamped Langevin dynamics.
    
    pos : (N,2) positions
    vel : (N,2) velocities
    forces : (N,2) net forces
    dt : timestep [s]
    D : diffusion coefficient [m^2/s]
    
    Returns updated (pos, vel).
    """
    N = pos.shape[0]
    new_pos = np.zeros_like(pos)
    new_vel = np.zeros_like(vel)

    # Noise term
    noise = np.random.normal(0.0, 1.0, (N,2))

    for i in range(N):
        # Deterministic velocity update (overdamped regime)
        new_vel[i,:] = forces[i,:] / zeta

        # Milstein position update
        drift = new_vel[i,:] * dt
        diffusion = np.sqrt(2.0 * D * dt) * noise[i,:]
        correction = D * dt * (noise[i,:]**2 - 1.0)  # Milstein correction term

        new_pos[i,:] = pos[i,:] + drift + diffusion + correction

    return new_pos, new_vel

# ============================================================
# Euler–Maruyama integrator step
# ============================================================
@njit
def euler_maruyama_step(pos: np.ndarray, vel: np.ndarray, forces: np.ndarray,
                        dt: float, D: float = D) -> tuple[np.ndarray, np.ndarray]:
    """
    Perform one Euler–Maruyama integration step for overdamped Langevin dynamics.
    
    pos : (N,2) positions
    vel : (N,2) velocities
    forces : (N,2) net forces
    dt : timestep [s]
    D : diffusion coefficient [m^2/s]
    
    Returns updated (pos, vel).
    """
    N = pos.shape[0]
    new_pos = np.zeros_like(pos)
    new_vel = np.zeros_like(vel)

    # Noise term
    noise = np.random.normal(0.0, 1.0, (N,2))

    for i in range(N):
        # Deterministic velocity update (overdamped regime)
        new_vel[i,:] = forces[i,:] / zeta

        # Euler–Maruyama position update
        drift = new_vel[i,:] * dt
        diffusion = np.sqrt(2.0 * D * dt) * noise[i,:]

        new_pos[i,:] = pos[i,:] + drift + diffusion

    return new_pos, new_vel