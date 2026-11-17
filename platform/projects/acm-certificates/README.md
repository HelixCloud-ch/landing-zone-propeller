# acm-certificates

Requests ACM certificates in the account and Region of the step: public certificates with DNS or email validation, or private certificates from AWS Private CA.

## Certificates

`certificates` is a map. One item is one certificate. The project calls the [`acm-certificate`](../../shared/modules/acm-certificate) module with `for_each`, so the module stays a single-certificate unit and the project stays a collection. The module checks the per-item rules at plan time. The messages say what to fix. The main rules are:

- `validation_domains` is for `EMAIL` only. Each key is the domain or a SAN, and its value is that name or a parent domain.
- `early_renewal_duration` is for a private CA only. Use `P90D` (days) or `2160h` (hours).
- `key_algorithm` is `RSA_2048`, `EC_prime256v1`, or `EC_secp384r1`.
- A private CA item cannot use `validation_method`, `validation_zone_id`, or `wait_for_validation`.

Pick one issuance mode per item:

- DNS validation (default).
- Email validation: `validation_method = "EMAIL"`.
- Private certificate: set `certificate_authority_arn`. The key algorithm family must match the CA. A mismatch fails at apply, not at plan.

The default ACM quota is 10 names per certificate, including `domain_name`. You can ask AWS to raise it up to 100. ACM reports a quota error at apply.

## Validation records

The records of a certificate are known only after its first apply. The project has two ways to publish them. Choose per certificate.

| Case | `validation_zone_id` | `wait_for_validation` | Records |
|------|----------------------|-----------------------|---------|
| Zone in the same account | set | `true` or `false` | Created by this project. With `true` the step waits for `ISSUED`. |
| Zone in another account, or records by hand | not set | `false` | Published elsewhere from the `dns_validation_records` output: a `dns-record` step in the zone account, or by hand. |
| Email validation | not set | `true` or `false` | None. With `true` the step waits for the approval. |

DNS validation with `wait_for_validation = true` needs `validation_zone_id`. Without a published record the wait lasts until `validation_timeout` and then fails. Publishing by hand stays possible: leave the zone and the wait off.

Why the project creates the records and not the module: ACM gives one CNAME per name, and an apex and its wildcard share it. Two certificates with the same name share it too. The project builds one record per zone and base name, so it is created once. The [`dns-record`](../../shared/modules/dns-record) module has no overwrite option, so a second creation would fail. Keys come from the inputs only, because the ACM values are unknown at plan time.

One `validation_zone_id` serves one certificate: every name of the item (the domain and all SANs) gets its record in that zone. A name outside the zone fails in Route 53 at apply. For such a certificate, leave the zone off and publish the records elsewhere.

Rules for the zone:

- It must be public, in the account of the step. The project checks `private_zone` and fails on a private zone.
- Do not set `validation_zone_id` for names whose records already exist (for example published by hand). The create fails.
- Keep the records after issuance. ACM uses them again for managed renewal. Removing `validation_zone_id` deletes them, and renewal then fails.

The `dns_validation_records` output lists the records of all DNS certificates, also those with a zone. Its key is `acm-<first 8 hex of sha1(record name)>`. It depends only on the name, so it stays the same when you add, rotate or remove certificates, as long as one certificate still has the name.

## Waiting for issuance

`wait_for_validation` makes the project wait until the certificate is `ISSUED`. The ARN in `arns` is then known only after issuance, so a consumer never gets an unissued ARN. `validation_timeout` is the limit of every wait. The waits run in parallel. The pipeline step `timeout` must be larger than `validation_timeout`.

The `statuses` output is the status at the last refresh. On the run that waits, it can still say `PENDING_VALIDATION` while `arns` is already the issued ARN. Use `arns` as the signal.

The wait lives in the project and not in the module. The records need data from the module, and a module waiter makes the module `arn` depend on the records. Terraform reports a dependency cycle for that layout. The project waiter checks the FQDNs of the records the project created.

## Pipeline wiring

Zone in the same account: no second step.

Zone in another account:

