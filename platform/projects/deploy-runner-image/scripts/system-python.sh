#!/usr/bin/env bash
# Make python3.14 the default python for recipes that call `python3` directly
# (for example shared/recipes/terraform.just), and keep boto3 in the system
# Python for consumer scripts that import it without an env.
#
# New Python code should use a python env (`python_envs` in the manifest) and `py-run` instead; the
# boto3 install here is kept for compatibility and is not pinned.
set -euo pipefail

ln -sf /usr/bin/python3.14 /usr/local/bin/python3
ln -sf /usr/bin/python3.14 /usr/local/bin/python
ln -sf /usr/bin/pip3.14 /usr/local/bin/pip3
ln -sf /usr/bin/pip3.14 /usr/local/bin/pip

command -v pip3.14 >/dev/null || {
  echo "system-python: needs the python3.14-pip package (enable it or disable this script)" >&2
  exit 1
}
pip3.14 install --no-cache-dir boto3 botocore
python3 -c "import boto3, botocore"
