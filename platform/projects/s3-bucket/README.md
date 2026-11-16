# s3-bucket

Generic S3 bucket project. Wraps the shared `s3-bucket` module and applies a
configurable bucket policy.

## What it does

- Creates a single S3 bucket with the account-regional naming convention
  (`<name>-<account_id>-<region>-an`).
- Applies SSE encryption (AES256 by default, or KMS when `kms_key_arn` is set).
- Blocks all public access.
- Attaches a bucket policy. When `bucket_policy_json` is null (the default),
  the built-in policy is applied: `DenyInsecureTransport`, plus the KMS
  enforcement below when `enforce_kms_key` is true. Pass an alternative policy to
  replace the default — typical use cases include cross-account grants,
  replication policies, or service principal access. The alternative policy
  replaces the built-in statements; copy them into it if you still need them.
- Set `manage_bucket_policy = false` to create no policy at all, for a policy
  managed outside this project. S3 keeps one policy per bucket and
  `PutBucketPolicy` replaces it without warning, so only one project may manage
  it. `bucket_policy_json` must stay null in that case, and the KMS enforcement
  below does not apply.

## KMS key enforcement

Setting `kms_key_arn` only changes the bucket default encryption. Any client can
still upload with another encryption type or another key if it asks for it.
To refuse such uploads, also set `enforce_kms_key = true` (default `false`, so
existing buckets keep their policy). The built-in policy then gets one more
statement, `DenyOtherKmsKey`: a `Deny` on `s3:PutObject` (this also covers
`CopyObject` and multipart uploads) when the key ID in the request is not
`kms_key_arn`. The key ID is the `x-amz-server-side-encryption-aws-kms-key-id`
header, which the client can send with the key it wants. The value is compared
as text, so only the full key ARN matches.

An upload with no encryption options is allowed. S3 applies the bucket default
encryption, which is our key. Most clients send no options, so they need no
change. An upload that asks for its own encryption must ask for our key.
Examples with the AWS CLI:

| Upload | Result |
|--------|--------|
| no encryption options | allowed, the bucket default key is used |
| `--sse aws:kms --sse-kms-key-id <kms_key_arn>` | allowed |
| `--sse AES256` (SSE-S3) | denied |
| `--sse aws:kms` without a key | denied; S3 would use the AWS managed key |
| `--sse aws:kms --sse-kms-key-id <ARN of another key>` | denied |
| `--sse aws:kms --sse-kms-key-id alias/<name>` or a bare key ID | denied; the text is not `kms_key_arn` |

Operational notes:

- With `enforce_kms_key = true`, `kms_key_arn` must be a key ARN
  (`arn:...:key/<id>`), not an alias. The policy compares the header with this
  value as text, and a client that sends the key ARN would not match an alias.
  AWS also documents that the condition needs a key ARN. A plan fails for
  an alias. Without enforcement an alias is accepted, but AWS recommends the
  full key ARN, because it resolves an alias in the account of the caller.
- A client that names the key must use the full key ARN, not an alias or a key ID.
- Principals that read or write objects need `kms:Decrypt` and
  `kms:GenerateDataKey` on the key in their own IAM policy. The bucket policy
  does not grant them.
- Turning the key on does not re-encrypt existing objects. Copy them in place
  with the key named explicitly, which the policy allows:
  `aws s3 cp s3://<bucket>/ s3://<bucket>/ --recursive --sse aws:kms --sse-kms-key-id <kms_key_arn>`.
- Replication writes use `s3:ReplicateObject` and are not affected.
- Leave `enforce_kms_key = false` for a bucket that must accept objects
  encrypted with several keys or with SSE-S3.
- Switching `manage_bucket_policy` from `true` to `false` deletes the existing
  policy on the next apply. Until the external owner puts a new one, the bucket
  has no TLS-only deny. Apply the external policy right after, and do the
  reverse switch (to `true`) only after the external policy is removed.
- The policy does not block SSE-C (customer-provided keys). Since April 2026 S3
  blocks SSE-C on new buckets, and on existing buckets in accounts that had no
  SSE-C objects; see
  [Blocking or unblocking SSE-C](https://docs.aws.amazon.com/AmazonS3/latest/userguide/blocking-unblocking-s3-c-encryption-gpb.html).

## What it does NOT do

- It does not grant access to any IAM principal in the default policy.
  Same-account access is granted via the principal's IAM policy
  (see the [iam-user](../../shared/modules/iam-user) module).

## References

- [aws_s3_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket)
- [aws_s3_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy)
- [DenyInsecureTransport pattern](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [Requiring SSE-KMS with a specific key](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html)
- [Bucket policy examples using condition keys](https://docs.aws.amazon.com/AmazonS3/latest/userguide/amazon-s3-policy-keys.html)
