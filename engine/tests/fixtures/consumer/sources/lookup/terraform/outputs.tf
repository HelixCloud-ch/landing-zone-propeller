output "net_id" {
  value = "net-fixture"
}

output "subnet_ids_json" {
  value = jsonencode(["subnet-a", "subnet-b"])
}
