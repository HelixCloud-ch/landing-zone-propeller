# Input Transforms (JSONata)

Pipeline inputs can include an `expr` field with a JSONata expression that
transforms the raw value before it reaches terraform. The expression runs in
the Autopilot Lambda at deploy time.

## Syntax

```yaml
inputs:
  - name: source-project.output_field
    var: terraform_variable_name
    expr: '<JSONata expression>'
```

The raw value is available as `$` in the expression. If the raw value is valid
JSON (e.g. a subnet map blob), it's parsed first so you can access nested fields
directly.

## How it works

1. Autopilot reads the input value from SSM (string)
2. Autopilot evaluates the JSONata expression with the value as input
3. The result (JSON-encoded) is passed to CodeBuild as `PROPELLER_INPUT_<var>`
4. The shared recipe writes it to `_propeller.auto.tfvars.json` (auto-detects
   JSON vs string values)

Transforms run in the Lambda, so any project type benefits (not just terraform).

## Examples

### Wrap a string in a list

A module expects `allowed_cidrs = list(string)` but the input is a single CIDR string.

```yaml
inputs:
  - name: vpc-project.cidr_block
    var: allowed_cidrs
    expr: "[$]"
```

| Input | Output |
|-------|--------|
| `10.0.0.0/8` | `["10.0.0.0/8"]` |

### Map lookup (size presets)

Translate a human-friendly size name to a concrete instance class.

```yaml
inputs:
  - name: "_static:small"
    var: instance_class
    expr: '$lookup({"small":"db.t3.medium","medium":"db.m5.large","large":"db.m5.xlarge"}, $)'
```

| Input | Output |
|-------|--------|
| `small` | `"db.t3.medium"` |
| `medium` | `"db.m5.large"` |

### Extract a key from a JSON object

A project outputs a JSON blob. You need one field from it.

```yaml
inputs:
  - name: vpc-project.subnet_ids_json
    var: private_subnets
    expr: "private"
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
    expr: '$ = "" ? [] : [$]'
```

| Input | Output |
|-------|--------|
| `10.0.0.0/8` | `["10.0.0.0/8"]` |
| `` | `[]` |

### Split a comma-separated string into a list

```yaml
inputs:
  - name: config-project.sg_ids_csv
    var: security_group_ids
    expr: '$split($, ",")'
```

| Input | Output |
|-------|--------|
| `sg-123,sg-456,sg-789` | `["sg-123","sg-456","sg-789"]` |

### Cast string to number

Terraform expects a number but the input arrives as a string.

```yaml
inputs:
  - name: "_static:20"
    var: allocated_storage
    expr: "$number($)"
```

| Input | Output |
|-------|--------|
| `20` | `20` |

### Cast string to boolean

```yaml
inputs:
  - name: "_static:true"
    var: multi_az
    expr: '$ = "true"'
```

| Input | Output |
|-------|--------|
| `true` | `true` |
| `false` | `false` |

### String concatenation / formatting

```yaml
inputs:
  - name: "_static:my-db"
    var: identifier
    expr: '"propeller-" & $'
```

| Input | Output |
|-------|--------|
| `my-db` | `"propeller-my-db"` |

### Nested extraction with fallback

```yaml
inputs:
  - name: vpc-project.subnet_ids_json
    var: data_subnets
    expr: "data ? data : []"
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
    expr: "private"
  - name: vpc-project.subnet_ids_json
    var: data_subnets
    expr: "data"
```

### Map with default fallback

```yaml
inputs:
  - name: "_static:small"
    var: instance_class
    expr: '$lookup({"small":"db.t3.medium"}, $) ? $lookup({"small":"db.t3.medium"}, $) : "default"'
```

| Input | Output |
|-------|--------|
| `small` | `"db.t3.medium"` |
| `unknown` | `"default"` |

## JSONata reference

JSONata is a lightweight query and transformation language for JSON.
Full docs: https://docs.jsonata.org/

Common operators:
- `$` is the input value
- `&` concatenates strings
- `[$]` wraps in an array
- `condition ? true_value : false_value` for conditionals
- `$number($)` casts to number
- `$split($, ",")` splits a string
- `$lookup(object, key)` does a map lookup
- `fieldname` accesses a key in a JSON object

## Notes

- The `expr` field is optional. Inputs without it pass through as plain strings.
- Transforms run in the Lambda (not CodeBuild), so errors are caught before
  a build starts.
- If the expression fails, the pipeline step fails with a clear error.
- For string inputs, the value is available as `$` (a string).
- For JSON inputs (valid JSON from a blob field), the value is parsed and you
  can access fields directly (e.g. `private` to get the `private` key).
- Prefer using common formats across the framework ecosystem (e.g. standardize
  on JSON lists for CIDRs, consistent key naming in blobs) to avoid needing
  transforms in the first place. Use transforms only when the source and
  target variable interfaces don't align.
