"""
Experiment 2: Distance Estimation Accuracy — Data Analysis

printed to console:
  - Table 1: Summary statistics by distance condition
  - Table 2: Linear regression results
  - Spearman rank correlation test result

saved as PNG:
  - Figure 1: Estimated vs Ground Truth scatter plot
  - Figure 2: Signed error vs distance box plot
  - Figure 3: Mean Percentage Error bar chart
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from scipy import stats

# =====================================================================
# 1. Load and prepare data
# =====================================================================

df = pd.read_csv("raw_data_with_target_distance.csv")

# Fixed seed for reproducible jitter in scatter plots
np.random.seed(42)

# Compute derived columns
df["error"] = df["estimated_distance"] - df["target_distance"]       # signed error
df["abs_error"] = df["error"].abs()                                  # absolute error
df["pct_error"] = (df["abs_error"] / df["target_distance"]) * 100    # percentage error

# =====================================================================
# 2. Table 1: Summary statistics by distance condition
# =====================================================================

# Per-distance group statistics (n = 5 per group)
distances = sorted(df["target_distance"].unique())

table_rows = []
for d in distances:
    group = df[df["target_distance"] == d]
    row = {
        "Ground truth (m)": d,
        "Mean est. (m)": group["estimated_distance"].mean(),
        "Mean error (m)": group["error"].mean(),             # signed, shows bias direction
        "Std dev (m)": group["error"].std(ddof=1),
        "MAE (m)": group["abs_error"].mean(),
        "RMSE (m)": np.sqrt((group["error"] ** 2).mean()),
        "MPE (%)": group["pct_error"].mean(),
    }
    table_rows.append(row)

# Overall row (N = 30)
overall = {
    "Ground truth (m)": "Overall",
    "Mean est. (m)": df["estimated_distance"].mean(),
    "Mean error (m)": df["error"].mean(),
    "Std dev (m)": df["error"].std(ddof=1),
    "MAE (m)": df["abs_error"].mean(),
    "RMSE (m)": np.sqrt((df["error"] ** 2).mean()),
    "MPE (%)": df["pct_error"].mean(),
}
table_rows.append(overall)

table1 = pd.DataFrame(table_rows)

print("=" * 90)
print("Table 1: Summary Statistics by Distance Condition")
print("=" * 90)
print(table1.to_string(index=False, float_format="{:.4f}".format))
print()

# =====================================================================
# 3. Statistical tests
# =====================================================================

# --- Test 1: Spearman rank correlation (does |error| increase with distance?) ---
rho, p_spearman = stats.spearmanr(df["target_distance"], df["abs_error"])

print("=" * 90)
print("Statistical Test 1: Spearman Rank Correlation")
print("  H0: No monotonic association between |error| and ground-truth distance (rho = 0)")
print("  H1: |error| increases with ground-truth distance (rho > 0)")
print(f"  rho = {rho:.4f},  p = {p_spearman:.6f} (two-tailed)")
# One-tailed p-value for positive direction
p_one_tailed = p_spearman / 2 if rho > 0 else 1 - p_spearman / 2
print(f"  One-tailed p = {p_one_tailed:.6f}")
if p_one_tailed < 0.05:
    print("  → Reject H0 at alpha = 0.05: absolute error significantly increases with distance")
else:
    print("  → Fail to reject H0: no significant monotonic increase in error with distance")
print()

# --- Test 2: Linear regression (estimated = beta0 + beta1 * ground_truth) ---
slope, intercept, r_value, p_reg, std_err = stats.linregress(
    df["target_distance"], df["estimated_distance"]
)
r_squared = r_value ** 2

print("=" * 90)
print("Statistical Test 2: Linear Regression (estimated = β₀ + β₁ × ground_truth)")
print("=" * 90)
print(f"  β₁ (slope)     = {slope:.4f}   (ideal: 1.0)")
print(f"  β₀ (intercept) = {intercept:.4f}   (ideal: 0.0)")
print(f"  R²             = {r_squared:.6f}   (ideal: 1.0)")
print(f"  p-value (slope) = {p_reg:.2e}")
print()

# Interpretation
if slope > 1.0:
    slope_interp = "systematic overestimation at far range"
elif slope < 1.0:
    slope_interp = "systematic underestimation at far range"
else:
    slope_interp = "no systematic range-dependent bias"

if intercept > 0:
    intercept_interp = "uniform overestimation at all distances"
elif intercept < 0:
    intercept_interp = "uniform underestimation at all distances"
else:
    intercept_interp = "no uniform bias"

print(f"  β₁ interpretation: {slope_interp}")
print(f"  β₀ interpretation: {intercept_interp}")
print()

# Table 2: Regression summary
print("Table 2: Regression Analysis Results")
print("-" * 50)
print(f"  {'Parameter':<20} {'Value':>10} {'Ideal':>10}")
print(f"  {'β₁ (slope)':<20} {slope:>10.4f} {'1.0000':>10}")
print(f"  {'β₀ (intercept)':<20} {intercept:>10.4f} {'0.0000':>10}")
print(f"  {'R²':<20} {r_squared:>10.6f} {'1.0000':>10}")
print()

# =====================================================================
# 4. Figures
# =====================================================================

# Common style settings
plt.rcParams.update({
    "figure.dpi": 150,
    "font.size": 11,
    "axes.titlesize": 13,
    "axes.labelsize": 12,
})

# --- Figure 1: Estimated vs Ground Truth scatter plot ---
fig1, ax1 = plt.subplots(figsize=(7, 6))

ax1.scatter(
    df["target_distance"] + np.random.uniform(-0.06, 0.06, size=len(df)),
    df["estimated_distance"],
    c="#2196F3", edgecolors="white", s=60, alpha=0.85, zorder=3, label="Measurements (n=30)"
)

# y = x reference line (perfect estimation)
lim = [0, 5.5]
ax1.plot(lim, lim, "k--", linewidth=1, alpha=0.6, label="Perfect estimation (y = x)")

# Regression line
x_fit = np.linspace(0, 5.5, 100)
y_fit = intercept + slope * x_fit
ax1.plot(
    x_fit, y_fit, "r-", linewidth=1.5, alpha=0.7,
    label=f"Regression (y = {intercept:.3f} + {slope:.3f}x, R² = {r_squared:.4f})"
)

ax1.set_xlabel("Ground Truth Distance (m)")
ax1.set_ylabel("Estimated Distance (m)")
ax1.set_title("Figure 1: Estimated vs Ground Truth Distance")
ax1.set_xlim(lim)
ax1.set_ylim(lim)
ax1.set_aspect("equal")
ax1.legend(loc="upper left", fontsize=9)
ax1.grid(True, alpha=0.3)

fig1.tight_layout()
fig1.savefig("figure1_estimated_vs_truth.png")
print("Saved: figure1_estimated_vs_truth.png")

# --- Figure 2: Signed error vs distance (box plot + scatter) ---
fig2, ax2 = plt.subplots(figsize=(7, 5))

# Group data for box plot
grouped_errors = [df[df["target_distance"] == d]["error"].values for d in distances]

bp = ax2.boxplot(
    grouped_errors,
    positions=range(len(distances)),
    widths=0.4,
    patch_artist=True,
    boxprops=dict(facecolor="#E3F2FD", edgecolor="#1976D2"),
    medianprops=dict(color="#D32F2F", linewidth=2),
    whiskerprops=dict(color="#1976D2"),
    capprops=dict(color="#1976D2"),
    flierprops=dict(marker="o", markerfacecolor="#FF9800", markersize=6),
)

# Overlay individual points with jitter
for i, d in enumerate(distances):
    group_data = df[df["target_distance"] == d]["error"].values
    jitter = np.random.normal(0, 0.04, size=len(group_data))
    ax2.scatter(
        [i] * len(group_data) + jitter, group_data,
        c="#1976D2", s=40, alpha=0.7, zorder=3
    )

# y = 0 reference line (perfect accuracy)
ax2.axhline(y=0, color="black", linestyle="--", linewidth=1, alpha=0.5)

ax2.set_xticks(range(len(distances)))
ax2.set_xticklabels([str(d) for d in distances])
ax2.set_xlabel("Ground Truth Distance (m)")
ax2.set_ylabel("Signed Error (m)")
ax2.set_title("Figure 2: Estimation Error vs Distance")
ax2.grid(True, axis="y", alpha=0.3)

fig2.tight_layout()
fig2.savefig("figure2_error_vs_distance.png")
print("Saved: figure2_error_vs_distance.png")

# --- Figure 3: Mean Percentage Error bar chart ---
fig3, ax3 = plt.subplots(figsize=(7, 5))

mpe_means = [df[df["target_distance"] == d]["pct_error"].mean() for d in distances]
mpe_stds = [df[df["target_distance"] == d]["pct_error"].std(ddof=1) for d in distances]

bars = ax3.bar(
    range(len(distances)), mpe_means,
    yerr=mpe_stds, capsize=5,
    color="#42A5F5", edgecolor="#1565C0", linewidth=1,
    error_kw=dict(ecolor="#333333", linewidth=1.5),
)

# Add value labels just above each error bar
for i, (mean, std) in enumerate(zip(mpe_means, mpe_stds)):
    ax3.text(i, mean + std + 0.2, f"{mean:.1f}%", ha="center", va="bottom", fontsize=10)

ax3.set_xticks(range(len(distances)))
ax3.set_xticklabels([str(d) for d in distances])
ax3.set_xlabel("Ground Truth Distance (m)")
ax3.set_ylabel("Mean Percentage Error (%)")
ax3.set_title("Figure 3: Mean Percentage Error by Distance")
ax3.grid(True, axis="y", alpha=0.3)

fig3.tight_layout()
fig3.savefig("figure3_mpe_bar_chart.png")
print("Saved: figure3_mpe_bar_chart.png")

plt.close("all")
print("\nAnalysis complete.")
