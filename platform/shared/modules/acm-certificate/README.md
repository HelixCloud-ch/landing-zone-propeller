# acm-certificate

Requests one ACM certificate: public with DNS or email validation, or private from AWS Private CA. It can wait until the certificate is `ISSUED`. It creates no DNS records.

## Usage

```hcl
module "certificate" {
  source = "../../../shared/modules/acm-certificate"

  domain_name               = "*.example.com"
  subject_alternative_names = ["example.com"]
  key_algorithm             = "EC_prime256v1"
  wait_for_validation       = true
  validation_record_fqdns   = ["_abc123.example.com"]
  tags                      = { Environment = "test" }
}
```

Outputs: `arn`, `domain_name`, `status`, `validation_records` (list of `{ name, type, value }`), and `validation_records_by_domain` (map from each certificate name to `{ name, type, value }`).

## Design notes

- **Modes.** The default is DNS validation. `validation_method = "EMAIL"` uses email, and `validation_domains` picks the validation domain per name. `certificate_authority_arn` requests a private certificate: `validation_method` must be null, and no validation happens.
- **Wait.** With `wait_for_validation = true` the module adds `aws_acm_certificate_validation`. The `arn` output then comes from the waiter, so a consumer gets the ARN only after issuance. `validation_record_fqdns` (DNS only) lets the provider check that the records exist first. `validation_timeout` is the create timeout. A private CA certificate cannot wait. A caller that indexes a `for_each` module call with a dynamic key to create the records cannot use this wait: terraform reports a dependency cycle, because the `arn` output depends on the waiter. The `acm-certificates` project does this, so it keeps its own waiter. A static reference to the module outputs has no cycle.
- **Records.** The module creates none. `validation_records` has one entry for each distinct record name. ACM returns the same CNAME for an apex and its wildcard. The module keeps one, so a caller can publish the records without a duplicate. `validation_records_by_domain` keeps one entry for each name, so a caller can map a name to its value. Both are empty for email and private CA.
- **Replacement.** The certificate has `create_before_destroy`. A change that replaces it creates the new certificate first. ACM refuses to delete a certificate that another service uses, so the apply fails while a consumer still points to the old one. Move the consumer first (rotate with a second module call).
- **Limits.** At most 99 additional names (100 with the primary name). The default account quota is 10 names in total. You can ask AWS to raise it. ACM reports a quota error at apply.
- **Not set.** The module sets no certificate transparency option and does not make the certificate exportable.
- **Domain.** The domain must be one the account can validate. Otherwise the request ends `FAILED` and the apply fails after about 5 minutes.
- **Tags.** A `Name` tag with the domain name is added. A `Name` in `tags` wins.
- **Standalone.** The module has no backend and no provider block. It works with a plain `terraform apply`.

## References

- [DNS validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html)
- [RequestCertificate API](https://docs.aws.amazon.com/acm/latest/APIReference/API_RequestCertificate.html)
- [aws_acm_certificate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate)
- [aws_acm_certificate_validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation)