```yaml
- project: acm-certificates-1
  source: propeller:acm-certificates
  target: <workload account>
  outputs:
    - name: arns
    - name: dns_validation_records

- project: acm-validation-dns
  source: propeller:dns-record
  target: <account of the public validation zone>
  inputs:
    - name: acm-certificates-1.dns_validation_records
      var: records
```

Set `zone_id` in the `dns-record` overlay.

## Consumer tfvars

```hcl
region = "eu-central-2"

certificates = {
  # Zone in the same account: records created, step waits for ISSUED
  shop = {
    domain_name         = "shop.example.com"
    key_algorithm       = "EC_prime256v1"
    validation_zone_id  = "Z0123456789ABCDEFGHIJ"
    wait_for_validation = true
  }

  # Records published elsewhere: no zone, no wait
  main = {
    domain_name               = "*.example.com"
    subject_alternative_names = ["example.com"]
  }
}
```

The only required input is `region`. Every output is a map keyed by certificate key, except `dns_validation_records`, which is one flat map for all certificates in the shape of the `dns-record` `records` input. `arns` is known after issuance when the item waits. `validation_record_fqdns` lists the records this project created, and is empty without a zone.

## Operational notes

- **Key is the state address.** A key in `certificates` is the state address (`module.certificate["<key>"]`). Renaming it destroys and recreates the certificate, and the ARN changes. Pick a stable key.
- **First apply.** Without a wait, the status is `PENDING_VALIDATION` until the records exist in a public zone.
- **The domain must be one the account can validate.** A request for a domain you do not control ends `FAILED` with `ADDITIONAL_VERIFICATION_REQUIRED`. The apply then fails after about 5 minutes. `example.com` appears here in examples only.
- **Import.** To adopt an existing certificate, run `terraform import 'module.certificate["<key>"].aws_acm_certificate.this' <certificate ARN>` with the same names and settings as in `certificates`. Other names or a different key algorithm replace the certificate.
- **Sleep/wake.** The project is not in a sleep preset. Certificates are free, and renewal needs the same records.
- **Rotation.** A certificate cannot be deleted while a listener uses it. To change the key algorithm or the names, add a new item with the new settings (the same names are allowed, and the records are shared). Run the pipeline, move the consumer to the new ARN, then remove the old item.
- **Public names.** ACM logs every name of a public certificate in public Certificate Transparency logs. Do not use sensitive host names.
- **Imported certificates.** They are out of scope, because the private key would sit in tfvars and state. A consumer with an imported certificate gives its ARN directly to the consumer of the certificate (for example `alb`).

## Indicative deploy role permissions

Indicative only. Check the list against your own policy and the provider version.

- `acm:RequestCertificate`
- `acm:DescribeCertificate`
- `acm:DeleteCertificate`
- `acm:ListTagsForCertificate`
- `acm:AddTagsToCertificate`
- `acm:RemoveTagsFromCertificate`

With `validation_zone_id`, also allow these actions on the hosted zone:

- `route53:GetHostedZone`
- `route53:ListTagsForResource`
- `route53:ChangeResourceRecordSets`
- `route53:ListResourceRecordSets`
- `route53:GetChange`

For a private CA, also allow these actions on the CA. A shared CA also needs a resource policy that allows the account.

- `acm-pca:IssueCertificate`
- `acm-pca:GetCertificate`
- `acm-pca:GetCertificateAuthorityCertificate`

## What does NOT belong here

- Validation records in a zone of another account. Use `dns-record` in the account of the zone.
- Imported certificates.
- The Private CA itself. This project only uses its ARN.
- Certificates for CloudFront. They must be in `us-east-1`. Use a step with that Region.

## References

- [DNS validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html)
- [Import certificates](https://docs.aws.amazon.com/acm/latest/userguide/import-certificate.html)
- [RequestCertificate API](https://docs.aws.amazon.com/acm/latest/APIReference/API_RequestCertificate.html)
- [ACM FAQ](https://aws.amazon.com/certificate-manager/faqs/)
- [aws_acm_certificate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate)
- [aws_acm_certificate_validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation)
- [acm-certificate module](../../shared/modules/acm-certificate)
- [dns-record module](../../shared/modules/dns-record)
- [dns-record project](../dns-record)
