import os
import time
import matplotlib.pyplot as plt

CMD_FILE = r"D:\sim\tls_cmd.txt"

times = []
states = []

start_time = time.perf_counter()
last_state = None

plt.ion()

fig, ax = plt.subplots()
line, = ax.step([], [], where="post")

ax.set_title("SUMO Emergency Traffic Light Status")
ax.set_xlabel("Time (ms)")
ax.set_ylabel("Emergency Status")
ax.set_yticks([0, 1])
ax.set_yticklabels(["OFF", "ON"])
ax.set_ylim(-0.2, 1.2)
ax.grid(True)

while plt.fignum_exists(fig.number):

    try:
        if os.path.exists(CMD_FILE):
            with open(CMD_FILE, "r") as f:
                command = f.read().strip().upper()

            if command in ("G", "R"):
                state = 1 if command == "G" else 0

                if state != last_state:
                    elapsed = (time.perf_counter() - start_time) * 1000

                    times.append(elapsed)
                    states.append(state)

                    last_state = state

                    line.set_data(times, states)

                    ax.set_xlim(
                        0,
                        max(1000, elapsed + 1000)
                    )

                    fig.canvas.draw_idle()
                    fig.canvas.flush_events()

    except Exception as e:
        print("Graph error:", e)

    plt.pause(0.1)