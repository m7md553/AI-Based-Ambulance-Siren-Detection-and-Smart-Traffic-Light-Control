
import sys
import time

sys.path.append(r"C:\Program Files (x86)\SUMO\tools")
import traci

sumo_gui = r"C:\Program Files (x86)\SUMO\bin\sumo-gui.exe"
config = r"D:\sim\simulation.sumocfg"
cmd_file = r"D:\sim\tls_cmd.txt"

TLS_ID = "center"

# Signal groups: 16
# Straight movements only:
# North-South: indices 1, 2, 9, 10
# East-West:   indices 5, 6, 13, 14

NS_GREEN = "rGGrrrrrrGGrrrrr"
EW_GREEN = "rrrrrGGrrrrrrGGr"

# Yellow for the same movements that were green
NS_YELLOW = "rYYrrrrrrYYrrrrr"
EW_YELLOW = "rrrrrYYrrrrrrYYr"

ALL_RED = "rrrrrrrrrrrrrrrr"

GREEN_TIME = 15.0
YELLOW_TIME = 3.0
ALL_RED_TIME = 1.0

def read_command():
    try:
        with open(cmd_file, "r") as f:
            return f.read().strip().upper()
    except OSError:
        return "R"

def set_state(state):
    if len(state) != 16:
        raise ValueError(
            f"Invalid signal state length: {len(state)}"
        )
    traci.trafficlight.setRedYellowGreenState(TLS_ID, state)
    print(f"Traffic light state: {state}")

traci.start([sumo_gui, "-c", config, "--start"])
print("SUMO Bridge Running")

try:
    tls_ids = traci.trafficlight.getIDList()
    if TLS_ID not in tls_ids:
        raise RuntimeError(f"Traffic light '{TLS_ID}' not found")

    current_mode = "R"
    phase = 0
    phase_start = traci.simulation.getTime()

    set_state(NS_GREEN)

    while traci.simulation.getMinExpectedNumber() > 0:
        command = read_command()
        sim_time = traci.simulation.getTime()

        # Emergency mode: keep NS green while command is G.
        # This is a temporary fixed-direction test.
        if command == "G":
            if current_mode != "G":
                set_state(ALL_RED)
                current_mode = "G"
                phase_start = sim_time
            elif sim_time - phase_start >= ALL_RED_TIME:
                set_state(NS_GREEN)
        else:
            if current_mode == "G":
                set_state(NS_YELLOW)
                current_mode = "Y"
                phase_start = sim_time

            elif current_mode == "Y":
                if sim_time - phase_start >= YELLOW_TIME:
                    set_state(ALL_RED)
                    current_mode = "R"
                    phase_start = sim_time

            elif current_mode == "R":
                if sim_time - phase_start >= ALL_RED_TIME:
                    phase = 1 - phase
                    set_state(NS_GREEN if phase == 0 else EW_GREEN)
                    current_mode = "N" if phase == 0 else "E"
                    phase_start = sim_time

            elif current_mode in ("N", "E"):
                if sim_time - phase_start >= GREEN_TIME:
                    set_state(NS_YELLOW if current_mode == "N"
                              else EW_YELLOW)
                    current_mode = "Y"
                    phase_start = sim_time

        traci.simulationStep()
        time.sleep(0.05)

except (traci.TraCIException, RuntimeError, ValueError) as e:
    print("Bridge error:", repr(e))

finally:
    if traci.isLoaded():
        traci.close()
    print("SUMO Bridge stopped")
