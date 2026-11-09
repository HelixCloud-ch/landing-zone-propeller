#!/usr/bin/env bash
# Script component used by tests/test.sh: proves scripts run, and run last.
set -euo pipefail
command -v uv >/dev/null
test -d /opt/propeller/python/python-smoke/.venv
echo "zz-test-marker ran" > /etc/propeller/test-marker
