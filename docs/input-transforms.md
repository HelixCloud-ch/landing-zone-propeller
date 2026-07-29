# Input Transforms (jq)

Pipeline inputs can include a `jq` field that transforms the raw value before
it reaches terraform. The expression runs at deploy time in CodeBuild using
the standard `jq` CLI.

## Syntax

```yaml
inputs:
  - name: source-project.output_field
    var: terraform_variable_name
    jq: '<jq expression>'
```

The raw string value is piped through the jq expression. The result is written
to `_propeller.auto.tfvars.json` as a typed JSON value (not a string).

When there is no `jq` field, the value is written as a plain string (existing behavior).

## How it works

1. Autopilot reads the input value from SSM (string)
2. Autopilot passes it to CodeBuild as `PROPELLER_INPUT_<var>=<value>`
3. Autopilot also passes `PROPELLER_TRANSFORMS_JSON={"var":"jq expr",...}`
4. The shared recipe (`_propeller-vars`) applies the jq expression per-input
5. The transformed result is written as a typed JSON value in `_propeller.auto.tfvars.json`

## Examples

### Wrap a string in a list

A module expects `allowed_cidrs = list(string)` but the input is a single CIDR string.

```yaml
inputs:
  - name: vpc-project.cidr_block
    var: allowed_cidrs
    jq: "[.]"
```

| Input | Output |
|-------|--------|
| `"10.0.0.0/8"` | `["10.0.0.0/8"]` |

### Map lookup (size presets)

Translate a human-friendly size name to a concrete instance class.

```yaml
inputs:
  - name: "_static:small"
    var: instance_class
    jq: '{"small":"db.t3.medium","medium":"db.m5.large","large":"db.m5.xlarge"}[.]'
```

| Input | Output |
|-------|--------|
| `"small"` | `"db.t3.medium"` |
| `"medium"` | `"db.m5.large"` |

### Extract a key from a JSON object

A project outputs a JSON blob. You need one field from it.

```yaml
inputs:
  - name: vpc-project.subnet_ids_json
    var: private_subnets
    jq: ".private"
```

| Input | Output |
|-------|--------|
| `{"private":["s-1","s-2"],"data":["s-3"]}` | `["s-1","s-2"]` |

### Conditional (empty string handling)

Only wrap in a list if the value is non-empty, otherwise produce an empty list.

```yaml
inputs:
  - name: vpc-project.cidr_block
    var: allowed_cidrs
    jq: 'if . == "" then [] else [.] end'
```

| Input | Output |
|-------|--------|
| `"10.0.0.0/8"` | `["10.0.0.0/8"]` |
| `""` | `[]` |

### Split a comma-separated string into a list

```yaml
inputs:
  - name: config-project.sg_ids_csv
    var: security_group_ids
    jq: 'split(",")'
```

| Input | Output |
|-------|--------|
| `"sg-123,sg-456,sg-789"` | `["sg-123","sg-456","sg-789"]` |

### Cast string to number

Terraform expects a number but the input arrives as a string (all SSM values are strings).

```yaml
inputs:
  - name: "_static:20"
    var: allocated_storage
    jq: "tonumber"
```

| Input | Output |
|-------|--------|
| `"20"` | `20` |

### Cast string to boolean

```yaml
inputs:
  - name: "_static:true"
    var: multi_az
    jq: '. == "true"'
```

| Input | Output |
|-------|--------|
| `"true"` | `true` |
| `"false"` | `false` |

### String concatenation / formatting

```yaml
inputs:
  - name: "_static:oracle-adt-0"
    var: identifier
    jq: '"propeller-" + .'
```

| Input | Output |
|-------|--------|
| `"oracle-adt-0"` | `"propeller-oracle-adt-0"` |

### Nested extraction with fallback

```yaml
inputs:
  - name: vpc-project.subnet_ids_json
    var: data_subnets
    jq: '.data // []'
```

| Input | Output |
|-------|--------|
| `{"private":[...],"data":["s-3","s-4"]}` | `["s-3","s-4"]` |
| `{"private":[...]}` | `[]` |

### Multiple values from one source (use separate inputs)

If you need multiple fields from one JSON blob, declare separate inputs:

```yaml
inputs:
  - name: vpc-project.subnet_ids_json
    var: private_subnets
    jq: ".private"
  - name: vpc-project.subnet_ids_json
    var: data_subnets
    jq: ".data"
```

### Map with default fallback

```yaml
inputs:
  - name: "_static:small"
    var: instance_class
    jq: '{"small":"db.t3.medium","medium":"db.m5.large"}[.] // "db.t3.medium"'
```

| Input | Output |
|-------|--------|
| `"small"` | `"db.t3.medium"` |
| `"unknown"` | `"db.t3.medium"` (fallback) |

## Notes

- The jq expression receives the raw value as input (`.` refers to the value)
- For string inputs, jq receives the value as a raw string (using `jq -R`)
- For inputs that are already valid JSON (like blobs), jq parses them as JSON
- If the jq expression fails, the build errors immediately with a clear message
- Transforms are applied at deploy time (in CodeBuild), not at resolve time
- The `jq` field is preserved through resolve and into the pipeline lock file
- `jq` is pre-installed in the deploy-runner image

It is recommended to avoid transforms when possible, designing project vars to
be compatible within the propeller ecosystem.
