"""
Experiment 4: Feedback Mode Comparison — Data Analysis

printed to console:
  - Table 1 : Condition-level hesitation summary
  - Table 1b: Hesitation by condition × distance (exploratory)
  - Table 2 : Per-participant hesitation detail
  - Table 3 : Questionnaire dimension comparison (Q1–Q6)
  - Table 4 : Overall preference (Q7, Q8)
  - Table 5 : Statistical test results

saved as PNG:
  - Figure 1: Paired dot plot — hesitation (participant-level means)
  - Figure 2: Likert rating comparison — grouped bar chart (Q1–Q6)

saved as CSV:
  - exp4_condition_summary.csv
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from scipy.stats import wilcoxon

# =====================================================================
# 1. Load data
# =====================================================================

OUTPUT_DIR = "./"

df = pd.read_csv("exp4_trial_data.csv")
df_q = pd.read_csv("exp4_condition_questionnaire.csv")
df_cmp = pd.read_csv("exp4_comparison_questionnaire.csv")
df_info = pd.read_csv("exp4_participant_info.csv")

# Strip whitespace from string columns
for frame in [df, df_q, df_cmp, df_info]:
    for col in frame.columns:
        if frame[col].dtype == object:
            frame[col] = frame[col].str.strip()

# Ordered lists used throughout
PARTICIPANTS = ["P1", "P2", "P3", "P4", "P5"]
DISTANCES = [3.0, 5.0, 7.0]
CONDITIONS = ["steps", "metres"]

# Likert question columns and their dimension labels
LIKERT_COLS = [
    "Q1_comprehensibility",
    "Q2_spatial_awareness",
    "Q3_actionability",
    "Q4_safety",
    "Q5_information_pacing",
    "Q6_cognitive_load",
]
LIKERT_LABELS = {
    "Q1_comprehensibility": "Comprehensibility",
    "Q2_spatial_awareness": "Spatial Awareness",
    "Q3_actionability": "Actionability",
    "Q4_safety": "Safety",
    "Q5_information_pacing": "Information Pacing",
    "Q6_cognitive_load": "Cognitive Load (rev.)",
}
LIKERT_SHORT = ["Q1", "Q2", "Q3", "Q4", "Q5", "Q6"]

# Condition order per participant (from participant_info)
CONDITION_ORDER = {}
for _, row in df_info.iterrows():
    p = row["participant"]
    first = row["condition_order_first"]
    second = row["condition_order_second"]
    assignment = row["order_assignment"]
    CONDITION_ORDER[p] = {
        "first": first,
        "second": second,
        "assignment": assignment,
        "label": f"{first.capitalize()} first, then {second.capitalize()}"
                 + (f" ({assignment})" if "random" in str(assignment) else ""),
    }

# =====================================================================
# 2. Participant-level aggregation
# =====================================================================
#
# The correct unit of analysis is the participant-level mean:
# each participant's 9 trials per condition are averaged into a
# single value before pairing.  Individual trials within a condition
# block are not independent (same person, same chair, sequential),
# so they cannot be treated as separate observations.

participant_hesitation = {}  # {participant: {condition: mean_hesitation}}

for p in PARTICIPANTS:
    participant_hesitation[p] = {}
    for cond in CONDITIONS:
        sub = df[(df["participant"] == p) & (df["condition"] == cond)]
        participant_hesitation[p][cond] = sub["hesitation_count"].mean()

# =====================================================================
# 3. Table 1: Condition-Level Hesitation Summary
# =====================================================================

print("=" * 65)
print("Table 1: Condition-Level Hesitation Summary")
print("=" * 65)

print(f"\n  {'Metric':<35} {'Steps':<15} {'Metres':<15}")
print(f"  {'-'*35} {'-'*15} {'-'*15}")

n_steps = len(df[df["condition"] == "steps"])
n_metres = len(df[df["condition"] == "metres"])
print(f"  {'Total trials':<35} {n_steps:<15} {n_metres:<15}")

# Participant-level means → grand mean and SD
steps_means = [participant_hesitation[p]["steps"] for p in PARTICIPANTS]
metres_means = [participant_hesitation[p]["metres"] for p in PARTICIPANTS]

s_grand = np.mean(steps_means)
s_sd = np.std(steps_means, ddof=1)
m_grand = np.mean(metres_means)
m_sd = np.std(metres_means, ddof=1)

print(f"  {'Mean hesitation (participant M)':<35} {s_grand:<15.3f} {m_grand:<15.3f}")
print(f"  {'SD (across participants)':<35} {s_sd:<15.3f} {m_sd:<15.3f}")
print()

# =====================================================================
# 4. Table 1b: Hesitation by Condition × Distance (Exploratory)
# =====================================================================

print("=" * 65)
print("Table 1b: Hesitation by Condition x Distance (Exploratory)")
print("=" * 65)

print(f"\n  {'Condition':<10} {'Distance':<12} {'Mean Hes.':<12} "
      f"{'SD':<10} {'N trials':<10}")
print(f"  {'-'*10} {'-'*12} {'-'*12} {'-'*10} {'-'*10}")

for cond in CONDITIONS:
    for d in DISTANCES:
        sub = df[(df["condition"] == cond) &
                 (df["starting_distance_m"] == d)]
        n = len(sub)
        if n > 0:
            mean_h = sub["hesitation_count"].mean()
            sd_h = sub["hesitation_count"].std(ddof=1)
            print(f"  {cond:<10} {d:<12.1f} {mean_h:<12.3f} "
                  f"{sd_h:<10.3f} {n:<10}")
        else:
            print(f"  {cond:<10} {d:<12.1f} {'N/A':<12} "
                  f"{'N/A':<10} {0:<10}")

print(f"\n  Note: Each cell pools 5 participants x 3 reps = 15 trials.")
print(f"  Exploratory only — no statistical test at this level.")
print()

# =====================================================================
# 5. Figure 1: Paired Dot Plot — Hesitation (Participant-Level Means)
# =====================================================================

plt.rcParams.update({
    "figure.dpi": 150,
    "font.size": 11,
    "axes.titlesize": 13,
    "axes.labelsize": 12,
})

fig1, ax1 = plt.subplots(figsize=(6, 5))

x_steps = 0
x_metres = 1

# Plot individual participant points and connecting lines
for p in PARTICIPANTS:
    s_val = participant_hesitation[p]["steps"]
    m_val = participant_hesitation[p]["metres"]
    ax1.plot([x_steps, x_metres], [s_val, m_val],
             "o-", color="#757575", linewidth=1.2,
             markersize=7, markerfacecolor="white",
             markeredgecolor="#424242", markeredgewidth=1.5,
             zorder=3)
    # Label each participant
    ax1.annotate(p, (x_metres, m_val),
                 textcoords="offset points", xytext=(8, 0),
                 fontsize=9, color="#616161", va="center")

# Grand means as larger markers
ax1.plot(x_steps, s_grand, "D", color="#42A5F5", markersize=10,
         alpha=0.45, zorder=2, label=f"Steps mean ({s_grand:.2f})")
ax1.plot(x_metres, m_grand, "D", color="#EF5350", markersize=10,
         zorder=4, label=f"Metres mean ({m_grand:.2f})")

ax1.set_xticks([x_steps, x_metres])
ax1.set_xticklabels(["Steps", "Metres"])
ax1.set_ylabel("Mean Hesitation Count (per trial)")
ax1.set_title("Figure 1: Hesitation by Feedback Mode\n"
              "(participant-level means, paired)")
ax1.set_xlim(-0.5, 1.8)
ax1.legend(loc="upper left", fontsize=9)
ax1.grid(True, axis="y", alpha=0.3)

fig1.tight_layout()
fig1.savefig(OUTPUT_DIR + "figure1_hesitation_paired_dot.png")
print("Saved: figure1_hesitation_paired_dot.png")

# =====================================================================
# 6. Table 2: Per-Participant Hesitation Detail
# =====================================================================

print()
print("=" * 95)
print("Table 2: Per-Participant Hesitation Detail")
print("=" * 95)

print(f"\n  {'Participant':<14} {'Condition':<10} "
      f"{'Mean Hes.':<12} {'SD':<12} {'Order'}")
print(f"  {'-'*14} {'-'*10} {'-'*12} {'-'*12} {'-'*35}")

for p in PARTICIPANTS:
    order_label = CONDITION_ORDER[p]["label"]
    for cond in CONDITIONS:
        sub = df[(df["participant"] == p) & (df["condition"] == cond)]
        mean_h = sub["hesitation_count"].mean()
        sd_h = sub["hesitation_count"].std(ddof=1)

        # Only print order on the first row for this participant
        order_str = order_label if cond == CONDITIONS[0] else ""
        print(f"  {p:<14} {cond:<10} {mean_h:<12.3f} "
              f"{sd_h:<12.3f} {order_str}")
    # Separator between participants
    if p != PARTICIPANTS[-1]:
        print()

print()

# Collision/intervention/clarification summary from notes
print("  --- Notable Events (from notes) ---")
notes_all = df[df["notes"].notna() & (df["notes"].str.strip() != "")]
if len(notes_all) > 0:
    for _, row in notes_all.iterrows():
        print(f"    {row['participant']} | {row['condition']} | "
              f"Trial {row['trial_number_within_condition']} | "
              f"{row['starting_distance_m']:.1f}m | "
              f"{row['notes']}")
else:
    print("    No notable events recorded.")
print()

# =====================================================================
# 7. Figure 2: Likert Rating Comparison — Grouped Bar Chart (Q1–Q6)
# =====================================================================

fig2, ax2 = plt.subplots(figsize=(10, 5.5))

x_pos = np.arange(len(LIKERT_COLS))
width = 0.32

# Compute per-condition means and individual scores
steps_q_means = []
metres_q_means = []
steps_q_individual = []
metres_q_individual = []

for col in LIKERT_COLS:
    s_scores = df_q[df_q["condition"] == "steps"][col].values.astype(float)
    m_scores = df_q[df_q["condition"] == "metres"][col].values.astype(float)
    steps_q_means.append(np.mean(s_scores))
    metres_q_means.append(np.mean(m_scores))
    steps_q_individual.append(s_scores)
    metres_q_individual.append(m_scores)

bars_s = ax2.bar(x_pos - width / 2, steps_q_means, width,
                 color="#42A5F5", edgecolor="#1565C0", linewidth=1,
                 label="Steps", zorder=2)
bars_m = ax2.bar(x_pos + width / 2, metres_q_means, width,
                 color="#EF5350", edgecolor="#B71C1C", linewidth=1,
                 label="Metres", zorder=2)

# Overlay individual data points with jitter
rng = np.random.default_rng(42)
for i in range(len(LIKERT_COLS)):
    s_vals = steps_q_individual[i]
    m_vals = metres_q_individual[i]
    jitter_s = rng.uniform(-0.06, 0.06, size=len(s_vals))
    jitter_m = rng.uniform(-0.06, 0.06, size=len(m_vals))
    ax2.scatter(np.full(len(s_vals), x_pos[i] - width / 2) + jitter_s,
                s_vals, color="#1565C0", s=18, zorder=3, alpha=0.7)
    ax2.scatter(np.full(len(m_vals), x_pos[i] + width / 2) + jitter_m,
                m_vals, color="#B71C1C", s=18, zorder=3, alpha=0.7)

ax2.set_xticks(x_pos)
xtick_labels = [f"{s}\n{LIKERT_LABELS[c]}"
                for s, c in zip(LIKERT_SHORT, LIKERT_COLS)]
ax2.set_xticklabels(xtick_labels, fontsize=9)
ax2.set_ylabel("Likert Rating (1-7)")
ax2.set_ylim(0.5, 7.8)
ax2.set_title("Figure 2: Subjective Ratings by Feedback Mode "
              "(Mean + Individual)")
ax2.legend(loc="lower right", fontsize=10)
ax2.grid(True, axis="y", alpha=0.3)

fig2.tight_layout()
fig2.savefig(OUTPUT_DIR + "figure2_likert_comparison.png")
print("Saved: figure2_likert_comparison.png")

# =====================================================================
# 8. Table 3: Questionnaire Dimension Comparison (Q1–Q6)
# =====================================================================

print()
print("=" * 75)
print("Table 3: Questionnaire Dimension Comparison (Q1-Q6)")
print("=" * 75)

print(f"\n  {'Question':<8} {'Dimension':<22} "
      f"{'Steps M':<10} {'Metres M':<10} {'Diff (S-M)':<10}")
print(f"  {'-'*8} {'-'*22} {'-'*10} {'-'*10} {'-'*10}")

for i, col in enumerate(LIKERT_COLS):
    s_mean = df_q[df_q["condition"] == "steps"][col].astype(float).mean()
    m_mean = df_q[df_q["condition"] == "metres"][col].astype(float).mean()
    diff = s_mean - m_mean
    dim = LIKERT_LABELS[col]
    short = LIKERT_SHORT[i]
    print(f"  {short:<8} {dim:<22} {s_mean:<10.2f} {m_mean:<10.2f} "
          f"{diff:+10.2f}")

# Overall usability score per participant
steps_overall = []
metres_overall = []
for p in PARTICIPANTS:
    s_row = df_q[(df_q["participant"] == p) & (df_q["condition"] == "steps")]
    m_row = df_q[(df_q["participant"] == p) & (df_q["condition"] == "metres")]
    s_scores = s_row[LIKERT_COLS].values.flatten().astype(float)
    m_scores = m_row[LIKERT_COLS].values.flatten().astype(float)
    steps_overall.append(np.mean(s_scores))
    metres_overall.append(np.mean(m_scores))

s_ov_mean = np.mean(steps_overall)
m_ov_mean = np.mean(metres_overall)
ov_diff = s_ov_mean - m_ov_mean

print(f"  {'-'*8} {'-'*22} {'-'*10} {'-'*10} {'-'*10}")
print(f"  {'--':<8} {'Overall Usability':<22} "
      f"{s_ov_mean:<10.2f} {m_ov_mean:<10.2f} {ov_diff:+10.2f}")

print(f"\n  Positive diff = Steps rated higher; "
      f"negative diff = Metres rated higher.")
print(f"  Overall usability = mean of Q1-Q6 per participant per condition.")
print()

# =====================================================================
# 9. Table 4: Overall Preference (Q7, Q8)
# =====================================================================

print("=" * 75)
print("Table 4: Overall Preference (Q7, Q8)")
print("=" * 75)

print(f"\n  {'Participant':<14} {'Q7 Preference':<18} {'Q8 Reason'}")
print(f"  {'-'*14} {'-'*18} {'-'*50}")

for _, row in df_cmp.iterrows():
    p = row["participant"]
    q7 = str(row["Q7_preference"])
    q8 = str(row["Q8_reason"])
    # Truncate long reasons for table display
    if len(q8) > 70:
        q8 = q8[:67] + "..."
    print(f"  {p:<14} {q7:<18} {q8}")

# Tally (normalise to lowercase for counting)
q7_lower = df_cmp["Q7_preference"].str.lower().str.strip()
pref_counts = q7_lower.value_counts()
print(f"\n  Summary: ", end="")
parts = []
for choice in ["steps", "metres", "no difference"]:
    count = pref_counts.get(choice, 0)
    parts.append(f"{count}/5 chose {choice.capitalize()}")
print(", ".join(parts))
print()

# =====================================================================
# 10. Table 5: Statistical Test Results
# =====================================================================

print("=" * 75)
print("Table 5: Statistical Test Results")
print("=" * 75)

# ----- 10a. Wilcoxon signed-rank test: hesitation -----
#
# Pairing rationale:
#   Each participant's 9 trials within a condition are not independent
#   (same person, same chair, sequential).  The correct unit of
#   analysis is the participant-level mean.  This yields N = 5 paired
#   observations.  The smallest achievable one-tailed p-value is
#   1/2^5 = 0.03125 (all 5 differences in the predicted direction
#   with maximal rank sum).

print("\n  --- Wilcoxon Signed-Rank Test: Hesitation Count ---")
print(f"  H0: No difference in mean hesitation between conditions")
print(f"  H1: Steps condition produces fewer hesitations (one-tailed)")
print(f"  Pairing unit: participant-level mean (9 trials averaged)")
print(f"  N = {len(PARTICIPANTS)} pairs")
print()

steps_hes = np.array([participant_hesitation[p]["steps"]
                       for p in PARTICIPANTS])
metres_hes = np.array([participant_hesitation[p]["metres"]
                        for p in PARTICIPANTS])
diffs_hes = metres_hes - steps_hes  # positive = metres has more hesitation

print(f"  {'Participant':<14} {'Steps Mean':<14} {'Metres Mean':<14} "
      f"{'Diff (M-S)':<14}")
print(f"  {'-'*14} {'-'*14} {'-'*14} {'-'*14}")
for i, p in enumerate(PARTICIPANTS):
    print(f"  {p:<14} {steps_hes[i]:<14.3f} {metres_hes[i]:<14.3f} "
          f"{diffs_hes[i]:+14.3f}")

n_favour_steps = int((diffs_hes > 0).sum())
n_tie = int((diffs_hes == 0).sum())
n_favour_metres = int((diffs_hes < 0).sum())

print(f"\n  Direction: {n_favour_steps}/{len(PARTICIPANTS)} favour Steps, "
      f"{n_favour_metres}/{len(PARTICIPANTS)} favour Metres, "
      f"{n_tie}/{len(PARTICIPANTS)} tied")

nonzero_mask = diffs_hes != 0
n_nonzero = int(nonzero_mask.sum())

hes_stat = np.nan
hes_p = np.nan

if n_nonzero >= 1:
    hes_stat, hes_p = wilcoxon(
        metres_hes[nonzero_mask], steps_hes[nonzero_mask],
        alternative="greater"
    )
    print(f"  Effective N (excl. ties): {n_nonzero}")
    print(f"  Test statistic (W+) = {hes_stat:.1f}")
    print(f"  p-value (one-tailed) = {hes_p:.6f}")

    if hes_p < 0.05:
        print(f"  -> Reject H0 at alpha = 0.05: Steps condition produces "
              f"significantly fewer hesitations")
    else:
        print(f"  -> Fail to reject H0 at alpha = 0.05")
        if n_favour_steps == len(PARTICIPANTS):
            print(f"     Note: all {len(PARTICIPANTS)} differences favour "
                  f"Steps, but N = {len(PARTICIPANTS)} limits the minimum "
                  f"achievable p-value to "
                  f"{1 / 2**len(PARTICIPANTS):.4f}")
else:
    print(f"  -> Cannot perform test: all differences are zero")
print()

# ----- 10b. Wilcoxon signed-rank test: overall usability -----

print("  --- Wilcoxon Signed-Rank Test: Overall Usability Score ---")
print(f"  H0: No difference in overall usability between conditions")
print(f"  H1: Steps condition has higher usability (one-tailed)")
print(f"  Pairing unit: participant-level mean of Q1-Q6")
print(f"  N = {len(PARTICIPANTS)} pairs")
print()

steps_us = np.array(steps_overall)
metres_us = np.array(metres_overall)
diffs_us = steps_us - metres_us  # positive = steps rated higher

print(f"  {'Participant':<14} {'Steps Score':<14} {'Metres Score':<14} "
      f"{'Diff (S-M)':<14}")
print(f"  {'-'*14} {'-'*14} {'-'*14} {'-'*14}")
for i, p in enumerate(PARTICIPANTS):
    print(f"  {p:<14} {steps_us[i]:<14.3f} {metres_us[i]:<14.3f} "
          f"{diffs_us[i]:+14.3f}")

n_favour_steps_us = int((diffs_us > 0).sum())
n_tie_us = int((diffs_us == 0).sum())
n_favour_metres_us = int((diffs_us < 0).sum())

print(f"\n  Direction: {n_favour_steps_us}/{len(PARTICIPANTS)} favour Steps, "
      f"{n_favour_metres_us}/{len(PARTICIPANTS)} favour Metres, "
      f"{n_tie_us}/{len(PARTICIPANTS)} tied")

nonzero_mask_us = diffs_us != 0
n_nonzero_us = int(nonzero_mask_us.sum())

us_stat = np.nan
us_p = np.nan

if n_nonzero_us >= 1:
    us_stat, us_p = wilcoxon(
        steps_us[nonzero_mask_us], metres_us[nonzero_mask_us],
        alternative="greater"
    )
    print(f"  Effective N (excl. ties): {n_nonzero_us}")
    print(f"  Test statistic (W+) = {us_stat:.1f}")
    print(f"  p-value (one-tailed) = {us_p:.6f}")

    if us_p < 0.05:
        print(f"  -> Reject H0 at alpha = 0.05: Steps condition has "
              f"significantly higher usability scores")
    else:
        print(f"  -> Fail to reject H0 at alpha = 0.05")
        if n_favour_steps_us == len(PARTICIPANTS):
            print(f"     Note: all {len(PARTICIPANTS)} differences favour "
                  f"Steps, but N = {len(PARTICIPANTS)} limits the minimum "
                  f"achievable p-value to "
                  f"{1 / 2**len(PARTICIPANTS):.4f}")
else:
    print(f"  -> Cannot perform test: all differences are zero")
print()

# ----- 10c. Summary table -----

print("  --- Summary ---")
print(f"\n  {'Metric':<28} {'N':<5} {'Steps':<10} {'Metres':<10} "
      f"{'W+':<8} {'p':<12} {'Sig.':<8}")
print(f"  {'-'*28} {'-'*5} {'-'*10} {'-'*10} "
      f"{'-'*8} {'-'*12} {'-'*8}")

hes_w_str = f"{hes_stat:.1f}" if not np.isnan(hes_stat) else "N/A"
hes_p_str = f"{hes_p:.6f}" if not np.isnan(hes_p) else "N/A"
hes_sig = ("Yes" if (not np.isnan(hes_p) and hes_p < 0.05)
           else "No")
print(f"  {'Mean hesitation':<28} {len(PARTICIPANTS):<5} "
      f"{np.mean(steps_hes):<10.3f} {np.mean(metres_hes):<10.3f} "
      f"{hes_w_str:<8} {hes_p_str:<12} {hes_sig:<8}")

us_w_str = f"{us_stat:.1f}" if not np.isnan(us_stat) else "N/A"
us_p_str = f"{us_p:.6f}" if not np.isnan(us_p) else "N/A"
us_sig = ("Yes" if (not np.isnan(us_p) and us_p < 0.05)
          else "No")
print(f"  {'Overall usability score':<28} {len(PARTICIPANTS):<5} "
      f"{np.mean(steps_us):<10.3f} {np.mean(metres_us):<10.3f} "
      f"{us_w_str:<8} {us_p_str:<12} {us_sig:<8}")
print()

# =====================================================================
# 11. Cross-participant consistency check
# =====================================================================

print("=" * 75)
print("Cross-Participant Consistency Check")
print("=" * 75)

print(f"\n  {'Participant':<14} {'Hes. direction':<18} "
      f"{'Usability dir.':<18} {'Q7 preference':<16}")
print(f"  {'-'*14} {'-'*18} {'-'*18} {'-'*16}")

for i, p in enumerate(PARTICIPANTS):
    if diffs_hes[i] > 0:
        hes_dir = "Steps better"
    elif diffs_hes[i] < 0:
        hes_dir = "Metres better"
    else:
        hes_dir = "Tied"

    if diffs_us[i] > 0:
        us_dir = "Steps better"
    elif diffs_us[i] < 0:
        us_dir = "Metres better"
    else:
        us_dir = "Tied"

    q7_row = df_cmp[df_cmp["participant"] == p]
    q7_val = (str(q7_row["Q7_preference"].values[0])
              if len(q7_row) > 0 else "N/A")

    print(f"  {p:<14} {hes_dir:<18} {us_dir:<18} {q7_val:<16}")

all_converge_hes = (n_favour_steps == len(PARTICIPANTS))
all_converge_us = (n_favour_steps_us == len(PARTICIPANTS))
print(f"\n  Convergence: ", end="")
if all_converge_hes and all_converge_us:
    print(f"All three indicators (hesitation, usability, preference) "
          f"consistently favour Steps across all participants.")
else:
    print(f"Some indicators diverge — see discussion for possible "
          f"explanations.")
print()

# =====================================================================
# 12. Export per-participant condition-level summary CSV
# =====================================================================

summary_rows = []
for p in PARTICIPANTS:
    cal_step_vals = df_info[df_info["participant"] == p][
        "calibrated_step_length_m"]
    cal_step = (cal_step_vals.values[0]
                if len(cal_step_vals) > 0 else np.nan)

    for cond in CONDITIONS:
        sub = df[(df["participant"] == p) & (df["condition"] == cond)]
        q_row = df_q[(df_q["participant"] == p) &
                      (df_q["condition"] == cond)]

        q_scores = {}
        usability = np.nan
        if len(q_row) > 0:
            for col in LIKERT_COLS:
                q_scores[col] = float(q_row[col].values[0])
            usability = np.mean([q_scores[c] for c in LIKERT_COLS])

        summary_rows.append({
            "participant": p,
            "condition": cond,
            "calibrated_step_m": cal_step,
            "condition_order": CONDITION_ORDER[p]["label"],
            "n_trials": len(sub),
            "mean_hesitation": sub["hesitation_count"].mean(),
            "sd_hesitation": sub["hesitation_count"].std(ddof=1),
            **q_scores,
            "overall_usability": usability,
        })

df_summary = pd.DataFrame(summary_rows)
df_summary.to_csv(OUTPUT_DIR + "exp4_condition_summary.csv", index=False)
print("Saved: exp4_condition_summary.csv")

# =====================================================================
# 13. Done
# =====================================================================

plt.close("all")
print()
print("=" * 75)
print("Analysis complete.")
print("=" * 75)
