## Requirements & Setup

To run the project correctly, make sure you have the following installed and configured:

1. **MATLAB R2024 or newer.**
2. **SUMO (Simulation of Urban Mobility)** installed on your computer.
3. **SUMO Traffic Network:** Make sure the SUMO network and traffic configuration files are properly configured and ready to run.

### Path Configuration

Before running the project, you must update the file paths in the source code to match your own computer:

- **`startSumoBridge.m`:** Update the `projectDir` path to your project folder.
- **`updateSumoStep.m`:** Update the `cmdFile` path to the location of `tls_cmd.txt`.
- **AI Model:** Make sure the path to the trained AI model is correctly configured in the MATLAB code.
- - **`detectSirenStep.m`:** Update the path to the trained AI model inside the siren detection script (`detectSirenStep.m`) to match the model's location on your computer.
- **Python & SUMO:** Make sure the Python executable path and SUMO installation paths are correct in the bridge script.

The paths currently used in the code are specific to my computer and may need to be modified.

### Important

Make sure SUMO, its tools (including TraCI), and the traffic network are correctly installed and configured before running the simulation.
