# mf_generator.py
"""
UI module for defining external magnetic field B(x,z).
Displays circular domain, lets user control decay type, max field, and gradients,
plots contours, and saves field to file.
"""

import os
import numpy as np
import matplotlib
matplotlib.use("TkAgg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
import tkinter as tk

# ============================================================
# Field generation
# ============================================================
def generate_field(domain_radius: float, resolution: int,
                   Bmax: float, form: str,
                   dBx: float, dBz: float) -> dict:
    """
    Generate B(x,z) field over circular domain.
    Returns dict with {"X","Z","B","Bmax","dBx","dBz"}.
    """
    x = np.linspace(-domain_radius, domain_radius, resolution)
    z = np.linspace(-domain_radius, domain_radius, resolution)
    X, Z = np.meshgrid(x, z)

    # Normalize z from bottom (-R) to top (+R)
    z_norm = (Z + domain_radius) / (2.0 * domain_radius)

    # Base decay profile
    if form == "Linear":
        B_decay = Bmax * (1.0 - z_norm)
    elif form == "Quadratic":
        B_decay = Bmax * (1.0 - z_norm**2)
    elif form == "Sinusoidal":
        B_decay = Bmax * np.cos(0.5 * np.pi * z_norm)
    elif form == "Radial":
        r = np.sqrt(X**2 + (Z + domain_radius)**2)
        r_norm = r / (2.0 * domain_radius)
        B_decay = Bmax * (1.0 - r_norm**2)
    else:
        B_decay = np.zeros_like(X)

    # Convert coordinates to microns for gradient terms
    X_um = X * 1e6
    Z_um = Z * 1e6

    # Add gradient modifiers
    B = B_decay + dBx * X_um + dBz * Z_um

    # Mask outside circular domain
    mask = X**2 + Z**2 <= domain_radius**2
    B_masked = np.where(mask, B, np.nan)

    return {"X": x, "Z": z, "B": B_masked,
            "Bmax": Bmax, "dBx": dBx, "dBz": dBz}

# ============================================================
# Save field
# ============================================================
def save_field(field_dict: dict, filename: str):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    folder = os.path.join(script_dir, "input-data")
    os.makedirs(folder, exist_ok=True)

    filepath = os.path.join(folder, filename + ".npy")
    np.save(filepath, field_dict)
    print(f"Field saved to {filepath}")

# ============================================================
# Launch UI
# ============================================================
def launch_field_ui(domain_radius: float = 1e-6, resolution: int = 200):
    root = tk.Tk()
    root.title("Magnetic Field Designer")

    # Container for plot state
    plot_state = {"fig": None, "ax": None, "canvas": None}

    # Control panel
    panel = tk.Frame(root)
    panel.pack(side=tk.BOTTOM, fill=tk.X)

    # Dropdown for functional form
    tk.Label(panel, text="Decay Type").grid(row=0, column=0)
    form_var = tk.StringVar(value="Linear")
    form_menu = tk.OptionMenu(panel, form_var, "Linear", "Quadratic", "Sinusoidal", "Radial")
    form_menu.grid(row=0, column=1)

    # Max field input
    tk.Label(panel, text="Max Field (Gauss)").grid(row=1, column=0)
    Bmax_var = tk.DoubleVar(value=100.0)  # default
    Bmax_entry = tk.Entry(panel, textvariable=Bmax_var)
    Bmax_entry.grid(row=1, column=1)

    # Gradient sliders
    tk.Label(panel, text="dB/dx (Gauss/µm)").grid(row=2, column=0)
    dBx_var = tk.DoubleVar(value=0.0)
    dBx_slider = tk.Scale(panel, variable=dBx_var, from_=-1.0, to=1.0,
                          resolution=0.01, orient=tk.HORIZONTAL)
    dBx_slider.grid(row=2, column=1)

    tk.Label(panel, text="dB/dz (Gauss/µm)").grid(row=3, column=0)
    dBz_var = tk.DoubleVar(value=0.0)
    dBz_slider = tk.Scale(panel, variable=dBz_var, from_=-1.0, to=1.0,
                          resolution=0.01, orient=tk.HORIZONTAL)
    dBz_slider.grid(row=3, column=1)

    # Refresh plot function
    def refresh_plot(field_dict=None):
        # Destroy old canvas if it exists
        if plot_state["canvas"] is not None:
            plot_state["canvas"].get_tk_widget().destroy()

        # Create new figure and axes
        fig, ax = plt.subplots(figsize=(5,5))
        canvas = FigureCanvasTkAgg(fig, master=root)
        canvas.get_tk_widget().pack(side=tk.TOP, fill=tk.BOTH, expand=True)

        plot_state["fig"] = fig
        plot_state["ax"] = ax
        plot_state["canvas"] = canvas

        if field_dict is not None:
            X, Z = np.meshgrid(field_dict["X"], field_dict["Z"])
            B = field_dict["B"]
            cs = ax.contourf(X, Z, B, levels=20, cmap="viridis")
            fig.colorbar(cs, ax=ax)

            ax.set_title("Magnetic Field Contours")
            ax.set_xlabel("x [m]")
            ax.set_ylabel("z [m]")
            ax.set_aspect("equal")

        canvas.draw()

    # Buttons
    def check_field():
        field_dict = generate_field(domain_radius, resolution,
                                    Bmax_var.get(), form_var.get(),
                                    dBx_var.get(), dBz_var.get())
        refresh_plot(field_dict)

    def reset_field():
        refresh_plot()  # blank plot

    tk.Button(panel, text="Check", command=check_field).grid(row=4, column=0)
    tk.Button(panel, text="Reset", command=reset_field).grid(row=4, column=1)

    # Save MF Config section
    tk.Label(panel, text="Filename").grid(row=5, column=0)
    filename_var = tk.StringVar(value="mf_config")
    filename_entry = tk.Entry(panel, textvariable=filename_var)
    filename_entry.grid(row=5, column=1)

    def save_config():
        field_dict = generate_field(domain_radius, resolution,
                                    Bmax_var.get(), form_var.get(),
                                    dBx_var.get(), dBz_var.get())
        save_field(field_dict, filename_var.get())

    tk.Button(panel, text="Save MF Config", command=save_config).grid(row=6, column=0, columnspan=2)

    # Initialize with blank plot
    refresh_plot()

    root.mainloop()

# ============================================================
# Entry point
# ============================================================
if __name__ == "__main__":
    launch_field_ui(domain_radius=1e-6, resolution=200)