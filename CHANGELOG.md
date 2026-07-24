# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-07-27
### Added

- Add support to manage (store, retrieve and delete) parameters from Azure Key Vault.
- Add the Azure Key Vault install tofu module (`specs/install/`) built on the shared parameter-storage modules, plus a `specs/requirements/` module that provisions a user-assigned managed identity (AKS Workload Identity) and grants it the Key Vault Secrets Officer RBAC role.
- Azure Key Vault `setup` now authenticates the Azure CLI via an AKS workload-identity federated token when `AZURE_FEDERATED_TOKEN_FILE` / `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` are set.
- The Azure Key Vault `specs/requirements/` module can optionally create the Key Vault itself (`key_vault.enable`) with the RBAC authorization model and hardened defaults; it is an independent toggle from the managed identity, and when both are enabled the vault is scoped to the identity automatically.

### Changed

- Migrate the Azure Key Vault `specs/requirements/` identity from a service principal + client secret to an AKS Workload Identity (user-assigned managed identity federated to the agent's Kubernetes ServiceAccount), removing the expiring secret and the secret in tofu state.

### Fixed

- Fix HashiCorp Vault parameters not being retrievable after being stored on a Vault Enterprise namespace.
- Report a clear error when storing a parameter in HashiCorp Vault fails, instead of silently reporting success.

### Changed

- Configure the HashiCorp Vault namespace and KV path prefix as separate fields.

## [0.2.0] - 2026-07-14
### Added

- Add support to manage (store, retrieve and delete) parameters from HashiCorp Vault.

### Changed

- Read entity slugs from the notification payload and remove the remote calls to the nullplatform API.
- Refactor the AWS Parameter Store and Secrets Manager installation to build on reusable Terraform modules (`parameter_storage_definition`, `parameter_storage_configuration`, and the agent-association module) instead of a bundled local module, adding per-instance provider configuration and opt-in agent notification channels.

## [0.1.0] - 2026-07-03

### Added

- Add support to manage (store and retrieve) parameters from AWS Secret Manager and AWS Parameter store.
