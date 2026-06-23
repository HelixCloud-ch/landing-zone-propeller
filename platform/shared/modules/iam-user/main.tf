# ── IAM user ──────────────────────────────────────────────────────────────────

resource "aws_iam_user" "this" {
  name = var.username
  path = var.path
}

# ── Inline policy ─────────────────────────────────────────────────────────────
# Caller supplies the policy JSON (built with aws_iam_policy_document in the
# project layer). Only created when inline_policy_json is provided.

resource "aws_iam_user_policy" "this" {
  count = var.inline_policy_json != null ? 1 : 0

  name   = coalesce(var.policy_name, "${var.username}-policy")
  user   = aws_iam_user.this.name
  policy = var.inline_policy_json
}

# ── Managed policy attachments ────────────────────────────────────────────────

resource "aws_iam_user_policy_attachment" "this" {
  for_each = toset(var.policy_arns)

  user       = aws_iam_user.this.name
  policy_arn = each.value
}
