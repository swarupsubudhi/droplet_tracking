# utils.py
"""
Utility functions for loading and interpolating magnetic field data.
Integrates with mf_generator.py outputs.
"""

import os
import numpy as np
from scipy.interpolate import RegularGridInterpolator

# ============================================================
# Load field file
# ============================================================
def load_field(filename: str) -> dict:
    """
    Load saved magnetic field array from .npy file.
    Expects dictionary with keys {"X", "Z", "B", "Bmax", "dBx", "dBz"}.

    Returns full dictionary for flexibility.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    folder = os.path.join(script_dir, "input-data")
    filepath = os.path.join(folder, filename + ".npy")

    data = np.load(filepath, allow_pickle=True).item()
    return data

# ============================================================
# Create interpolator
# ============================================================
def create_field_interpolator(field_dict):
    """
    Create an interpolator for B(x,z) over the domain.
    Returns a callable interpolator function.
    """
    X = field_dict["X"]
    Z = field_dict["Z"]
    B = field_dict["B"]

    # Note: meshgrid produces B with shape (len(Z), len(X))
    interp = RegularGridInterpolator((Z, X), B,
                                     bounds_error=False,
                                     fill_value=np.nan)
    return interp

# ============================================================
# Interpolate field values
# ============================================================
def interpolate_field(interpolator, positions: np.ndarray) -> np.ndarray:
    """
    Interpolate field values at given particle positions.

    positions : (N,2) array of (x,z) coordinates in meters
    Returns (N,) array of interpolated field magnitudes.
    """
    # Swap order to (z,x) for the interpolator
    coords = np.array([[pos[1], pos[0]] for pos in positions])
    return interpolator(coords)