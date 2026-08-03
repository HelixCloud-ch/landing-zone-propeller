locals {
  sizes = {
    small = { capacity = 1 }
    large = { capacity = 8 }
  }
  size = local.sizes[var.size]
}
