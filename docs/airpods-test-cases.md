# AirPods mute acceptance

| Scenario | Expected evidence |
| --- | --- |
| Mute/unmute active microphone | Confirmed gate state and Hop status change together |
| Mixed microphone and application audio | Microphone becomes zero; application signal remains unchanged |
| Repeated same state | No duplicate application, callback or system-state publication |
| Gate or IPC failure | Reject gesture; do not display confirmed mute |
| No microphone capture | Acknowledge no-op; never open a device or mute application sound |
| Close, stop or device change | Retire target before teardown; late gesture cannot restart capture |
| Stale worker capture token | Reject; current microphone state unchanged |
| UI mute then accessory gesture | Same authoritative state, no echo/retry loop |
| Actual AirPods button | User presses button; no speech needed; observe Hop status and system banner |

Unit tests and synthetic PCM can verify routing without using a real microphone.
An actual AirPods gesture and live physical microphone remain hardware acceptance
checks; no recording is started without a separate notice.
