
import sys
import time
import random

sys.path.append(r"C:\Program Files (x86)\SUMO\tools")
import traci


# =========================================================
# CONFIGURATION
# =========================================================

SUMO_GUI = r"C:\Program Files (x86)\SUMO\bin\sumo-gui.exe"
CONFIG = r"D:\sim\simulation.sumocfg"
CMD_FILE = r"D:\sim\tls_cmd.txt"

TLS_ID = "center"

AMB_INTERVAL = 38.0

GREEN_TIME = 15.0
YELLOW_TIME = 5.0
RED_YELLOW_TIME = 1.5
ALL_RED_TIME = 1.0

CLEARING_DISTANCE = 35.0
LANE_CHANGE_DURATION = 5.0
LANE_CHANGE_COOLDOWN = 4.0

# =========================================================
# TRAFFIC LIGHT STATES: 16 CONTROLLED LINKS
# =========================================================

NS_GREEN = "GGGgrrrrGGGgrrrr"
NS_YELLOW = "yyyyrrrryyyyrrrr"
NS_RED_YELLOW = "uuuurrrruuuurrrr"

EW_GREEN = "rrrrGGGgrrrrGGGg"
EW_YELLOW = "rrrryyyyrrrryyyy"
EW_RED_YELLOW = "rrrruuuurrrruuuu"

ALL_RED = "rrrrrrrrrrrrrrrr"

# Start with NS red-yellow, then green.
# The cycle alternates NS and EW with an all-red clearance.
NORMAL_STAGES = [
    (NS_RED_YELLOW, RED_YELLOW_TIME),
    (NS_GREEN, GREEN_TIME),
    (NS_YELLOW, YELLOW_TIME),
    (ALL_RED, ALL_RED_TIME),

    (EW_RED_YELLOW, RED_YELLOW_TIME),
    (EW_GREEN, GREEN_TIME),
    (EW_YELLOW, YELLOW_TIME),
    (ALL_RED, ALL_RED_TIME),
]

# Validate all normal signal states before starting SUMO.
for state, duration in NORMAL_STAGES:
    if len(state) != 16:
        raise ValueError(
            f"Invalid signal length: {state}, length={len(state)}"
        )
    if duration <= 0:
        raise ValueError("Stage durations must be positive.")


# =========================================================
# AMBULANCE ROUTES AND LANES
# =========================================================

AMB_ROUTES = [
    "amb_s_straight", "amb_s_left", "amb_s_right",
    "amb_n_straight", "amb_n_left", "amb_n_right",
    "amb_w_straight", "amb_w_left", "amb_w_right",
    "amb_e_straight", "amb_e_left", "amb_e_right",
]

AMBULANCE_LANES = {
    "amb_s_straight": 0,
    "amb_s_left": 1,
    "amb_s_right": 0,

    "amb_n_straight": 0,
    "amb_n_left": 1,
    "amb_n_right": 0,

    "amb_w_straight": 0,
    "amb_w_left": 1,
    "amb_w_right": 0,

    "amb_e_straight": 0,
    "amb_e_left": 1,
    "amb_e_right": 0,
}

INCOMING_EDGES = {"s_in", "n_in", "e_in", "w_in"}

last_yield_request = {}


# =========================================================
# READ MATLAB COMMAND
# G = siren detected
# R = no siren
# =========================================================

def read_command():
    try:
        with open(CMD_FILE, "r") as f:
            command = f.read().strip().upper()

        return command if command in ("G", "R") else "R"

    except OSError:
        return "R"


# =========================================================
# TRAFFIC LIGHT CONTROL
# =========================================================

def set_state(state):
    if len(state) != 16:
        raise ValueError(
            f"Expected 16 signal characters, got {len(state)}"
        )

    traci.trafficlight.setRedYellowGreenState(TLS_ID, state)


def to_yellow(state):
    # Change active green signals to yellow.
    return "".join(
        "y" if char in ("G", "g") else char
        for char in state
    )


# =========================================================
# AMBULANCE MANAGEMENT
# =========================================================

def get_active_ambulances():
    return sorted(
        vid for vid in traci.vehicle.getIDList()
        if vid.startswith("amb_live_")
    )


