"""
Experiment 5: Real-time Performance — Data Analysis

printed to console:
  - Table 1 : Per-scenario performance summary (FPS + detection latency)
  - Table 2 : Speech feedback latency
  - Table 3 : Design target assessment

saved as PNG:
  - Figure 1: FPS time series (6 subplots)
  - Figure 2: Detection latency box plot per scenario
  - Figure 3: Speech feedback latency scatter plot
  - Figure 4: FPS box plot per scenario (supplementary)

saved as CSV:
  - exp5_scenario_summary.csv
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

# =====================================================================
# 1. Load data
# =====================================================================

OUTPUT_DIR = "./"

SCENARIOS = ["S1", "S2", "S3", "S4", "S5", "S6"]
SCENARIO_FILES = {
    "S1": "s1_data.csv",
    "S2": "s2_data.csv",
    "S3": "s3_data.csv",
    "S4": "s4_data.csv",
    "S5": "s5_data.csv",
    "S6": "s6_data.csv",
}
SCENARIO_LABELS = {
    "S1": "Empty scene",
    "S2": "Single obj., static",
    "S3": "Single obj., walking",
    "S4": "Multi obj., static",
    "S5": "Multi obj., walking",
    "S6": "Lighting variation",
}

# Design targets.
DESIGN_FPS_MIN = 10
DESIGN_SPEECH_MAX_S = 1.0

# Read and merge frame-by-frame performance logs from all scenarios.
frames = []
for scenario, filename in SCENARIO_FILES.items():
    try:
        scene_df = pd.read_csv(filename)
        if "scenario" not in scene_df.columns:
            scene_df["scenario"] = scenario
        frames.append(scene_df)
    except FileNotFoundError:
        print(f"WARNING: {filename} not found, skipping {scenario}")

df = pd.concat(frames, ignore_index=True)

for col in df.columns:
    if df[col].dtype == object:
        df[col] = df[col].str.strip()

# Parse timestamps and compute each frame's seconds relative to the first frame in its scenario.
df["timestamp"] = pd.to_datetime(df["timestamp"])
df["relative_seconds"] = df.groupby("scenario")["timestamp"].transform(
    lambda ts: (ts - ts.iloc[0]).dt.total_seconds()
)

# Read speech feedback latency data.
df_speech = pd.read_csv("exp5_speech_latency.csv")
for col in df_speech.columns:
    if df_speech[col].dtype == object:
        df_speech[col] = df_speech[col].str.strip()

print(f"Loaded {len(df)} frames across {df['scenario'].nunique()} scenarios")
print(f"Loaded {len(df_speech)} speech latency measurements")
print()

# =====================================================================
# 2. Compute per-second FPS by counting frames.
# =====================================================================
#
# Split each scenario's recording period into 1-second windows [0,1), [1,2), ...
# Count how many frames were actually completed inside each window; that count is the FPS for that second.
# If no frame was completed in a given second, record the FPS as 0.
# Exclude the final window when it is shorter than 1 full second.

fps_records = []
for s in SCENARIOS:
    sub = df[df["scenario"] == s].sort_values("relative_seconds")
    max_sec = sub["relative_seconds"].max()
    # Number of complete windows: for example, max_sec = 59.8 gives 59 complete windows [0,1)...[58,59).
    n_full_windows = int(max_sec)

    for t in range(n_full_windows):
        count = int(((sub["relative_seconds"] >= t) &
                      (sub["relative_seconds"] < t + 1)).sum())
        fps_records.append({
            "scenario": s,
            "second": t,
            "fps_counted": count,
        })

fps_per_second = pd.DataFrame(fps_records)

print(f"FPS per-second windows: {len(fps_per_second)} "
      f"(~{len(fps_per_second) // len(SCENARIOS)} per scenario)")
print()

# =====================================================================
# 3. Compute inter-frame gaps to detect brief stalls.
# =====================================================================

max_gap_per_scenario = {}
for s in SCENARIOS:
    sub = df[df["scenario"] == s].sort_values("timestamp")
    gaps_ms = sub["timestamp"].diff().dt.total_seconds() * 1000
    max_gap_per_scenario[s] = gaps_ms.max()

# =====================================================================
# Global plotting settings.
# =====================================================================

plt.rcParams.update({
    "figure.dpi": 150,
    "font.size": 11,
    "axes.titlesize": 13,
    "axes.labelsize": 12,
})

SCENARIO_COLORS = {
    "S1": "#42A5F5",
    "S2": "#66BB6A",
    "S3": "#FFA726",
    "S4": "#EF5350",
    "S5": "#AB47BC",
    "S6": "#78909C",
}

# =====================================================================
# 4. Table 1: Per-Scenario Performance Summary
# =====================================================================
#
# FPS columns: per-second FPS from the frame-counting method.
# Detection latency columns: frame-by-frame data.
# Maximum frame gap: exposes momentary stalls.
# No Overall row is added because different scenarios represent different operating conditions.

print("=" * 120)
print("Table 1: Per-Scenario Performance Summary")
print("=" * 120)

sub_header = (
    f"  {'':<30}"
    f"{'---- FPS (frame count/s) ----':<30}"
    f"{'--- Latency ms (per frame) ---':<28}"
)
header = (
    f"  {'Scenario':<8} {'Description':<22}"
    f"{'Mean':<7} {'Med.':<7} {'P5':<7} {'Min':<7}"
    f"  {'Med.':<8} {'P95':<8} {'Max':<8}"
    f"  {'MaxGap':<10}"
    f"{'N(s)':<6} {'N(frm)':<6}"
)
print(f"\n{sub_header}")
print(header)
print(f"  {'-'*118}")

for s in SCENARIOS:
    fps_s = fps_per_second[fps_per_second["scenario"] == s]["fps_counted"]
    lat_s = df[df["scenario"] == s]["detection_latency_ms"]
    gap_s = max_gap_per_scenario[s]

    print(
        f"  {s:<8} {SCENARIO_LABELS[s]:<22}"
        f"{fps_s.mean():<7.1f} {fps_s.median():<7.1f} "
        f"{fps_s.quantile(0.05):<7.1f} {fps_s.min():<7.0f}"
        f"  {lat_s.median():<8.2f} {lat_s.quantile(0.95):<8.2f} "
        f"{lat_s.max():<8.2f}"
        f"  {gap_s:<10.1f}"
        f"{len(fps_s):<6} {len(lat_s):<6}"
    )

print(f"\n  FPS: computed by counting frames in each complete 1-second window.")
print(f"  MaxGap: largest time gap between two consecutive frames (ms).")
print()

# =====================================================================
# 5. Figure 1: FPS Time Series (all scenarios on one plot)
# =====================================================================
#
# Combine all six scenarios in the same coordinate system with a shared y-axis range of 0-65.
# This avoids misleading readers with separate subplots that use different y-axis ranges.

fig1, ax1 = plt.subplots(figsize=(10, 5))

for s in SCENARIOS:
    sub = fps_per_second[fps_per_second["scenario"] == s].sort_values("second")
    ax1.plot(sub["second"], sub["fps_counted"],
             linewidth=1.2, color=SCENARIO_COLORS[s], alpha=0.8,
             label=f"{s}: {SCENARIO_LABELS[s]}")

# Design target reference line.
ax1.axhline(y=DESIGN_FPS_MIN, color="#D32F2F",
            linestyle="--", linewidth=1, alpha=0.7,
            label=f"Design target: {DESIGN_FPS_MIN} FPS")

ax1.set_xlim(0, 60)
ax1.set_ylim(0, 65)
ax1.set_xlabel("Time (seconds)")
ax1.set_ylabel("FPS (frames counted per second)")
ax1.grid(True, alpha=0.3)

# Place the legend above the plot in three columns and push it upward to avoid covering the plotting area.
ax1.legend(loc="lower center", bbox_to_anchor=(0.5, 1.02),
           ncol=3, fontsize=9, frameon=True, framealpha=0.9)
fig1.suptitle("Figure 1: FPS Time Series by Scenario",
              fontsize=13, y=1.05)

fig1.tight_layout(rect=[0, 0, 1, 0.88])
fig1.savefig(OUTPUT_DIR + "figure1_fps_time_series.png",
             bbox_inches="tight")
print("Saved: figure1_fps_time_series.png")

# =====================================================================
# 6. Figure 2: Detection Latency Box Plot per Scenario
# =====================================================================

fig2, ax2 = plt.subplots(figsize=(9, 5))

latency_data = [df[df["scenario"] == s]["detection_latency_ms"].values
                for s in SCENARIOS]

bp = ax2.boxplot(latency_data, tick_labels=SCENARIOS, patch_artist=True,
                 widths=0.5, showfliers=True,
                 flierprops=dict(marker="o", markersize=1.5, alpha=0.2))

for patch, s in zip(bp["boxes"], SCENARIOS):
    patch.set_facecolor(SCENARIO_COLORS[s])
    patch.set_alpha(0.6)

# Annotate the P95 value for each scenario.
for i, s in enumerate(SCENARIOS):
    lat_s = df[df["scenario"] == s]["detection_latency_ms"]
    p95 = lat_s.quantile(0.95)
    ax2.plot(i + 1, p95, "D", color="#212121", markersize=5, zorder=5)
    ax2.annotate(f"P95={p95:.1f}",
                 xy=(i + 1, p95),
                 xytext=(0, 8), textcoords="offset points",
                 fontsize=7.5, ha="center", color="#424242")

ax2.set_xlabel("Scenario")
ax2.set_ylabel("Detection Latency (ms)")
ax2.set_title("Figure 2: Detection Latency Distribution by Scenario")
ax2.grid(True, axis="y", alpha=0.3)

fig2.tight_layout()
fig2.savefig(OUTPUT_DIR + "figure2_latency_boxplot.png")
print("Saved: figure2_latency_boxplot.png")

# =====================================================================
# 7. Table 2: Speech Feedback Latency
# =====================================================================

print()
print("=" * 85)
print("Table 2: Speech Feedback Latency")
print("=" * 85)

SPEECH_SCENARIOS = sorted(df_speech["scenario"].unique())

print(f"\n  {'Scenario':<10}", end="")
for t in range(1, 6):
    print(f"{'T' + str(t):<8}", end="")
print(f"  {'Mean(s)':<9} {'SD(s)':<9} {'Max(s)':<9}")

print(f"  {'-'*10}", end="")
for _ in range(5):
    print(f"{'-'*8}", end="")
print(f"  {'-'*9} {'-'*9} {'-'*9}")

for s in SPEECH_SCENARIOS:
    sub = df_speech[df_speech["scenario"] == s].sort_values("trial")
    lats = sub["feedback_latency_s"].values

    print(f"  {s:<10}", end="")
    for lat in lats:
        print(f"{lat:<8.3f}", end="")
    for _ in range(5 - len(lats)):
        print(f"{'—':<8}", end="")
    print(f"  {np.mean(lats):<9.3f} {np.std(lats, ddof=1):<9.3f} "
          f"{np.max(lats):<9.3f}")

print(f"\n  Total measurements: {len(df_speech)}")
print()

# =====================================================================
# 8. Figure 3: Speech Feedback Latency Scatter Plot
# =====================================================================

fig3, ax3 = plt.subplots(figsize=(5, 4.5))

speech_colors = {"S2": "#42A5F5", "S4": "#EF5350"}
rng_speech = np.random.default_rng(42)

# Keep the x positions of S2 and S4 near the center to reduce empty space on both sides.
x_positions = {s: i * 0.5 + 0.25 for i, s in enumerate(SPEECH_SCENARIOS)}

for s in SPEECH_SCENARIOS:
    sub = df_speech[df_speech["scenario"] == s]
    jitter = rng_speech.uniform(-0.08, 0.08, size=len(sub))
    ax3.scatter(
        np.full(len(sub), x_positions[s]) + jitter,
        sub["feedback_latency_s"].values,
        s=50, color=speech_colors.get(s, "#757575"),
        edgecolors="#424242", linewidths=0.8,
        zorder=3, alpha=0.85
    )

ax3.axhline(y=DESIGN_SPEECH_MAX_S, color="#D32F2F",
            linestyle="--", linewidth=1, alpha=0.7,
            label=f"Design target: {DESIGN_SPEECH_MAX_S}s")

ax3.set_xticks(list(x_positions.values()))
ax3.set_xticklabels([f"{s}\n({SCENARIO_LABELS.get(s, s)})"
                      for s in SPEECH_SCENARIOS], fontsize=9)
ax3.set_xlim(-0.05, 1.05)
ax3.set_ylabel("Feedback Latency (s)")
ax3.set_title("Figure 3: Speech Feedback Latency\n(Individual Measurements)")
ax3.legend(loc="upper right", fontsize=9)
ax3.grid(True, axis="y", alpha=0.3)

fig3.tight_layout()
fig3.savefig(OUTPUT_DIR + "figure3_speech_latency_scatter.png")
print("Saved: figure3_speech_latency_scatter.png")

# =====================================================================
# 9. Table 3: Design Target Assessment
# =====================================================================
#
# There are only two design targets, and both are assessed using the strictest rule: every measurement must pass.
# Detection latency P95 is already described in Table 1, so it is not assessed separately as pass/fail.

print("=" * 95)
print("Table 3: Design Target Assessment")
print("=" * 95)

print(f"\n  {'Design Target':<28} {'Criterion':<40} "
      f"{'Worst Measured':<18} {'Met?':<5}")
print(f"  {'-'*28} {'-'*40} {'-'*18} {'-'*5}")

# --- 1. Stable FPS >= 10 ---
# Assessment method: FPS in every complete 1-second window must be >= DESIGN_FPS_MIN.
all_fps = fps_per_second["fps_counted"]
fps_worst = int(all_fps.min())
fps_worst_scenario = fps_per_second.loc[
    all_fps.idxmin(), "scenario"
]
fps_met = fps_worst >= DESIGN_FPS_MIN

print(f"  {f'Stable FPS >= {DESIGN_FPS_MIN}':<28} "
      f"{'All complete 1-s windows >= ' + str(DESIGN_FPS_MIN) + ' FPS':<40} "
      f"{str(fps_worst) + ' FPS (' + fps_worst_scenario + ')':<18} "
      f"{'Yes' if fps_met else 'NO':<5}")

# --- 2. Speech latency < 1s ---
# Assessment method: all 10 measurements must be < DESIGN_SPEECH_MAX_S.
all_speech = df_speech["feedback_latency_s"]
speech_worst = all_speech.max()
speech_worst_row = df_speech.loc[all_speech.idxmax()]
speech_worst_scenario = speech_worst_row["scenario"]
speech_met = bool((all_speech < DESIGN_SPEECH_MAX_S).all())
n_speech = len(all_speech)

print(f"  {f'Speech latency < {DESIGN_SPEECH_MAX_S}s':<28} "
      f"{f'All {n_speech} measurements < {DESIGN_SPEECH_MAX_S}s':<40} "
      f"{f'{speech_worst:.3f}s ({speech_worst_scenario})':<18} "
      f"{'Yes' if speech_met else 'NO':<5}")

# --- Supplementary: maximum frame gap ---
worst_gap_s = max(max_gap_per_scenario, key=max_gap_per_scenario.get)
worst_gap_v = max_gap_per_scenario[worst_gap_s]

print(f"\n  Supplementary: largest frame gap = {worst_gap_v:.1f}ms "
      f"({worst_gap_s})")

print(f"\n  Note: Design targets derived from engineering reasoning")
print(f"  (walking speed, safety distance, Proposal requirements),")
print(f"  not established standards from literature.")
print()

# =====================================================================
# 10. Figure 4: FPS Box Plot per Scenario (Supplementary)
# =====================================================================

fig4, ax4 = plt.subplots(figsize=(8, 5))

fps_boxdata = [
    fps_per_second[fps_per_second["scenario"] == s]["fps_counted"].values
    for s in SCENARIOS
]

bp4 = ax4.boxplot(fps_boxdata, tick_labels=SCENARIOS, patch_artist=True,
                  widths=0.5, showfliers=True,
                  flierprops=dict(marker="o", markersize=3, alpha=0.4))

for patch, s in zip(bp4["boxes"], SCENARIOS):
    patch.set_facecolor(SCENARIO_COLORS[s])
    patch.set_alpha(0.6)

ax4.axhline(y=DESIGN_FPS_MIN, color="#D32F2F",
            linestyle="--", linewidth=1, alpha=0.7,
            label=f"Design target: {DESIGN_FPS_MIN} FPS")

ax4.set_xlabel("Scenario")
ax4.set_ylabel("FPS (frames counted per second)")
ax4.set_title("Figure 4 (Supplementary): FPS Distribution by Scenario")
ax4.legend(loc="lower right", fontsize=9)
ax4.grid(True, axis="y", alpha=0.3)

fig4.tight_layout()
fig4.savefig(OUTPUT_DIR + "figure4_fps_boxplot.png")
print("Saved: figure4_fps_boxplot.png")

# =====================================================================
# 11. Export scenario-level summary CSV
# =====================================================================

export_rows = []
for s in SCENARIOS:
    fps_s = fps_per_second[fps_per_second["scenario"] == s]["fps_counted"]
    lat_s = df[df["scenario"] == s]["detection_latency_ms"]
    oc_s = df[df["scenario"] == s]["object_count"]

    export_rows.append({
        "scenario": s,
        "description": SCENARIO_LABELS[s],
        "n_seconds": len(fps_s),
        "n_frames": len(lat_s),
        "fps_mean": round(fps_s.mean(), 2),
        "fps_median": round(fps_s.median(), 2),
        "fps_p5": round(fps_s.quantile(0.05), 2),
        "fps_min": int(fps_s.min()),
        "latency_median_ms": round(lat_s.median(), 2),
        "latency_p95_ms": round(lat_s.quantile(0.95), 2),
        "latency_max_ms": round(lat_s.max(), 2),
        "max_frame_gap_ms": round(max_gap_per_scenario[s], 2),
        "object_count_mean": round(oc_s.mean(), 2),
        "object_count_max": int(oc_s.max()),
    })

df_export = pd.DataFrame(export_rows)
df_export.to_csv(OUTPUT_DIR + "exp5_scenario_summary.csv", index=False)
print("Saved: exp5_scenario_summary.csv")

# =====================================================================
# 12. Done
# =====================================================================

plt.close("all")
print()
print("=" * 100)
print("Analysis complete.")
print("=" * 100)
