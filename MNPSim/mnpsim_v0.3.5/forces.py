# forces.py
"""
Force definitions for nanoparticle simulation.
All constants are imported from config.py.
"""

import numpy as np
from numba import njit
from config import MU0, KB, G, a, chi, A, zeta, T, C1, C2, F_cutoff, rho_p, rho_f

# ============================================================
# External magnetic force (bias field gradient contribution)
# ============================================================
@njit
def external_field_force(pos: np.ndarray, B0_grad: np.ndarray) -> np.ndarray:
    """
    External magnetic force from bias field gradient.
    pos : (N,2) positions
    B0_grad : (2,) gradient of B^2 field in plane
    Returns (N,2) array of forces
    """
    N = pos.shape[0]
    F = np.zeros((N, 2))
    coeff = MU0 * A * chi * 0.5
    for i in range(N):
        F[i, :] = coeff * B0_grad
    return F

# ============================================================
# Dipole–dipole interaction force
# ============================================================
@njit
def dipole_dipole_force(pos: np.ndarray, moments: np.ndarray) -> np.ndarray:
    """
    Dipole–dipole pairwise forces.
    pos : (N,2) positions
    moments : (N,2) dipole moments (projected in plane)
    Returns (N,2) array of forces
    """
    N = pos.shape[0]
    F = np.zeros((N, 2))
    for i in range(N):
        for j in range(N):
            if i == j:
                continue
            dx = pos[i,0] - pos[j,0]
            dz = pos[i,1] - pos[j,1]
            r2 = dx*dx + dz*dz
            r = np.sqrt(r2)
            if r < 1e-12:
                continue
            theta = np.arctan2(dx, dz)
            m = np.linalg.norm(moments[j])
            coeff = (3.0 * MU0 * m**2) / (4.0 * np.pi * r**4)
            Fr = coeff * (1.0 - 3.0 * np.sin(theta)**2)
            Ftheta = coeff * (2.0 * np.sin(theta) * np.cos(theta))
            ex = dx / r
            ez = dz / r
            Fx_r = Fr * ex
            Fz_r = Fr * ez
            Fx_t = -Ftheta * ez
            Fz_t = Ftheta * ex
            Fij_x = Fx_r + Fx_t
            Fij_z = Fz_r + Fz_t
            # Apply cutoff condition
            if np.sqrt(Fij_x**2 + Fij_z**2) < F_cutoff:
                continue
            F[i,0] += Fij_x
            F[i,1] += Fij_z
    return F

# ============================================================
# Drag force
# ============================================================
@njit
def drag_force(vel: np.ndarray) -> np.ndarray:
    """
    Stokes drag force.
    vel : (N,2) velocities
    Returns (N,2) array of forces
    """
    return -zeta * vel

# ============================================================
# Gravity + buoyancy
# ============================================================
@njit
def gravity_force(N: int) -> np.ndarray:
    """
    Gravity + buoyancy force (acts along -z).
    N : number of particles
    Returns (N,2) array of forces
    """
    F = np.zeros((N,2))
    coeff = A * (rho_p - rho_f) * G
    for i in range(N):
        F[i,1] = -coeff
    return F

# ============================================================
# Brownian force
# ============================================================
@njit
def brownian_force(N: int, dt: float) -> np.ndarray:
    """
    Brownian random force.
    N : number of particles
    dt : timestep [s]
    Returns (N,2) array of forces
    """
    sigma = np.sqrt(2.0 * KB * T * zeta / dt)
    F = np.random.normal(0.0, sigma, (N,2))
    return F

# ============================================================
# Contact barrier force
# ============================================================
@njit
def contact_force(pos: np.ndarray) -> np.ndarray:
    """
    Short-range repulsion to prevent overlap.
    pos : (N,2) positions
    Returns (N,2) array of forces
    """
    N = pos.shape[0]
    F = np.zeros((N,2))
    dmin = 2.0 * a
    cutoff = 1.1 * dmin
    for i in range(N):
        for j in range(N):
            if i == j:
                continue
            dx = pos[i,0] - pos[j,0]
            dz = pos[i,1] - pos[j,1]
            r2 = dx*dx + dz*dz
            r = np.sqrt(r2)
            if r < cutoff and r > 1e-12:
                term = ((210.0*a)**2 - r**2) / (C2 * 4.0 * a**2)
                coeff = -C1 * (r/(2.0*a)) * (term**3)
                ex = dx / r
                ez = dz / r
                F[i,0] += coeff * ex
                F[i,1] += coeff * ez
    return F

# ============================================================
# Total forces aggregator
# ============================================================
@njit
def total_forces(pos: np.ndarray, vel: np.ndarray, moments: np.ndarray,
                 B0_grad: np.ndarray, dt: float) -> np.ndarray:
    """
    Compute total forces on all particles.
    pos : (N,2) positions
    vel : (N,2) velocities
    moments : (N,2) dipole moments
    B0_grad : (2,) gradient of B^2 field
    dt : timestep [s]
    Returns (N,2) array of forces
    """
    N = pos.shape[0]
    F_ext = external_field_force(pos, B0_grad)
    F_dip = dipole_dipole_force(pos, moments)
    F_drag = drag_force(vel)
    F_grav = gravity_force(N)
    F_brown = brownian_force(N, dt)
    F_contact = contact_force(pos)
    return F_ext + F_dip + F_drag + F_grav + F_brown + F_contact