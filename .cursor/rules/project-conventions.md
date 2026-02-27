---
description: Project conventions for soldier-trades-tracker
globs:
alwaysApply: true
---

This rule serves as high-level documentation for how this project is structured.

## Rules for AI

- Use this file to understand how the codebase works
- Treat this rule/file as your "source of truth" when making code recommendations

## Project conventions

These conventions should be used when writing code for this project.

### Convention 1: Minimize dependencies, vanilla Rails is plenty

Dependencies are a natural part of building software, but we aim to minimize them when possible to keep this open-source codebase easy to understand, maintain, and contribute to.

- Push Rails to its limits before adding new dependencies
- When a new dependency is added, there must be a strong technical or business reason to add it
- When adding dependencies, you should favor old and reliable over new and flashy

### Convention 2: Place business logic in service objects

This codebase adopts a "skinny controller, skinny models" approach.

- Place business logic in service objects (plain Ruby objects or modules under `app/services/`)
- Service objects should be as atomic as possible so they can be composed for more complex flows
- Controllers and jobs should delegate to services; avoid branching and heavy logic in them
- Do not add the interactor gem unless there is a strong reason (Convention 1: minimize dependencies)

### Convention 3: Prefer server-side solutions over client-side solutions

- When possible, leverage Turbo frames over complex, JS-driven client-side solutions
- When writing client-side code, use Stimulus controllers and keep it simple
- Keep client-side code for where it truly shines (e.g. bulk selection, live feedback). Use Stimulus as the default for any custom JS

### Convention 4: For jobs, use Solid Queue

Solid Queue's best practices can be found in its [wiki](https://github.com/rails/solid_queue).

### Convention 5: Use Minitest + Fixtures for testing, minimize fixtures

- Always use Minitest and fixtures for testing
- Keep fixtures to a minimum. Most models should have fixtures that represent the "base cases" for that model. "Edge cases" should be created on the fly, within the context of the test where they are needed

### Convention 6: Use ActiveRecord for complex validations, DB for simple and critical ones, keep business logic out of DB

- Enforce `null` checks, unique indexes, and other simple validations in the DB
- Use DB validations for critical business rules (e.g. unique index on trades per account + reference)
- ActiveRecord validations may mirror DB-level ones for convenience when handling form errors
- Complex validations and business logic should remain in ActiveRecord (or in service objects where appropriate)
