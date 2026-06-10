# Plan-time assertions (design Testing Strategy). check blocks emit warnings
# rather than blocking the plan, so they surface registry mistakes without making
# a benign empty configuration fail.

# Req 7.4 — every peer named in allowed_destinations resolves to a reserved
# keyword or an existing registry entry. Unknown names are silently dropped from
# route generation; this surfaces them so they are not lost without notice.
check "allowed_destinations_resolve" {
  assert {
    condition = alltrue(flatten([
      for name, s in local.spokes : [
        for dest in s.allowed_destinations :
        contains(["hub", "onprem"], dest) || contains(keys(local.spokes), dest)
      ]
    ]))
    error_message = "One or more spokes name an allowed_destination that is neither a reserved keyword (hub, onprem) nor an existing registry key. Such entries produce no route. Check spelling of friendly names in the registry."
  }
}

# Property 7 — quota safety. Visible even when no segment tables exist yet.
check "segment_quota" {
  assert {
    condition     = length(var.segments) <= 20
    error_message = "segments declares ${length(var.segments)} route tables; the default TGW route-table quota is 20. Request a quota increase or reduce the segment count."
  }
}

# Property 1 (regression guard) — a spoke with empty allowed_destinations
# contributes no reachability route in any of the route maps.
check "isolation_by_default" {
  assert {
    condition = alltrue([
      for name, s in local.spokes :
      length([
        for k in concat(keys(local.hub_routes), keys(local.onprem_routes), keys(local.peer_routes)) :
        k if startswith(k, "${name}@")
      ]) == 0 if length(s.allowed_destinations) == 0
    ])
    error_message = "A spoke with empty allowed_destinations has a reachability route keyed to it; isolation-by-default is violated."
  }
}
