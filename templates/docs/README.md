# {{project.name}} Documentation

Index of project documentation. Source files live under `force-app/main/default/`.

## Standards & Patterns

- [Apex Standards](apex-standards.md) — governor limits, security, SOQL/DML, async, naming
- [LWC Standards](lwc-standards.md) — CSS, JavaScript, accessibility
- [React Standards](react-standards.md) — React-on-Salesforce specifics _(present when `platform.frontend` includes react)_
- [Quality Checklist](quality-checklist.md) — unified pre-flight checklist (with Agent + Trust Layer + AI Gateway sections)
- [Salesforce Patterns](patterns/salesforce-patterns.md) — generic platform patterns (SF-1 through SF-20)
- [Project Patterns](patterns/project-patterns.md) — project-specific patterns and shared components

## Project Context

- [Project Context](project-context.md) — object model, channels, glossary, project-specific constraints

## Component Indexes

- [Lightning Web Components](lwc/README.md)
- [Apex Classes](apex-classes/README.md)
- [React Components](react/README.md) _(present when `platform.frontend` includes react)_
- [Agentforce Agents](agents/README.md) _(present when the project ships agents under `paths.agentDefinitions`)_

## Architecture Decision Records

- [ADRs](adr/) — significant architectural decisions, one per file (template at `adr/0000-template.md`)
