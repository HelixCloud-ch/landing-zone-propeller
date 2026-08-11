# Resolved once per endpoint entry. Fails the plan on a misspelled or
# unavailable service name instead of silently creating nothing. service_type
# is always passed (never inferred) because a few services (S3, DynamoDB)
# expose both a Gateway and an Interface variant as distinct records under
# the same service name — omitting it makes the data source fail with
# "multiple EC2 VPC Endpoint Services matched", confirmed against a live
# account (eu-west-1: com.amazonaws.eu-west-1.s3 returns one Gateway and one
# Interface ServiceDetail).
data "aws_vpc_endpoint_service" "this" {
  for_each = var.endpoints

  service      = each.value.service_name == null ? coalesce(each.value.service, each.key) : null
  service_name = each.value.service_name
  service_type = each.value.type
}
