# bedrock-model-access

Enables Amazon Bedrock third-party foundation models in the target account and
region, without invoking them. Idempotent and safe to re-run.

## What it does

1. Anthropic use case form: submitted only if none exists. The form is
   write-once, so later submissions are ignored. In opt-in regions such as
   eu-central-2 the management account's form is not inherited, so each
   account submits its own.
2. Model agreements: for each model, skipped if
   `agreementAvailability.status` is `AVAILABLE`. Otherwise the project reads
   the first agreement offer and creates the agreement.

`plan` reports what `apply` would do, without making changes. `destroy` is a
no-op: deleting an agreement doesn't block access, because the next invoke
recreates it. Block access with IAM or SCP deny policies instead.

Only models sold through AWS Marketplace need an agreement. Amazon (Nova),
Meta, Mistral, DeepSeek and Qwen models don't, so leave them out of
`model_ids`.

## Inputs

| Input | Required | Description |
| --- | --- | --- |
| `model_ids` | yes | Foundation model IDs, as a JSON list or comma-separated. Use base model IDs (`anthropic.claude-sonnet-4-5-20250929-v1:0`), not inference profile IDs. |
| `region` | no | Defaults to `AWS_REGION`. |
| `company_name` | if Anthropic | Use case form field. |
| `company_website` | if Anthropic | Use case form field. |
| `industry_option` | if Anthropic | Use case form field. |
| `other_industry_option` | no | Use case form field. |
| `use_cases` | if Anthropic | Use case form field. |
| `intended_users` | no | `0` internal, `1` external, `2` both. Defaults to `0`. |

## Finding model IDs

To list the base model IDs behind the geographic inference profiles in a
region (here, EU profiles reachable from eu-central-2):

```bash
aws bedrock list-inference-profiles --region eu-central-2 --no-cli-pager \
  --query "inferenceProfileSummaries[?starts_with(inferenceProfileId, 'eu.')].models[].modelArn" \
  --output json \
  | jq -r '.[] | split("/")[1]' | sort -u
```

The IDs come from the model ARNs, not from the profile IDs with the prefix
stripped: the two don't always match. Keep only Marketplace models (for
example `anthropic.*`); a model without an agreement offer fails the step.

## Example

```yaml
- project: bedrock-model-access
  source: propeller:bedrock-model-access
  target: tenant-${tenant.name}-workload
  inputs:
    - var: region
      literal: eu-central-2
    - var: model_ids
      literal: '["anthropic.claude-sonnet-4-5-20250929-v1:0"]'
    - var: company_name
      literal: Helix Cloud GmbH
    - var: company_website
      literal: https://www.helixcloud.ch/
    - var: industry_option
      literal: Other
    - var: other_industry_option
      literal: Cloud Consulting
    - var: use_cases
      literal: Document understanding and summarization.
```
