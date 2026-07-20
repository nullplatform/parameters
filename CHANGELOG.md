# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Prefix the HashiCorp Vault login (both `userpass` and `kubernetes`) with the Vault Enterprise namespace derived from `setup.namespace` when it ends in the KV `data` segment (e.g. `admin/ns/data` → namespace `admin/ns`). Namespace-scoped credentials previously failed authentication with "access denied" because the login always targeted the root namespace. Prefixes whose `data` segment is in the middle (the default and any custom root-namespace subpath) are unaffected and keep logging in against the root namespace.

### Changed

- Rename the HashiCorp Vault `namespace` setup field label to "Namespace" and clarify its description (namespace and path prefix where parameters are stored).

## [0.2.0] - 2026-07-14
### Added

- Add support to manage (store, retrieve and delete) parameters from HashiCorp Vault.

### Changed

- Read entity slugs from the notification payload and remove the remote calls to the nullplatform API.
- Refactor the AWS Parameter Store and Secrets Manager installation to build on reusable Terraform modules (`parameter_storage_definition`, `parameter_storage_configuration`, and the agent-association module) instead of a bundled local module, adding per-instance provider configuration and opt-in agent notification channels.

## [0.1.0] - 2026-07-03

### Added

- Add support to manage (store and retrieve) parameters from AWS Secret Manager and AWS Parameter store.