def spawn_ambulance(serial):
    direction = random.choice(["s", "n", "w", "e"])

    turn = random.choices(
        ["straight", "left", "right"],
        weights=[60, 20, 20],
        k=1
    )[0]

    route_id = f"amb_{direction}_{turn}"

    # كمّل باقي كود spawn_ambulance الأصلي هنا
    vehicle_id = f"amb_live_{serial}"
    lane_index = AMBULANCE_LANES[route_id]

    try:
        traci.vehicle.add(
            vehID=vehicle_id,
            routeID=route_id,
            typeID="amb",
            depart="now",
            departLane=str(lane_index),
            departSpeed="max"
        )

        print(
            f"[AMBULANCE] id={vehicle_id}, "
            f"route={route_id}, lane={lane_index}"
        )

        return True

    except traci.TraCIException as error:
        print("[AMBULANCE ERROR]", repr(error))
        return False


# =========================================================
# EMERGENCY ROAD CLEARING
# =========================================================

def clear_path_for_ambulance(ambulance_id, sim_time):
    try:
        amb_road = traci.vehicle.getRoadID(ambulance_id)

        if amb_road not in INCOMING_EDGES:
            return

        leader = traci.vehicle.getLeader(
            ambulance_id,
            CLEARING_DISTANCE
        )

        if not leader:
            return

        car_id, gap = leader

        if not car_id or gap > CLEARING_DISTANCE:
            return

        amb_lane = traci.vehicle.getLaneID(ambulance_id)
        car_lane = traci.vehicle.getLaneID(car_id)
        car_road = traci.vehicle.getRoadID(car_id)

        # Only consider a vehicle in the same lane and approach.
        if amb_lane != car_lane or car_road != amb_road:
            return

        if car_road.startswith(":"):
            return

        last_time = last_yield_request.get(car_id, -999)

        if sim_time - last_time < LANE_CHANGE_COOLDOWN:
            return

        current_index = traci.vehicle.getLaneIndex(car_id)
        car_position = traci.vehicle.getLanePosition(car_id)

        best_lanes = traci.vehicle.getBestLanes(car_id)
        candidates = []

        for lane_info in best_lanes:
            lane_id = lane_info[0]
            allows_continuation = lane_info[4]

            if not allows_continuation:
                continue

            if traci.lane.getEdgeID(lane_id) != car_road:
                continue

            target_index = int(lane_id.rsplit("_", 1)[-1])

            # Only adjacent lanes are considered.
            if abs(target_index - current_index) != 1:
                continue

            occupied_nearby = False

            for other_id in traci.lane.getLastStepVehicleIDs(lane_id):
                if other_id == car_id:
                    continue

                try:
                    other_pos = traci.vehicle.getLanePosition(other_id)

                    if abs(other_pos - car_position) < 12.0:
                        occupied_nearby = True
                        break

                except traci.TraCIException:
                    continue

            if not occupied_nearby:
                candidates.append(target_index)

        if not candidates:
            print(
                f"[NO SAFE LANE] car={car_id}, "
                f"ambulance={ambulance_id}, gap={gap:.1f}m"
            )
            return

        def nearby_traffic(lane_index):
            count = 0
            lane_id = f"{car_road}_{lane_index}"

            for other_id in traci.lane.getLastStepVehicleIDs(lane_id):
                if other_id == car_id:
                    continue

                try:
                    other_pos = traci.vehicle.getLanePosition(other_id)

                    if abs(other_pos - car_position) < 25.0:
                        count += 1

                except traci.TraCIException:
                    continue

            return count

        candidates.sort(key=nearby_traffic)
        target_index = candidates[0]

        traci.vehicle.changeLane(
            car_id,
            target_index,
            LANE_CHANGE_DURATION
        )

        last_yield_request[car_id] = sim_time

        print(
            f"[YIELD REQUEST] car={car_id}, "
            f"from_lane={current_index}, "
            f"to_lane={target_index}, gap={gap:.1f}m"
        )

    except traci.TraCIException as error:
        print("[CLEARING ERROR]", repr(error))


# =========================================================
# FIND SIGNALS FOR THE AMBULANCE APPROACH
# =========================================================

