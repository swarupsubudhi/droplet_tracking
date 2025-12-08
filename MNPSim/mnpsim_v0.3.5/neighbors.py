# neighbors.py
"""
Neighbor list management for nanoparticle simulation.
Handles spatial cutoffs and force-based filtering of dipole interactions.
"""

import numpy as np
from numba import njit
from config import r_cutoff, neighbor_buffer, neighbor_rebuild_interval, F_cutoff, MU0

# ============================================================
# Build neighbor list
# ============================================================
@njit
def build_neighbor_list(pos: np.ndarray, r_c: float = r_cutoff) -> list:
    """
    Build neighbor list for each particle within cutoff radius.
    pos : (N,2) positions
    r_c : cutoff distance [m]
    Returns list of lists: neighbors[i] contains indices of neighbors of particle i
    """
    N = pos.shape[0]
    neighbors = []
    for i in range(N):
        neigh_i = []
        for j in range(N):
            if i == j:
                continue
            dx = pos[i,0] - pos[j,0]
            dz = pos[i,1] - pos[j,1]
            r2 = dx*dx + dz*dz
            if r2 <= r_c**2:
                neigh_i.append(j)
        neighbors.append(neigh_i)
    return neighbors

# ============================================================
# Update neighbor list
# ============================================================
def update_neighbor_list(pos: np.ndarray, old_pos: np.ndarray,
                         old_list: list, step: int,
                         buffer: float = neighbor_buffer,
                         r_c: float = r_cutoff) -> list:
    """
    Rebuild neighbor list if particles moved beyond buffer distance
    or after fixed interval.
    pos : (N,2) current positions
    old_pos : (N,2) positions at last rebuild
    old_list : previous neighbor list
    step : current simulation step
    buffer : buffer distance [m]
    r_c : cutoff distance [m]
    Returns updated neighbor list
    """
    N = pos.shape[0]
    rebuild = False

    # Check displacement criterion
    for i in range(N):
        dx = pos[i,0] - old_pos[i,0]
        dz = pos[i,1] - old_pos[i,1]
        if dx*dx + dz*dz > (buffer**2):
            rebuild = True
            break

    # Check interval criterion
    if step % neighbor_rebuild_interval == 0:
        rebuild = True

    if rebuild:
        return build_neighbor_list(pos, r_c)
    else:
        return old_list

# ============================================================
# Filter neighbor list by force cutoff
# ============================================================
@njit
def filter_by_force(pos: np.ndarray, moments: np.ndarray,
                    neighbor_list: list, F_cut: float = F_cutoff) -> list:
    """
    Filter neighbor pairs by dipole force magnitude threshold.
    pos : (N,2) positions
    moments : (N,2) dipole moments
    neighbor_list : list of neighbor indices
    F_cut : force cutoff [N]
    Returns filtered neighbor list
    """
    N = pos.shape[0]
    filtered = []
    for i in range(N):
        neigh_i = []
        for j in neighbor_list[i]:
            dx = pos[i,0] - pos[j,0]
            dz = pos[i,1] - pos[j,1]
            r2 = dx*dx + dz*dz
            r = np.sqrt(r2)
            if r < 1e-12:
                continue
            m = np.linalg.norm(moments[j])
            # Worst-case dipole force magnitude
            F_est = (3.0 * MU0 * m**2) / (2.0 * np.pi * r**4)
            if F_est >= F_cut:
                neigh_i.append(j)
        filtered.append(neigh_i)
    return filtered