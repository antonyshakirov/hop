RNNoise 0.2 from the official Xiph release, unchanged source and default model.

Source: https://github.com/xiph/rnnoise/releases/tag/v0.2
Archive SHA-256: `90fce4b00b9ff24c08dbfe31b82ffd43bae383d85c5535676d28b0a2b11c0d37`.

The source archive is not fetched or executed at build time. Only the inference
library is compiled. Training, examples and upstream build scripts are excluded.
The retained BSD license is in COPYING and is included in the app bundle.

The release omits `os_support.h` and `opus_defines.h`, required by its ARM
implementation. These two unmodified headers are from Xiph Opus v1.5.2:
https://github.com/xiph/opus/tree/v1.5.2. Their notices are retained.