def get_ambulance_signal_state(vehicle_id):
    route = traci.vehicle.getRoute(vehicle_id)
    route_index = traci.vehicle.getRouteIndex(vehicle_id)

    if route_index < 0 or route_index + 1 >= len(route):
        return None

    current_edge = route[route_index]

    if current_edge not in INCOMING_EDGES:
        return None

    controlled_links = traci.trafficlight.getControlledLinks(TLS_ID)

    state = ["r"] * len(controlled_links)
    found = False

    # Give green to movements originating from the ambulance's
    # approach. This also allows queued vehicles on that approach.
    for index, group in enumerate(controlled_links):
        for link in group:
            from_lane, to_lane, _ = link
            from_edge = from_lane.rsplit("_", 1)[0]

            if from_edge == current_edge:
                state[index] = "G"
                found = True
                break

    if not found:
        print(
            f"[WARNING] No signal links for "
            f"vehicle={vehicle_id}, edge={current_edge}"
        )
        return None

    return "".join(state)


# =========================================================
# MAIN SIMULATION
# =========================================================

def main():
    random.seed()

    try:
        traci.start([
            SUMO_GUI,
            "-c", CONFIG,
            "--start"
        ])

        print("[BRIDGE] SUMO Bridge Running")

        if TLS_ID not in traci.trafficlight.getIDList():
            raise RuntimeError(
                f"Traffic light '{TLS_ID}' not found"
            )

        available_routes = set(traci.route.getIDList())
        missing_routes = set(AMB_ROUTES) - available_routes

        if missing_routes:
            raise RuntimeError(
                "Missing ambulance routes: "
                + ", ".join(sorted(missing_routes))
            )

        if len(traci.trafficlight.getControlledLinks(TLS_ID)) != 16:
            raise RuntimeError(
                "Expected exactly 16 controlled links"
            )

        sim_time = traci.simulation.getTime()

        # Begin with NS red-yellow, then NS green.
        stage_index = 0
        stage_start = sim_time

        set_state(NORMAL_STAGES[stage_index][0])

        next_ambulance_time = sim_time
        ambulance_serial = 0

        emergency_active = False
        emergency_state = None
        emergency_road = None

        transition = None
        transition_start = sim_time

        last_command = None
        last_diagnostic_time = -1.0

        while traci.simulation.getMinExpectedNumber() > 0:

            sim_time = traci.simulation.getTime()
            command = read_command()

            if command != last_command:
                print(
                    f"[COMMAND] t={sim_time:.1f}s, "
                    f"command={command}"
                )
                last_command = command

            active_ambulances = get_active_ambulances()

            # Spawn one ambulance at a time.
            if (
                not active_ambulances
                and sim_time >= next_ambulance_time
            ):
                ambulance_serial += 1

                if spawn_ambulance(ambulance_serial):
                    next_ambulance_time = (
                        sim_time + AMB_INTERVAL
                    )
                else:
                    next_ambulance_time = sim_time + 1.0

            active_ambulances = get_active_ambulances()

            ambulance_id = (
                active_ambulances[0]
                if active_ambulances else None
            )

            desired_state = None

            # ---------------------------------------------
            # EMERGENCY PRIORITY
            # ---------------------------------------------

            if ambulance_id is not None:
                ambulance_road = traci.vehicle.getRoadID(
                    ambulance_id
                )

                # Request yielding only while siren is active.
                if command == "G":
                    clear_path_for_ambulance(
                        ambulance_id,
                        sim_time
                    )

                    # Latch the approach while siren is active.
                    if ambulance_road in INCOMING_EDGES:
                        candidate_state = (
                            get_ambulance_signal_state(
                                ambulance_id
                            )
                        )

                        if candidate_state is not None:
                            emergency_road = ambulance_road
                            emergency_state = candidate_state
                            emergency_active = True

                # Keep priority while the ambulance approaches
                # or is inside the junction.
                if (
                    emergency_active
                    and (
                        ambulance_road.startswith(":")
                        or ambulance_road == emergency_road
                    )
                ):
                    desired_state = emergency_state

                # The ambulance has reached its outgoing road.
                elif (
                    emergency_active
                    and ambulance_road not in INCOMING_EDGES
                    and not ambulance_road.startswith(":")
                ):
                    desired_state = None

            # ---------------------------------------------
            # APPLY EMERGENCY OR NORMAL SIGNAL
            # ---------------------------------------------

            if desired_state is not None:
                current_state = (
                    traci.trafficlight.getRedYellowGreenState(
                        TLS_ID
                    )
                )

                if current_state != desired_state:
                    set_state(desired_state)

                    print(
                        "[EMERGENCY] Priority signal:",
                        desired_state
                    )

                transition = None

            else:
                if emergency_active:
                    # End priority with yellow, then all-red.
                    current_state = (
                        traci.trafficlight.getRedYellowGreenState(
                            TLS_ID
                        )
                    )

                    set_state(to_yellow(current_state))

                    print(
                        "[EMERGENCY] Priority ended; "
                        "yellow started"
                    )

                    emergency_active = False
                    emergency_state = None
                    emergency_road = None

                    transition = "yellow"
                    transition_start = sim_time

                elif transition == "yellow":
                    if (
                        sim_time - transition_start
                        >= YELLOW_TIME
                    ):
                        set_state(ALL_RED)

                        transition = "all_red"
                        transition_start = sim_time

                        print("[SIGNAL] All-red clearance")

                elif transition == "all_red":
                    if (
                        sim_time - transition_start
                        >= ALL_RED_TIME
                    ):
                        # Resume at NS red-yellow, then NS green.
                        transition = None
                        stage_index = 0
                        stage_start = sim_time

                        set_state(NORMAL_STAGES[stage_index][0])

                        print(
                            "[SIGNAL] Resuming normal cycle: "
                            "NS red-yellow"
                        )

                elif transition is None:
                    state, duration = NORMAL_STAGES[stage_index]

                    if sim_time - stage_start >= duration:
                        stage_index = (
                            stage_index + 1
                        ) % len(NORMAL_STAGES)

                        stage_start = sim_time
                        state = NORMAL_STAGES[stage_index][0]

                        set_state(state)

                        print(
                            f"[NORMAL SIGNAL] "
                            f"stage={stage_index}, state={state}"
                        )

            # ---------------------------------------------
            # DIAGNOSTICS
            # ---------------------------------------------

            if sim_time - last_diagnostic_time >= 1.0:
                signal = (
                    traci.trafficlight.getRedYellowGreenState(
                        TLS_ID
                    )
                )

                print(
                    f"[STATUS] t={sim_time:.1f}s, "
                    f"command={command}, signal={signal}, "
                    f"emergency={emergency_active}"
                )

                for vid in get_active_ambulances():
                    try:
                        road = traci.vehicle.getRoadID(vid)
                        lane = traci.vehicle.getLaneID(vid)
                        speed = traci.vehicle.getSpeed(vid)
                        route = traci.vehicle.getRoute(vid)
                        route_index = traci.vehicle.getRouteIndex(vid)

                        print(
                            f"[AMB] id={vid}, road={road}, "
                            f"lane={lane}, speed={speed:.2f}, "
                            f"route={route}, "
                            f"routeIndex={route_index}"
                        )

                        if speed < 0.1 and not road.startswith(":"):
                            leader = traci.vehicle.getLeader(
                                vid,
                                CLEARING_DISTANCE
                            )

                            print(
                                f"[STOP CHECK] {vid}: "
                                f"leader={leader}, "
                                f"waiting="
                                f"{traci.vehicle.getWaitingTime(vid):.1f}s"
                            )

                    except traci.TraCIException as error:
                        print("[DIAGNOSTIC ERROR]", repr(error))

                last_diagnostic_time = sim_time

            traci.simulationStep()
            time.sleep(0.05)

    except traci.TraCIException as error:
        print("[SUMO CONNECTION ERROR]", repr(error))

    except Exception as error:
        print("[BRIDGE ERROR]", repr(error))
        raise

    finally:
        try:
            traci.close()
        except Exception:
            pass

        print("[BRIDGE] SUMO Bridge stopped")


if __name__ == "__main__":
    main()
