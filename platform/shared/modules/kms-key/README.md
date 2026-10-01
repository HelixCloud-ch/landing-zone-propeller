# kms-key

Symmetric customer managed key with an alias. The module owns the key
lifecycle only; the key policy comes from the caller (`policy_json`),
normally the `json` output of a policy module such as
`backup-kms-key-policy`.

Keeping the policy outside the key means a different access profile is a
policy change, applied in place (`PutKeyPolicy`), never a new key: a
destroyed key schedules deletion, and data it encrypted becomes
unrecoverable once the window expires.

Automatic rotation only applies to symmetric keys whose material AWS KMS
generates; set `enable_rotation = false` for imported key material or keys
in a custom key store.

## References

- [Key policies in AWS KMS](https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html)
- [EnableKeyRotation](https://docs.aws.amazon.com/kms/latest/APIReference/API_EnableKeyRotation.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.41 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.41 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alias"></a> [alias](#input\_alias) | Alias name for the key, without the 'alias/' prefix. | `string` | n/a | yes |
| <a name="input_deletion_window_in_days"></a> [deletion\_window\_in\_days](#input\_deletion\_window\_in\_days) | Waiting period before the key is deleted after a destroy (7-30). | `number` | `30` | no |
| <a name="input_description"></a> [description](#input\_description) | Description of the customer managed key. | `string` | n/a | yes |
| <a name="input_enable_rotation"></a> [enable\_rotation](#input\_enable\_rotation) | Enable automatic key rotation. Not supported for imported or custom key store key material. | `bool` | `true` | no |
| <a name="input_policy_json"></a> [policy\_json](#input\_policy\_json) | Key policy document (JSON), e.g. the json output of backup-kms-key-policy. | `string` | n/a | yes |
| <a name="input_rotation_period_in_days"></a> [rotation\_period\_in\_days](#input\_rotation\_period\_in\_days) | Rotation period (90-2560 days). Null keeps the AWS default of 365; ignored without rotation. | `number` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alias_arn"></a> [alias\_arn](#output\_alias\_arn) | ARN of the key alias. |
| <a name="output_key_arn"></a> [key\_arn](#output\_key\_arn) | ARN of the customer managed key. |
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | ID of the customer managed key. |
<!-- END_TF_DOCS -->
