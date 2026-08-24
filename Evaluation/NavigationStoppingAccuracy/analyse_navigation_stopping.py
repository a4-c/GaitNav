"""
Experiment 3: Navigation Stopping Accuracy — Data Analysis

printed to console:
  - Table 1: Overshoot summary
  - Table 2a/2b/2c: Accuracy statistics by distance (P1/P2/P3)
  - Table 3: Condition comparison summary (across participants)
  - Table 4: Between-participant comparison
  - Table 5: Statistical test results
  - Early-stop observation summary (P2 baseline)

saved as PNG:
  - Figure 1: Overshoot rate by distance (grouped bar chart)
  - Figure 2: Stopping error by distance — multi-panel (P1/P2/P3)
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from scipy.stats import wilcoxon, fisher_exact

# =====================================================================
# 1. Load data
# =====================================================================

OUTPUT_DIR = "./"

df = pd.read_csv("exp3_trial_data.csv")
df_info = pd.read_csv("exp3_participant_info.csv")

# Strip whitespace from string columns
for col in df.columns:
    if df[col].dtype == object:
        df[col] = df[col].str.strip()
for col in df_info.columns:
    if df_info[col].dtype == object:
        df_info[col] = df_info[col].str.strip()

# Ordered lists used throughout
PARTICIPANTS = ["P1", "P2", "P3"]
DISTANCES = [1.0, 2.0, 3.0, 4.0, 5.0, 7.0]
CONDITIONS = ["baseline", "adaptive"]

# Default step length used by the baseline condition
DEFAULT_STEP_LENGTH = 0.65

# Per-participant calibrated step length (adaptive condition)
CALIBRATED_STEPS = dict(
    zip(df_info["participant"], df_info["calibrated_step_length_m"])
)

# Condition order descriptions for Table 4
CONDITION_ORDER = {
    "P1": "Baseline first, then Adaptive",
    "P2": "Adaptive first, then Baseline",
    "P3": "Baseline first, then Adaptive",
}

# =====================================================================
# 2. Derived metric: safety-margin deviation
# =====================================================================

def expected_safety_margin(row):
    """Return the expected safety margin for a given row."""
    if row["condition"] == "baseline":
        return DEFAULT_STEP_LENGTH
    else:
        return CALIBRATED_STEPS[row["participant"]]

df["expected_margin"] = df.apply(expected_safety_margin, axis=1)
df["safety_margin_deviation"] = abs(df["stopping_error_m"] - df["expected_margin"])

# Flag overshoot trials
df["is_overshoot"] = df["overshoot"] == "true"

# Non-overshoot subset for accuracy analysis
df_safe = df[~df["is_overshoot"]].copy()

# =====================================================================
# 3. Table 1: Overshoot Summary
# =====================================================================

print("=" * 65)
print("Table 1: Overshoot Summary")
print("=" * 65)

b_all = df[df["condition"] == "baseline"]
a_all = df[df["condition"] == "adaptive"]
b_ov = int(b_all["is_overshoot"].sum())
a_ov = int(a_all["is_overshoot"].sum())
b_rate = b_ov / len(b_all) * 100
a_rate = a_ov / len(a_all) * 100

print(f"\n  {'Metric':<30} {'Baseline':<15} {'Adaptive':<15}")
print(f"  {'-'*30} {'-'*15} {'-'*15}")
print(f"  {'Total trials':<30} {len(b_all):<15} {len(a_all):<15}")
print(f"  {'Overshoot count':<30} {b_ov:<15} {a_ov:<15}")
print(f"  {'Overshoot rate':<30} {f'{b_rate:.1f}%':<15} {f'{a_rate:.1f}%':<15}")
print()

# =====================================================================
# 4. Figure 1: Overshoot Rate by Distance (grouped bar chart)
# =====================================================================

plt.rcParams.update({
    "figure.dpi": 150,
    "font.size": 11,
    "axes.titlesize": 13,
    "axes.labelsize": 12,
})

fig1, ax1 = plt.subplots(figsize=(9, 5))
x_pos = np.arange(len(DISTANCES))
width = 0.35

overshoot_rates = {}
for cond in CONDITIONS:
    rates = []
    for d in DISTANCES:
        sub = df[(df["condition"] == cond) & (df["target_distance_m"] == d)]
        total = len(sub)
        ov = sub["is_overshoot"].sum()
        rates.append(ov / total * 100 if total > 0 else 0)
    overshoot_rates[cond] = rates

ax1.bar(x_pos - width / 2, overshoot_rates["baseline"], width,
        color="#EF5350", edgecolor="#B71C1C", linewidth=1, label="Baseline")
ax1.bar(x_pos + width / 2, overshoot_rates["adaptive"], width,
        color="#42A5F5", edgecolor="#1565C0", linewidth=1, label="Adaptive")

for i, (vb, va) in enumerate(zip(overshoot_rates["baseline"],
                                  overshoot_rates["adaptive"])):
    ax1.text(i - width / 2, vb + 1, f"{vb:.0f}%", ha="center",
             va="bottom", fontsize=9)
    ax1.text(i + width / 2, va + 1, f"{va:.0f}%", ha="center",
             va="bottom", fontsize=9)

ax1.set_xticks(x_pos)
ax1.set_xticklabels([f"{d:.0f}m" for d in DISTANCES])
ax1.set_xlabel("Target Distance (m)")
ax1.set_ylabel("Overshoot Rate (%)")
ax1.set_title("Figure 1: Overshoot Rate by Distance")
ax1.set_ylim(0, max(max(overshoot_rates["baseline"]),
                     max(overshoot_rates["adaptive"])) + 15)
ax1.legend(loc="upper right", fontsize=10)
ax1.grid(True, axis="y", alpha=0.3)

fig1.tight_layout()
fig1.savefig(OUTPUT_DIR + "figure1_overshoot_rate_by_distance.png")
print("Saved: figure1_overshoot_rate_by_distance.png")

# =====================================================================
# 5. Table 2a/2b/2c: Accuracy Statistics by Distance (per participant)
#    Left-right layout: Baseline | Adaptive, rows by distance + Overall
# =====================================================================

print()

for idx, p in enumerate(PARTICIPANTS):
    cal_step = CALIBRATED_STEPS[p]
    table_label = chr(ord("a") + idx)  # a, b, c

    print("=" * 95)
    print(f"Table 2{table_label}: Accuracy Statistics — "
          f"{p} (calibrated step = {cal_step:.2f} m)")
    print("=" * 95)

    # Header: Distance | --- Baseline --- | --- Adaptive ---
    hdr_metric = "MAE     Std     SM Dev  SM Std"
    print(f"\n  {'Dist':<7}| {'--- Baseline ---':<32}| {'--- Adaptive ---':<32}")
    print(f"  {'':<7}| {'MAE':<8}{'Std':<8}{'SM Dev':<8}{'SM Std':<8}"
          f"| {'MAE':<8}{'Std':<8}{'SM Dev':<8}{'SM Std':<8}")
    print(f"  {'-'*7}+{'-'*32}+{'-'*32}")

    for d in DISTANCES + ["Overall"]:
        if d == "Overall":
            dist_label = "All"
            b_sub = df_safe[(df_safe["participant"] == p) &
                            (df_safe["condition"] == "baseline")]
            a_sub = df_safe[(df_safe["participant"] == p) &
                            (df_safe["condition"] == "adaptive")]
        else:
            dist_label = f"{d:.1f}m"
            b_sub = df_safe[(df_safe["participant"] == p) &
                            (df_safe["condition"] == "baseline") &
                            (df_safe["target_distance_m"] == d)]
            a_sub = df_safe[(df_safe["participant"] == p) &
                            (df_safe["condition"] == "adaptive") &
                            (df_safe["target_distance_m"] == d)]

        # Print separator before Overall
        if d == "Overall":
            print(f"  {'-'*7}+{'-'*32}+{'-'*32}")

        def fmt_side(sub):
            if len(sub) == 0:
                return f"{'N/A':<8}{'N/A':<8}{'N/A':<8}{'N/A':<8}"
            mae = sub["stopping_error_m"].mean()
            std = sub["stopping_error_m"].std(ddof=1)
            sm_m = sub["safety_margin_deviation"].mean()
            sm_s = sub["safety_margin_deviation"].std(ddof=1)
            return f"{mae:<8.3f}{std:<8.3f}{sm_m:<8.3f}{sm_s:<8.3f}"

        print(f"  {dist_label:<7}| {fmt_side(b_sub)}| {fmt_side(a_sub)}")

    print()

# =====================================================================
# 6. Figure 2: Stopping Error by Distance — multi-panel (P1/P2/P3)
# =====================================================================

fig2, axes = plt.subplots(1, 3, figsize=(16, 5), sharey=True)

colors = {"baseline": "#EF5350", "adaptive": "#42A5F5"}
offsets = {"baseline": -0.12, "adaptive": 0.12}
markers = {"baseline": "s", "adaptive": "o"}

for ax_idx, p in enumerate(PARTICIPANTS):
    ax = axes[ax_idx]
    cal_step = CALIBRATED_STEPS[p]
    x_pos = np.arange(len(DISTANCES))

    for cond in CONDITIONS:
        means = []
        stds = []
        for d in DISTANCES:
            sub = df_safe[(df_safe["participant"] == p) &
                          (df_safe["condition"] == cond) &
                          (df_safe["target_distance_m"] == d)]
            means.append(sub["stopping_error_m"].mean())
            stds.append(sub["stopping_error_m"].std(ddof=1))

        ax.errorbar(
            x_pos + offsets[cond], means, yerr=stds,
            fmt=markers[cond] + "-", color=colors[cond],
            capsize=4, capthick=1.5, linewidth=1.5, markersize=5,
            label=f"{cond.capitalize()}",
        )

    # Reference lines
    ax.axhline(y=0, color="#616161", linestyle="-", linewidth=0.8, alpha=0.4)
    ax.axhline(y=DEFAULT_STEP_LENGTH, color="#EF5350", linestyle="--",
               linewidth=1, alpha=0.6,
               label=f"Baseline margin ({DEFAULT_STEP_LENGTH} m)")
    ax.axhline(y=cal_step, color="#42A5F5", linestyle="--",
               linewidth=1, alpha=0.6,
               label=f"Adaptive margin ({cal_step:.2f} m)")

    ax.set_xticks(x_pos)
    ax.set_xticklabels([f"{d:.0f}" for d in DISTANCES])
    ax.set_xlabel("Target Distance (m)")
    ax.set_title(f"{p} (cal. step = {cal_step:.2f} m)", fontsize=12)
    ax.grid(True, axis="y", alpha=0.3)

    if ax_idx == 0:
        ax.set_ylabel("Stopping Error (m)")

    ax.legend(loc="upper left", fontsize=7)

fig2.suptitle("Figure 2: Stopping Error by Distance (Mean ± SD)",
              fontsize=14, y=1.02)
fig2.tight_layout()
fig2.savefig(OUTPUT_DIR + "figure2_stopping_error_by_distance.png",
             bbox_inches="tight")
print("Saved: figure2_stopping_error_by_distance.png")

# =====================================================================
# 7. Table 3: Condition Comparison Summary (across participants)
# =====================================================================

print()
print("=" * 70)
print("Table 3: Condition Comparison Summary (Across Participants)")
print("=" * 70)

metrics = {}
for cond in CONDITIONS:
    sub = df[df["condition"] == cond]
    sub_safe = df_safe[df_safe["condition"] == cond]
    metrics[cond] = {
        "overshoot_rate": sub["is_overshoot"].mean() * 100,
        "mae": sub_safe["stopping_error_m"].mean(),
        "std": sub_safe["stopping_error_m"].std(ddof=1),
        "sm_dev_mean": sub_safe["safety_margin_deviation"].mean(),
        "sm_dev_std": sub_safe["safety_margin_deviation"].std(ddof=1),
    }

print(f"\n  {'Metric':<35} {'Baseline':<12} {'Adaptive':<12} {'Diff':<12}")
print(f"  {'-'*35} {'-'*12} {'-'*12} {'-'*12}")

rows_t3 = [
    ("Overshoot rate (%)", "overshoot_rate", "{:.1f}", ""),
    ("MAE (m)", "mae", "{:.4f}", ""),
    ("Std dev (m)", "std", "{:.4f}", ""),
    ("Safety-margin dev mean (m)", "sm_dev_mean", "{:.4f}", ""),
    ("Safety-margin dev std dev (m)", "sm_dev_std", "{:.4f}", ""),
]

for label, key, fmt, _ in rows_t3:
    bv = metrics["baseline"][key]
    av = metrics["adaptive"][key]
    diff = bv - av
    bstr = fmt.format(bv)
    astr = fmt.format(av)
    dstr = fmt.format(diff)
    # Prefix diff with + or - for clarity (positive means baseline is larger)
    if diff > 0:
        dstr = "+" + dstr
    print(f"  {label:<35} {bstr:<12} {astr:<12} {dstr:<12}")

print()

# =====================================================================
# 8. Table 4: Between-Participant Comparison
# =====================================================================

print("=" * 95)
print("Table 4: Between-Participant Comparison")
print("=" * 95)

# Build per-participant metrics
p_data = {}
for p in PARTICIPANTS:
    cal_step = CALIBRATED_STEPS[p]
    pm = {"cal_step": cal_step, "order": CONDITION_ORDER[p]}
    for cond in CONDITIONS:
        sub = df[(df["participant"] == p) & (df["condition"] == cond)]
        sub_safe = df_safe[(df_safe["participant"] == p) &
                           (df_safe["condition"] == cond)]
        pm[f"{cond}_mae"] = sub_safe["stopping_error_m"].mean()
        pm[f"{cond}_sm_dev"] = sub_safe["safety_margin_deviation"].mean()
        pm[f"{cond}_ov_rate"] = sub["is_overshoot"].mean() * 100
    pm["delta_mae"] = pm["baseline_mae"] - pm["adaptive_mae"]
    pm["delta_sm_dev"] = pm["baseline_sm_dev"] - pm["adaptive_sm_dev"]
    p_data[p] = pm

# Column headers
p1_hdr = f"P1 ({CONDITION_ORDER['P1']})"
p2_hdr = f"P2 ({CONDITION_ORDER['P2']})"
p3_hdr = f"P3 (Random draw: {CONDITION_ORDER['P3']})"

col_w = 22
print(f"\n  {'Metric':<35} {p1_hdr:<{col_w}} {p2_hdr:<{col_w}} {p3_hdr}")
print(f"  {'-'*35} {'-'*col_w} {'-'*col_w} {'-'*col_w}")

table4_rows = [
    ("Calibrated step (m)",     "cal_step",        "{:.2f}"),
    ("Baseline MAE (m)",        "baseline_mae",    "{:.4f}"),
    ("Adaptive MAE (m)",        "adaptive_mae",    "{:.4f}"),
    ("MAE improvement (m)",     "delta_mae",       "{:+.4f}"),
    ("Baseline SM dev mean (m)","baseline_sm_dev",  "{:.4f}"),
    ("Adaptive SM dev mean (m)","adaptive_sm_dev",  "{:.4f}"),
    ("SM dev improvement (m)",  "delta_sm_dev",    "{:+.4f}"),
    ("Baseline overshoot rate", "baseline_ov_rate", "{:.1f}%"),
    ("Adaptive overshoot rate", "adaptive_ov_rate", "{:.1f}%"),
]

for label, key, fmt in table4_rows:
    vals = []
    for p in PARTICIPANTS:
        vals.append(fmt.format(p_data[p][key]))
    print(f"  {label:<35} {vals[0]:<{col_w}} {vals[1]:<{col_w}} {vals[2]}")

print()

# =====================================================================
# 9. Table 5: Statistical Test Results
# =====================================================================

print("=" * 95)
print("Table 5: Statistical Test Results")
print("=" * 95)

# ----- 9a. Wilcoxon signed-rank test (within-participant, paired by distance) -----
#
# Pairing rationale:
#   Trial order within each condition block was independently randomised,
#   so individual trials at the same distance are NOT naturally paired
#   across conditions.  Pairing by CSV row order would create artificial
#   pairs and inflate the effective sample size (30 "pairs" that are not
#   true matched observations).
#
#   The correct unit of analysis is the distance-level mean: for each
#   participant and each target distance, average the 5 repetitions'
#   safety-margin deviation under each condition.  This yields 6 genuine
#   paired observations (one per distance) per participant.
#
#   Trade-off: N = 6 limits statistical power.  The smallest achievable
#   one-tailed p-value is 1/2^6 = 0.0156 (all 6 differences in the
#   predicted direction with maximal rank sum).

print("\n  --- Wilcoxon Signed-Rank Test (within-participant, paired by distance) ---")
print(f"  H0: No difference in safety-margin deviation between conditions")
print(f"  H1: Adaptive produces smaller safety-margin deviation")
print(f"  Pairing unit: distance-level mean (5 repetitions averaged per distance)")
print(f"  Pairs per participant: {len(DISTANCES)}")
print()

for p in PARTICIPANTS:
    baseline_means = []
    adaptive_means = []

    print(f"  {p}:")
    print(f"    {'Distance':<10} {'Baseline':<12} {'Adaptive':<12} {'Diff':<12}")
    print(f"    {'-'*10} {'-'*12} {'-'*12} {'-'*12}")

    for d in DISTANCES:
        b_sub = df_safe[(df_safe["participant"] == p) &
                        (df_safe["condition"] == "baseline") &
                        (df_safe["target_distance_m"] == d)]
        a_sub = df_safe[(df_safe["participant"] == p) &
                        (df_safe["condition"] == "adaptive") &
                        (df_safe["target_distance_m"] == d)]

        b_mean = b_sub["safety_margin_deviation"].mean()
        a_mean = a_sub["safety_margin_deviation"].mean()
        baseline_means.append(b_mean)
        adaptive_means.append(a_mean)

        print(f"    {d:<10.1f} {b_mean:<12.4f} {a_mean:<12.4f} "
              f"{b_mean - a_mean:<+12.4f}")

    baseline_means = np.array(baseline_means)
    adaptive_means = np.array(adaptive_means)
    diffs = baseline_means - adaptive_means

    nonzero_mask = diffs != 0
    n_total = len(diffs)
    n_nonzero = nonzero_mask.sum()
    n_zero = n_total - n_nonzero

    # Count how many differences favour adaptive (positive)
    n_positive = (diffs > 0).sum()

    print(f"\n    Pairs: {n_total} total, {n_zero} zero-difference excluded, "
          f"{n_nonzero} tested")
    print(f"    Direction: {n_positive}/{n_total} distances favour adaptive")

    if n_nonzero > 0:
        stat, p_val = wilcoxon(
            diffs[nonzero_mask], alternative="greater"
        )
        print(f"    Test statistic (W+) = {stat:.1f}")
        print(f"    p-value (one-tailed) = {p_val:.6f}")

        if p_val < 0.05:
            print(f"    -> Reject H0 at alpha = 0.05: adaptive condition produces "
                  f"significantly smaller safety-margin deviation")
        else:
            print(f"    -> Fail to reject H0 at alpha = 0.05")
            if n_positive == n_total:
                print(f"       Note: all {n_total} differences favour adaptive, "
                      f"but N = {n_total} limits the minimum achievable p-value "
                      f"to {1 / 2**n_total:.4f}")
    else:
        print(f"    -> Cannot perform test: all differences are zero")
    print()

# ----- 9b. Fisher's exact test (overshoot rate) -----
print("  --- Fisher's Exact Test (overshoot rate comparison) ---")
print(f"  H0: No difference in overshoot rate between conditions")
print(f"  H1: Overshoot rate differs between conditions")
print()

for p in PARTICIPANTS:
    b_sub = df[(df["participant"] == p) & (df["condition"] == "baseline")]
    a_sub = df[(df["participant"] == p) & (df["condition"] == "adaptive")]

    b_overshoot = b_sub["is_overshoot"].sum()
    b_safe_n = len(b_sub) - b_overshoot
    a_overshoot = a_sub["is_overshoot"].sum()
    a_safe_n = len(a_sub) - a_overshoot

    print(f"  {p}:")
    print(f"    Contingency table:")
    print(f"                   Overshoot    Safe")
    print(f"      Baseline     {b_overshoot:<12} {b_safe_n}")
    print(f"      Adaptive     {a_overshoot:<12} {a_safe_n}")

    if b_overshoot == 0 and a_overshoot == 0:
        print(f"    -> No overshoot events in either condition. "
              f"Fisher's exact test is not applicable.")
        print(f"       Both conditions achieved 0% overshoot rate — "
              f"the system prevented all collisions.")
    else:
        odds_ratio, p_val = fisher_exact(
            [[b_overshoot, b_safe_n], [a_overshoot, a_safe_n]],
            alternative="two-sided",
        )
        print(f"    Odds ratio = {odds_ratio:.4f}")
        print(f"    p-value    = {p_val:.6f}")
        if p_val < 0.05:
            print(f"    -> Reject H0 at alpha = 0.05: overshoot rate differs "
                  f"significantly between conditions")
        else:
            print(f"    -> Fail to reject H0: no significant difference "
                  f"in overshoot rate")
    print()

# Combined Fisher's test
print("  Combined (all participants):")
b_all = df[df["condition"] == "baseline"]
a_all = df[df["condition"] == "adaptive"]
b_ov_total = b_all["is_overshoot"].sum()
b_safe_total = len(b_all) - b_ov_total
a_ov_total = a_all["is_overshoot"].sum()
a_safe_total = len(a_all) - a_ov_total

print(f"    Contingency table:")
print(f"                   Overshoot    Safe")
print(f"      Baseline     {b_ov_total:<12} {b_safe_total}")
print(f"      Adaptive     {a_ov_total:<12} {a_safe_total}")

if b_ov_total == 0 and a_ov_total == 0:
    print(f"    -> No overshoot events across all participants. "
          f"Fisher's exact test is not applicable.")
    print(f"       The system achieved 0% overshoot rate across all "
          f"180 trials — no collisions occurred.")
else:
    odds_ratio, p_val = fisher_exact(
        [[b_ov_total, b_safe_total], [a_ov_total, a_safe_total]],
        alternative="two-sided",
    )
    print(f"    Odds ratio = {odds_ratio:.4f}")
    print(f"    p-value    = {p_val:.6f}")
print()

# =====================================================================
# 10. Supplementary: P2 baseline early-stop observations
# =====================================================================

print("=" * 95)
print("Supplementary: Early-Stop Observations (P2 Baseline)")
print("=" * 95)

early_stop = df[df["notes"].str.contains("early", case=False, na=False)]
total_early = len(early_stop)
print(f"\n  Total early-stop trials: {total_early} / "
      f"{len(df[(df['participant'] == 'P2') & (df['condition'] == 'baseline')])} "
      f"(P2 baseline)")

if total_early > 0:
    print(f"\n  Distance distribution of early-stop trials:")
    dist_counts = early_stop["target_distance_m"].value_counts().sort_index()
    for d, count in dist_counts.items():
        print(f"    {d:.1f}m: {count} trials")

    print(f"\n  Stopping error comparison (P2 baseline):")
    p2b = df_safe[(df_safe["participant"] == "P2") &
                  (df_safe["condition"] == "baseline")]
    p2b_early = p2b[p2b["notes"].str.contains("early", case=False, na=False)]
    p2b_normal = p2b[~p2b["notes"].str.contains("early", case=False, na=False)]

    print(f"    Early-stop trials:  MAE = {p2b_early['stopping_error_m'].mean():.4f} m "
          f"(n = {len(p2b_early)})")
    print(f"    Normal-stop trials: MAE = {p2b_normal['stopping_error_m'].mean():.4f} m "
          f"(n = {len(p2b_normal)})")
    print(f"    All trials:         MAE = {p2b['stopping_error_m'].mean():.4f} m "
          f"(n = {len(p2b)})")

    print(f"\n  Interpretation:")
    print(f"    The participant stopped before the system announced 'stop' in "
          f"{total_early} trials.")
    print(f"    This suggests a mismatch between the fixed step length "
          f"(0.65m) and the")
    print(f"    participant's actual gait: the countdown lagged behind the "
          f"participant's")
    print(f"    body sense, causing them to stop based on their own judgement "
          f"rather than")
    print(f"    waiting for system guidance.")
print()

# =====================================================================
# 11. Export per-participant condition-level summary CSV
# =====================================================================

summary_rows = []
for p in PARTICIPANTS:
    for cond in CONDITIONS:
        sub = df[(df["participant"] == p) & (df["condition"] == cond)]
        sub_safe = df_safe[(df_safe["participant"] == p) &
                           (df_safe["condition"] == cond)]

        summary_rows.append({
            "participant": p,
            "condition": cond,
            "calibrated_step_m": CALIBRATED_STEPS[p],
            "expected_margin_m": (DEFAULT_STEP_LENGTH if cond == "baseline"
                                  else CALIBRATED_STEPS[p]),
            "n_trials": len(sub),
            "n_overshoot": int(sub["is_overshoot"].sum()),
            "overshoot_rate_pct": sub["is_overshoot"].mean() * 100,
            "mae_m": sub_safe["stopping_error_m"].mean(),
            "std_m": sub_safe["stopping_error_m"].std(ddof=1),
            "median_error_m": sub_safe["stopping_error_m"].median(),
            "sm_dev_mean_m": sub_safe["safety_margin_deviation"].mean(),
            "sm_dev_std_m": sub_safe["safety_margin_deviation"].std(ddof=1),
        })

df_summary = pd.DataFrame(summary_rows)
df_summary.to_csv(OUTPUT_DIR + "exp3_condition_summary.csv", index=False)
print("Saved: exp3_condition_summary.csv")

# =====================================================================
# 12. Done
# =====================================================================

plt.close("all")
print()
print("=" * 95)
print("Analysis complete.")
print("=" * 95)
