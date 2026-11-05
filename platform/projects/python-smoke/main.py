"""Report the Python env this project runs in, as outputs."""

import json
import sys

import yaml

outputs = {
    "python_version": sys.version.split()[0],
    "pyyaml_version": yaml.__version__,
    "pyyaml_libyaml": str(yaml.__with_libyaml__).lower(),
    "interpreter": sys.executable,
}
for key, value in outputs.items():
    print(f"python-smoke: {key}={value}")

with open(".propeller-outputs.json", "w") as f:
    json.dump(outputs, f)
