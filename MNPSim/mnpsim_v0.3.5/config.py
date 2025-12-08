# config.py
"""
Configuration file for nanoparticle simulation.
All physical constants, particle parameters, and cutoff thresholds
are defined here for easy modification.
"""

import numpy as np

# --- Physical constants (SI units) ---
MU0 = 4.0 * np.pi * 1e-7        # Vacuum permeability [H/m]
KB = 1.380649e-23               # Boltzmann constant [J/K]
G = 9.80665                     # Gravitational acceleration [m/s^2]

# --- Particle/system parameters ---
a = 50e-9                       # Particle radius [m]
chi = 0.4                       # Magnetic susceptibility (dimensionless)
eta = 1.002e-3                  # Fluid viscosity [Pa·s]
rho_p = 5170.0                  # Particle density [kg/m^3]
rho_f = 1000.0                  # Fluid density [kg/m^3]
T = 298.15                      # Temperature [K]

# --- Derived quantities ---
A = np.pi * a**2                # 2D particle area [m^2]
zeta = 6.0 * np.pi * eta * a    # Drag coefficient [N·s/m]
D = KB * T / zeta               # Diffusion coefficient [m^2/s]

# --- Contact barrier constants ---
C1 = 1.02
C2 = 0.011

# --- Cutoff thresholds ---
F_cutoff = 1e-8                 # Dipole force cutoff [N]
r_cutoff = 200e-9               # Neighbor list cutoff distance [m]
neighbor_buffer = 1.0 * a       # Buffer distance for neighbor list rebuild [m]
neighbor_rebuild_interval = 50  # Steps between neighbor list rebuilds

# --- Logging ---
log_interval = 10               # Steps between logging outputs