# GaitNav

iPhone-based near-field obstacle warning system for visually impaired users.

GaitNav uses YOLOv8s object detection, LiDAR distance estimation, and adaptive gait sensing to convert obstacle distances into personalised step-count feedback.

## Requirements

- iPhone with LiDAR, such as iPhone 12 Pro or later
- iOS 16+
- Xcode 15+

## Project Structure

```text
GaitNav/
|-- GaitNav/
|   |-- App/                 
|   |-- Core/                # Perception, gait, and feedback coordinators
|   |-- Perception/          # Object detection, distance estimation, and tracking
|   |-- Gait/                # Step detection, profiling, calibration, and step length
|   |-- Feedback/            # Speech feedback, countdown, and feedback policies
|   |-- UI/                  # Camera preview, overlays, settings, and setup screens
|   |-- Design/              
|   `-- Resources/           # App assets and YOLOv8s CoreML model
|-- Evaluation/              # Experiment data and analysis scripts
|   |-- ObjectDetectionAccuracy/
|   |-- DistanceEstimationAccuracy/
|   |-- NavigationStoppingAccuracy/
|   |-- FeedbackModeComparison/
|   `-- RealTimePerformance/
|-- GaitNav.xcodeproj/
`-- README.md
```

## Evaluation

The `Evaluation/` folder contains the raw data and analysis scripts used for the project evaluation. The files are organised by experiment, so each experiment folder contains both its raw data and the script needed to analyse it.

| Folder | Experiment | Report Section |
|--------|------------|----------------|
| `ObjectDetectionAccuracy/` | Object detection accuracy | 5.2 |
| `DistanceEstimationAccuracy/` | Distance estimation accuracy | 5.3 |
| `NavigationStoppingAccuracy/` | Navigation stopping accuracy | 5.4 |
| `FeedbackModeComparison/` | Feedback mode comparison | 5.5 |
| `RealTimePerformance/` | Real-time performance and speech latency | 5.6 |

The scripts use standard Python data analysis libraries:

- `pandas`
- `numpy`
- `matplotlib`
- `scipy`

Install them if needed:

```bash
pip install pandas numpy matplotlib scipy
```

Run each script from its own experiment folder. For example:

```bash
cd Evaluation/ObjectDetectionAccuracy
python3 analyse_object_detection.py
```

Each script assumes that its input CSV files are located in the same folder as the script.
