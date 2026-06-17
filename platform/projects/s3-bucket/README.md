# s3-bucket

Generic S3 bucket project. Wraps the shared `s3-bucket` module and applies a
configurable bucket policy.

## What it does

- Creates a single S3 bucket with the account-regional naming convention
  (`<name>-<account_id>-<region>-an`).
- Applies SSE encryption (AES256 by default, or KMS when `kms_key_arn` is set).
- Blocks all public access.
- Attaches a bucket policy. When `bucket_policy_json` is null (the default),
  the built-in TLS-only policy (`DenyInsecureTransport`) is applied. Pass an
  alternative policy to extend or replace the default — typical use cases
  include cross-account grants, replication policies, or service principal
  access.

## What it does NOT do

- It does not grant access to any IAM principal in the default policy.
  Same-account access is granted via the principal's IAM policy
  (see [iam-app-user](../iam-app-user)).

## References

- [aws_s3_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket)
- [aws_s3_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy)
- [DenyInsecureTransport pattern](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
