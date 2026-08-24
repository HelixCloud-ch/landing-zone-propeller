# State migration for consumers that applied this project before the resources
# moved into shared/modules/vpc-routes. Keep these blocks until every consumer
# has applied; removing them earlier makes the next plan treat the old addresses
# as orphaned.
#
# Route tables and associations keep their instance keys across the move (tier,
# and "<tier>-<index>"), so a single keyless block relocates every instance
# regardless of how the consumer configured its tiers.

moved {
  from = aws_route_table.this
  to   = module.routes.aws_route_table.this
}

moved {
  from = aws_route_table_association.this
  to   = module.routes.aws_route_table_association.this
}

# NOT MIGRATED HERE: aws_route.
#
# The old resource was keyed by tier (aws_route.tgw_default["app"]); routes are
# now keyed by tier and destination inside the module
# (module.routes.aws_route.this["app-0.0.0.0/0"]). A moved block preserves
# instance keys and cannot remap them, so this migration has to name each tier —
# and tier names are consumer configuration.
#
# Each consumer adds a moved.tf to its project overlay
# (platforms/<platform>/projects/vpc-routes/terraform/) with one block per tier
# that previously had routes:
#
#   moved {
#     from = aws_route.tgw_default["app"]
#     to   = module.routes.aws_route.this["app-0.0.0.0/0"]
#   }
#
# Without it the existing default route is destroyed and recreated: a
# sub-second window with no default route on that tier.
