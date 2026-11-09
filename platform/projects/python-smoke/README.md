# python-smoke

Test project for python envs and the `py-run` recipe. It runs
`main.py` in the `python-smoke` env and publishes the Python and PyYAML
versions, and the interpreter path, as outputs. It creates nothing.

```yaml
- project: python-smoke
  source: propeller:python-smoke
  target: <account>
  outputs:
    - name: python_version
    - name: pyyaml_version
    - name: interpreter
```

To run it offline on the deploy-runner image, add the env to the image in the
operations overlay (`image.overrides.yaml`):

```yaml
version: "1"
python_envs:
  python-smoke:
    path: ../../shared/python/python-smoke
```

The `interpreter` output shows if the baked env ran. See
[deploy-runner-image](../deploy-runner-image/README.md#python-envs).
