"""
Experiment 1: Object Detection Accuracy — Data Analysis

printed to console:
  - Table 1: Detection results summary by scenario
  - Table 2: Detection results by object category
  - Table 3: Deployment reliability assessment
  - Table 4: S7 qualitative observation summary
  - Table 5: Inter-rater reliability
  - Fisher's exact test result (best vs worst recall scenario)

saved as PNG:
  - Figure 1: Recall comparison by scenario (bar chart)
  - Figure 2: Precision / F1 comparison by scenario (grouped bar chart)
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from scipy.stats import fisher_exact

# =====================================================================
# 1. Load data
# =====================================================================

OUTPUT_DIR = "./"

df = pd.read_csv("exp1_frame_annotations.csv")
df_irr = pd.read_csv("exp1_inter_rater_annotations.csv")
df_s7 = pd.read_csv("exp1_s7_qualitative.csv")

# Strip any possible \r characters left from Windows line endings
for col in df.columns:
    if df[col].dtype == object:
        df[col] = df[col].str.strip()
for col in df_irr.columns:
    if df_irr[col].dtype == object:
        df_irr[col] = df_irr[col].str.strip()
for col in df_s7.columns:
    if df_s7[col].dtype == object:
        df_s7[col] = df_s7[col].str.strip()

# Scenario list in the experimental design order
SCENARIOS = ["S1", "S2", "S3", "S4", "S5", "S6"]

# Scenario labels used in charts
SCENARIO_LABELS = {
    "S1": "S1\nSingle/Close",
    "S2": "S2\nSingle/Far",
    "S3": "S3\nMultiple",
    "S4": "S4\nOcclusion",
    "S5": "S5\nWalking",
    "S6": "S6\nLow Light",
}

# =====================================================================
# 2. Helper function: compute metrics from TP/FP/FN counts
# =====================================================================

def compute_metrics(subset):
    """Compute TP, FP, FN, and derived metrics from a set of annotation rows."""
    tp = (subset["judgement"] == "TP").sum()
    fp = (subset["judgement"] == "FP").sum()
    fn = (subset["judgement"] == "FN").sum()

    precision = tp / (tp + fp) if (tp + fp) > 0 else np.nan
    recall = tp / (tp + fn) if (tp + fn) > 0 else np.nan
    f1 = (2 * precision * recall / (precision + recall)
          if precision and recall and (precision + recall) > 0
          else np.nan)

    # Label accuracy: number of TP rows with correct labels divided by total TP rows
    tp_rows = subset[subset["judgement"] == "TP"]
    label_acc = ((tp_rows["label_correct"] == "yes").sum() / len(tp_rows)
                 if len(tp_rows) > 0 else np.nan)

    return {
        "TP": int(tp),
        "FP": int(fp),
        "FN": int(fn),
        "Precision": precision,
        "Recall": recall,
        "F1": f1,
        "Label Acc": label_acc,
    }

# =====================================================================
# 3. Table 1: detection result summary for each scenario
# =====================================================================

print("=" * 95)
print("Table 1: Detection Results Summary by Scenario")
print("=" * 95)

table1_rows = []
for s in SCENARIOS:
    row = compute_metrics(df[df["scenario"] == s])
    row["Scenario"] = s
    table1_rows.append(row)

# Overall row combining S1–S6
overall = compute_metrics(df)
overall["Scenario"] = "Overall"
table1_rows.append(overall)

table1 = pd.DataFrame(table1_rows)
col_order = ["Scenario", "TP", "FP", "FN", "Precision", "Recall", "F1", "Label Acc"]
table1 = table1[col_order]

print(table1.to_string(index=False, float_format="{:.4f}".format))
print()

# =====================================================================
# 4. Figure 1: recall comparison bar chart for each scenario
# =====================================================================

plt.rcParams.update({
    "figure.dpi": 150,
    "font.size": 11,
    "axes.titlesize": 13,
    "axes.labelsize": 12,
})

recalls = [table1[table1["Scenario"] == s]["Recall"].values[0] for s in SCENARIOS]
x_pos = np.arange(len(SCENARIOS))

fig1, ax1 = plt.subplots(figsize=(8, 5))
bars = ax1.bar(
    x_pos, recalls,
    color="#42A5F5", edgecolor="#1565C0", linewidth=1,
)

# Annotate values above each bar
for i, v in enumerate(recalls):
    ax1.text(i, v + 0.01, f"{v:.2f}", ha="center", va="bottom", fontsize=10)

# Reference baseline for navigation reliability at y = 0.80
ax1.axhline(y=0.80, color="#D32F2F", linestyle="--", linewidth=1.2,
            label="Deployment threshold (recall = 0.80)")

ax1.set_xticks(x_pos)
ax1.set_xticklabels([SCENARIO_LABELS[s] for s in SCENARIOS], fontsize=9)
ax1.set_xlabel("Scenario")
ax1.set_ylabel("Recall")
ax1.set_title("Figure 1: Recall Comparison by Scenario")
ax1.set_ylim(0, 1.12)
ax1.legend(loc="lower right", fontsize=9)
ax1.grid(True, axis="y", alpha=0.3)

fig1.tight_layout()
fig1.savefig(OUTPUT_DIR + "figure1_recall_by_scenario.png")
print("Saved: figure1_recall_by_scenario.png")

# =====================================================================
# 5. Figure 2: precision / F1 comparison bar chart for each scenario
# =====================================================================

precisions = [table1[table1["Scenario"] == s]["Precision"].values[0] for s in SCENARIOS]
f1s = [table1[table1["Scenario"] == s]["F1"].values[0] for s in SCENARIOS]

fig2, ax2 = plt.subplots(figsize=(8, 5))
width = 0.35
ax2.bar(x_pos - width / 2, precisions, width,
        color="#66BB6A", edgecolor="#2E7D32", linewidth=1, label="Precision")
ax2.bar(x_pos + width / 2, f1s, width,
        color="#FFA726", edgecolor="#E65100", linewidth=1, label="F1")

# Value annotations
for i in range(len(SCENARIOS)):
    ax2.text(i - width / 2, precisions[i] + 0.01,
             f"{precisions[i]:.2f}", ha="center", va="bottom", fontsize=9)
    ax2.text(i + width / 2, f1s[i] + 0.01,
             f"{f1s[i]:.2f}", ha="center", va="bottom", fontsize=9)

ax2.set_xticks(x_pos)
ax2.set_xticklabels([SCENARIO_LABELS[s] for s in SCENARIOS], fontsize=9)
ax2.set_xlabel("Scenario")
ax2.set_ylabel("Score")
ax2.set_title("Figure 2: Precision and F1 by Scenario")
ax2.set_ylim(0, 1.15)
ax2.legend(loc="lower right", fontsize=9)
ax2.grid(True, axis="y", alpha=0.3)

fig2.tight_layout()
fig2.savefig(OUTPUT_DIR + "figure2_precision_f1_by_scenario.png")
print("Saved: figure2_precision_f1_by_scenario.png")

# =====================================================================
# 6. Table 2: detection results by object category
# =====================================================================

print()
print("=" * 95)
print("Table 2: Detection Results by Object Category")
print("=" * 95)

# Identify all ground-truth object categories that appear, excluding "none" for FP rows
categories = sorted(
    df[df["ground_truth_object"] != "none"]["ground_truth_object"].unique()
)

table2_rows = []
for cat in categories:
    # All rows for this category: rows whose ground_truth_object is this category, either TP or FN
    # Plus FP rows misdetected as this category, where app_label is this category and ground_truth is none
    gt_rows = df[df["ground_truth_object"] == cat]
    fp_rows = df[(df["judgement"] == "FP") & (df["app_label"] == cat)]

    tp = (gt_rows["judgement"] == "TP").sum()
    fn = (gt_rows["judgement"] == "FN").sum()
    fp = len(fp_rows)

    precision = tp / (tp + fp) if (tp + fp) > 0 else np.nan
    recall = tp / (tp + fn) if (tp + fn) > 0 else np.nan
    f1 = (2 * precision * recall / (precision + recall)
          if precision and recall and (precision + recall) > 0
          else np.nan)

    # Label accuracy
    tp_rows_cat = gt_rows[gt_rows["judgement"] == "TP"]
    label_acc = ((tp_rows_cat["label_correct"] == "yes").sum() / len(tp_rows_cat)
                 if len(tp_rows_cat) > 0 else np.nan)

    table2_rows.append({
        "Category": cat,
        "TP": int(tp),
        "FP": int(fp),
        "FN": int(fn),
        "Precision": precision,
        "Recall": recall,
        "F1": f1,
        "Label Acc": label_acc,
    })

# Overall row
total_tp = sum(r["TP"] for r in table2_rows)
total_fp = sum(r["FP"] for r in table2_rows)
total_fn = sum(r["FN"] for r in table2_rows)
total_prec = total_tp / (total_tp + total_fp) if (total_tp + total_fp) > 0 else np.nan
total_rec = total_tp / (total_tp + total_fn) if (total_tp + total_fn) > 0 else np.nan
total_f1 = (2 * total_prec * total_rec / (total_prec + total_rec)
            if total_prec and total_rec and (total_prec + total_rec) > 0
            else np.nan)
tp_all = df[df["judgement"] == "TP"]
total_label_acc = ((tp_all["label_correct"] == "yes").sum() / len(tp_all)
                   if len(tp_all) > 0 else np.nan)
table2_rows.append({
    "Category": "Overall",
    "TP": int(total_tp), "FP": int(total_fp), "FN": int(total_fn),
    "Precision": total_prec, "Recall": total_rec, "F1": total_f1,
    "Label Acc": total_label_acc,
})

table2 = pd.DataFrame(table2_rows)
print(table2.to_string(index=False, float_format="{:.4f}".format))
print()

# =====================================================================
# 7. Table 3: deployment reliability assessment
# =====================================================================

print("=" * 95)
print("Table 3: Deployment Reliability Assessment")
print("=" * 95)

overall_recall = overall["Recall"]
overall_precision = overall["Precision"]

# Find the scenario with the lowest recall
scenario_recalls = {s: table1[table1["Scenario"] == s]["Recall"].values[0]
                    for s in SCENARIOS}
worst_scenario = min(scenario_recalls, key=scenario_recalls.get)
worst_recall = scenario_recalls[worst_scenario]

criteria = [
    ("Overall Recall",      ">= 0.80", f"{overall_recall:.4f}",
     "PASS" if overall_recall >= 0.80 else "FAIL"),
    ("Overall Precision",   ">= 0.70", f"{overall_precision:.4f}",
     "PASS" if overall_precision >= 0.70 else "FAIL"),
    (f"Min Scenario Recall ({worst_scenario})", ">= 0.60",
     f"{worst_recall:.4f}",
     "PASS" if worst_recall >= 0.60 else "FAIL"),
]

print(f"  {'Metric':<35} {'Threshold':>12} {'Measured':>12} {'Result':>8}")
print("  " + "-" * 70)
for name, thresh, measured, result in criteria:
    print(f"  {name:<35} {thresh:>12} {measured:>12} {result:>8}")
print()

# =====================================================================
# 8. Table 4: S7 qualitative scenario observation
# =====================================================================

print("=" * 95)
print("Table 4: S7 Qualitative Scenario Observation (Door)")
print("=" * 95)

total_s7 = len(df_s7)
detected_s7 = (df_s7["any_detection"] == "yes").sum()
not_detected_s7 = (df_s7["any_detection"] == "no").sum()

print(f"  Total frames sampled:  {total_s7}")
print(f"  Frames with detection: {detected_s7}")
print(f"  Frames without:        {not_detected_s7}")

# If any frames have detections, display the reported labels
if detected_s7 > 0:
    labels = df_s7[df_s7["any_detection"] == "yes"]["app_label_if_detected"].value_counts()
    print(f"  Labels reported:       {dict(labels)}")
else:
    print("  Labels reported:       (none — YOLO produced no response)")

# Print the observation from the first row as the representative example
sample_obs = df_s7.iloc[0]["observation"]
print(f"  Observation:           {sample_obs}")
print()

# =====================================================================
# 9. Table 5：Inter-rater Reliability
# =====================================================================

print("=" * 95)
print("Table 5: Inter-rater Reliability")
print("=" * 95)

# Extract the S3 + S4 subset from the primary annotation data
df_primary_subset = df[df["scenario"].isin(["S3", "S4"])].copy()
df_primary_subset = df_primary_subset.sort_values(
    ["scenario", "frame_id", "ground_truth_object"]
).reset_index(drop=True)

df_second = df_irr.sort_values(
    ["scenario", "frame_id", "ground_truth_object"]
).reset_index(drop=True)

# Build the matching key
merge_key = ["scenario", "frame_id", "ground_truth_object"]
merged = pd.merge(
    df_primary_subset, df_second,
    on=merge_key, suffixes=("_pri", "_sec"),
    how="outer",  # Use outer join to capture any unmatched rows
)

total_frames_irr = df_second.groupby(["scenario", "frame_id"]).ngroups
total_judgements = len(merged)

# Judgement agreement: judgement values are the same
judgement_agree = (merged["judgement_pri"] == merged["judgement_sec"]).sum()
judgement_pct = judgement_agree / total_judgements * 100 if total_judgements > 0 else 0

# Label agreement, compared only when both annotators marked the row as TP
both_tp = merged[
    (merged["judgement_pri"] == "TP") & (merged["judgement_sec"] == "TP")
]
label_agree = (both_tp["label_correct_pri"] == both_tp["label_correct_sec"]).sum()
label_pct = label_agree / len(both_tp) * 100 if len(both_tp) > 0 else 0

print(f"  Scenarios cross-annotated:    S3 + S4")
print(f"  Total frames:                 {total_frames_irr}")
print(f"  Total judgements compared:    {total_judgements}")
print(f"  Judgement agreements:         {judgement_agree} / {total_judgements} "
      f"({judgement_pct:.1f}%)")
print(f"  Label-correct agreements:     {label_agree} / {len(both_tp)} "
      f"({label_pct:.1f}%)  [among TP pairs only]")
print()

if judgement_pct >= 90:
    print("  → Agreement >= 90%: annotation reliability is GOOD.")
else:
    print("  → Agreement < 90%: annotation reliability requires further discussion.")

# Report disagreement cases
disagree_rows = merged[merged["judgement_pri"] != merged["judgement_sec"]]
if len(disagree_rows) > 0:
    print(f"\n  Disagreement cases ({len(disagree_rows)}):")
    for _, row in disagree_rows.iterrows():
        print(f"    {row['scenario']} frame {row['frame_id']} "
              f"[{row['ground_truth_object']}]: "
              f"primary={row['judgement_pri']}, second={row['judgement_sec']}")
else:
    print("  No disagreements in judgement.")

# Label disagreements
label_disagree = both_tp[both_tp["label_correct_pri"] != both_tp["label_correct_sec"]]
if len(label_disagree) > 0:
    print(f"\n  Label-correct disagreements ({len(label_disagree)}):")
    for _, row in label_disagree.iterrows():
        print(f"    {row['scenario']} frame {row['frame_id']} "
              f"[{row['ground_truth_object']}]: "
              f"primary={row['label_correct_pri']}, "
              f"second={row['label_correct_sec']}")
print()

# =====================================================================
# 10. Label error details
# =====================================================================

print("=" * 95)
print("Label Error Details")
print("=" * 95)

label_errors = df[(df["judgement"] == "TP") & (df["label_correct"] == "no")]
if len(label_errors) > 0:
    for _, row in label_errors.iterrows():
        print(f"  {row['scenario']} frame {row['frame_id']}: "
              f"ground truth = {row['ground_truth_object']}, "
              f"app label = {row['app_label']}"
              + (f"  ({row['notes']})" if pd.notna(row.get('notes'))
                 and str(row.get('notes', '')).strip() else ""))
else:
    print("  No label errors found.")
print()

# =====================================================================
# 11. Fisher's exact test: recall difference between the best and worst scenarios
# =====================================================================

print("=" * 95)
print("Statistical Test: Fisher's Exact Test (Best vs Worst Recall Scenario)")
print("=" * 95)

# TP and FN counts for each scenario, where FN means the ground-truth object was not detected
scenario_counts = {}
for s in SCENARIOS:
    sub = df[df["scenario"] == s]
    # Count only ground-truth objects, excluding "none" values from FP rows
    gt_sub = sub[sub["ground_truth_object"] != "none"]
    tp = (gt_sub["judgement"] == "TP").sum()
    fn = (gt_sub["judgement"] == "FN").sum()
    total = tp + fn
    recall = tp / total if total > 0 else np.nan
    scenario_counts[s] = {"TP": tp, "FN": fn, "Recall": recall}

# Find the best and worst scenarios
best_s = max(scenario_counts, key=lambda s: scenario_counts[s]["Recall"])
worst_s = min(scenario_counts, key=lambda s: scenario_counts[s]["Recall"])

best = scenario_counts[best_s]
worst = scenario_counts[worst_s]

print(f"  Best scenario:  {best_s} (recall = {best['Recall']:.4f}, "
      f"TP = {best['TP']}, FN = {best['FN']})")
print(f"  Worst scenario: {worst_s} (recall = {worst['Recall']:.4f}, "
      f"TP = {worst['TP']}, FN = {worst['FN']})")
print()

# Handle the special case where the best and worst recall are identical, such as all values being 1.0
if best["Recall"] == worst["Recall"]:
    print("  Best and worst scenario have identical recall.")
    print("  Fisher's exact test is not applicable — no variation to test.")
    print("  All scenarios achieved the same detection rate.")
else:
    # Build the 2×2 contingency table
    contingency = [
        [best["TP"], best["FN"]],
        [worst["TP"], worst["FN"]],
    ]
    print(f"  Contingency table:")
    print(f"              TP    FN")
    print(f"    {best_s:>5}   {best['TP']:>4}  {best['FN']:>4}")
    print(f"    {worst_s:>5}   {worst['TP']:>4}  {worst['FN']:>4}")
    print()

    odds_ratio, p_value = fisher_exact(contingency, alternative="two-sided")

    print(f"  H0: No difference in detection success rate between {best_s} and {worst_s}")
    print(f"  H1: Detection success rate differs between the two scenarios")
    print(f"  Odds ratio = {odds_ratio:.4f}")
    print(f"  p-value    = {p_value:.6f}")
    print()

    if p_value < 0.05:
        print(f"  → Reject H0 at alpha = 0.05: scenario conditions significantly "
              f"affect detection reliability.")
    else:
        print(f"  → Fail to reject H0: no statistically significant difference "
              f"in recall between {best_s} and {worst_s}.")
        print(f"    Given the moderate sample size (20 frames per scenario), "
              f"absence of significance")
        print(f"    should be interpreted with caution — it may reflect "
              f"insufficient statistical power")
        print(f"    rather than true equivalence.")
print()

# =====================================================================
# 12. Supplementary: detection results for the S5 walking scenario by distance range
# =====================================================================

print("=" * 95)
print("Supplementary: S5 Walking Scenario — Detection by Distance Range")
print("=" * 95)

s5 = df[df["scenario"] == "S5"]
if "distance_range" in s5.columns and s5["distance_range"].notna().any():
    ranges = ["far", "mid", "near"]
    for r in ranges:
        sub = s5[s5["distance_range"] == r]
        if len(sub) == 0:
            continue
        tp = (sub["judgement"] == "TP").sum()
        fn = (sub["judgement"] == "FN").sum()
        total = tp + fn
        recall = tp / total if total > 0 else np.nan
        print(f"  {r:>5}: {tp} TP, {fn} FN  (recall = {recall:.2f}, n = {total})")
else:
    print("  No distance_range data available for S5.")
print()

# =====================================================================
# 13. Summary output
# =====================================================================

plt.close("all")
print("=" * 95)
print("Analysis complete.")
print("=" * 95)
