# React on Salesforce Pack

Patterns and guidance for **native React** components on the Salesforce platform — the platform's React support, alongside the existing LWC framework.

## When to use this pack

Install with `/argo:pattern-pack add react` if your project:
- Has `platform.frontend = "react"` or `"both"` in `sf-project.json`
- Builds React components under `paths.reactSource` (default `force-app/main/default/react/`)
- Uses `@salesforce/react/graphql` for org data

If the project is LWC-only, the base SF-1..20 patterns are sufficient — install the React pack only when React is in scope.

## What's in the pack

- **RX-1: Platform GraphQL Fetch** — `useQuery` / `useMutation` from `@salesforce/react/graphql`, FLS auto-enforced
- **RX-2: Platform-Aware Auth** — never hand-roll OAuth; the SDK injects credentials
- **RX-3: Deployment** — bundles deploy via `sf project deploy start` like LWC
- **RX-4: SLDS via React Tokens** — CSS custom properties + `@salesforce/react/slds-components`
- **RX-5: i18n** — `useLabel`, `useLocale`, `useFormatter` from `@salesforce/react/i18n`
- **RX-6: LWC ↔ React Interop** — `<lightning-react-host>` and `<LwcContainer>` for incremental migration

Plus four checklist items appended to `docs/quality-checklist.md` covering function components, GraphQL-only data, scoped CSS, test minimums.

## What's not in the pack

- Component scaffolding — that's `/argo:react-init`
- Lint enforcement — that's `hooks/lint-react.sh` (registered automatically when `platform.frontend` includes `react`)
- React-specific perf review — covered by `/argo:perf-review` (which gained React-bundle awareness in v2.4)

## Cross-references

- Companion docs: `docs/react-standards.md` (deeper rules, more cross-cutting)
- Specialist agent: `@react-dev`
- Skills: `/argo:react-init`, `/argo:perf-review`
- Base patterns that apply equivalently: SF-1 (lists), SF-2 (record details), SF-8 (toasts via SLDS components), SF-18 (i18n), SF-19 (virtualization), SF-20 (lazy-load)

## References

- [Salesforce React Developer Guide](https://developer.salesforce.com/docs/platform/react/guide)
- [`@salesforce/react/graphql` reference](https://developer.salesforce.com/docs/platform/react/api/graphql)
- [SLDS design tokens](https://www.lightningdesignsystem.com/2e1ef8501/p/63a48b-design-tokens)
