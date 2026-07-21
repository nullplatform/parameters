# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Fix HashiCorp Vault parameters failing to retrieve after a successful store on Vault Enterprise namespaces. The Vault namespace and the KV mount are now configured as two independent fields (`setup.namespace` and `setup.path_prefix`), so read/write requests reach the real KV path `<namespace>/<mount>/data/<subpath>`. Previously a single `setup.namespace` field with a trailing-`/data` heuristic left no place for the KV mount name, so writes landed on a non-existent path.
- Validate the HTTP status of the HashiCorp Vault `store` write. `curl -s` exits 0 even on HTTP 4xx/5xx, so a failed write (wrong namespace/mount, missing permission) was previously reported as success while the value was never persisted.

### Changed

- Split the HashiCorp Vault `setup.namespace` field into two: `setup.namespace` (env `VAULT_NAMESPACE`) is now the Vault Enterprise namespace (applied as a URL prefix on login and every request; empty = root namespace), and the new `setup.path_prefix` (env `VAULT_PATH_PREFIX`, default `secret/data/nullplatform`) is the KV v2 `<mount>/data/<subpath>` prefix. The Vault namespace is no longer embedded in the `external_id`.

## [0.2.0] - 2026-07-14
### Added

- Add support to manage (store, retrieve and delete) parameters from HashiCorp Vault.

### Changed

- Read entity slugs from the notification payload and remove the remote calls to the nullplatform API.
- Refactor the AWS Parameter Store and Secrets Manager installation to build on reusable Terraform modules (`parameter_storage_definition`, `parameter_storage_configuration`, and the agent-association module) instead of a bundled local module, adding per-instance provider configuration and opt-in agent notification channels.

## [0.1.0] - 2026-07-03

### Added

- Add support to manage (store and retrieve) parameters from AWS Secret Manager and AWS Parameter store.
