import sys
sys.path.append(r"C:\Program Files (x86)\SUMO\tools")
import traci
gui = r"C:\Program Files (x86)\SUMO\bin\sumo-gui.exe"
cfg = r"D:\sim\simulation.sumocfg"
traci.start([gui, "-c", cfg, "--start"])
links = traci.trafficlight.getControlledLinks("center")
for i, group in enumerate(links):
    print(i, group)
traci.close()
