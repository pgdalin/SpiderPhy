# SpiderPhy (OSF link: https://osf.io/98cnd/overview)


<img width="616" height="462" alt="image" src="https://github.com/user-attachments/assets/8e1731fd-ca94-48a7-8955-267bc75e0fa5" />


I would like to thank the original authors of the SpiderPhy project for making their dataset available under Open Science principles: Cindy Lor, David Steyrl, Alexander Karner, Sebastian Götzenderfer, Anne Klimesch, Stephanie J. Eder, Fabian Renz, Johannes Rother, Filip Melinscak & Frank Scharnowski.

# What's SpiderPhy?

The SpiderPhy project investigates how distress manifests across different biological channels during exposure therapy-like conditions. Subjects were exposed to 174 spider-related images and 16 neutral stimuli. This pipeline processes:

- Cardiac Activity (ECG): Heart rate (BPM) and Heart Rate Variability (RMSSD).
- Oculometry: Gaze position (heatmaps) and pupil dilation speed.
- Electrodermal Activity (EDA/GSR): Phasic skin conductance responses.
- Psychometrics: Standardized phobia scales (FSQ, SAS, SPQ, STAI).

# What does this repository do ?

This repository implements a comprehensive end-to-end analysis pipeline for the SpiderPhy study, a multimodal dataset exploring physiological, psychometric, and behavioral responses to fear-inducing stimuli in N = 54 subclinical spider-fearful individuals.

# The scripts

## Python 

Located in the /Python directory, these scripts handle raw .mat LSL data:
- physio_processing.py: Extracts summary statistics using NeuroKit2.
- gaze_extraction.py: Performs drift correction by anchoring gaze to fixation crosses.
- heatmaps_generation.py: Generates spatial density overlays (heatmaps) on top of the original stimuli.

## R

Located in the /R directory, focusing on analytics:
- merge2.R: Consolidates physiological features, psychometric scores, and trial-level ratings.
- psychometrics.R: Assesses internal reliability (Cronbach’s alpha) and convergent validity.
- lmm2.R: Fits Linear Mixed-Effects Models (LMM) to test interactions between subjective fear and physiological reactivity.

# Why?

As a recent Master’s graduate in Applied Cognitive Psychology (University of Paris Cité), I developed this project to bridge the gap between psychological theory and data science. My focus is on:

- Pipeline Automation: Building robust workflows for noisy biological data.
- Statistics: Applying LMMs to capture the complexity of human behavior.
- Open Science: Promoting reproducible research through well-documented code.

# How to reach me?

pablo.dalin@gmail.com

