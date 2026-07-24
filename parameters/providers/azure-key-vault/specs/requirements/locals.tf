locals {
  vault_ids = var.workload_identity.enable ? { for id in var.workload_identity.key_vault_ids : id => id } : {}
}
