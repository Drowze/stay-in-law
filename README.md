# Stay in Law (Rails)

## Ruby version

- Required for local development: `ruby-4.0.0` (see `.ruby-version`)

## Setup

```bash
bundle install
bundle exec rails db:prepare
```

## Validation

```bash
bundle exec standardrb
bundle exec rails test
```

## Dependency update policy

- Direct dependencies are kept on the latest available versions where compatible.
- Current direct dependencies are up to date (`bundle outdated --only-explicit` reports `Bundle up to date!`).
- When a dependency is not on the absolute latest release, the reason should be compatibility constraints from Rails/Ruby or security/stability concerns and must be documented in this file.
