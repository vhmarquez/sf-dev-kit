---
name: lwc-vs-react
description: Decide whether a new UI component should be built as an LWC or a React component on Salesforce. Asks 5–7 quick questions, recommends with rationale and references to RX-* / SF-* patterns.
---

You are picking the frontend framework. Headless 360 added native React on the platform alongside LWC; both are first-class. The choice depends on the surface, the team's expertise, and the depth of integration with Salesforce-native primitives.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
FRONTEND="$(sf_config_get '.platform.frontend // \"lwc\"' "$ENV")"
```

If `platform.frontend = "lwc"`, this skill defaults to LWC and only recommends React if the user explicitly opts in (which would require also flipping the config). If `platform.frontend = "react"` or `"both"`, both options are live.

## Input

`$ARGUMENTS`:
- (empty) — interactive Q&A
- `<one-line description>` — concrete component context
- `--non-interactive answers="..."` — scripted

## Decision questions

1. **What surface?** Record page / App Builder / Experience Cloud / hosted outside the org?
2. **Salesforce-native data?** `getRecord`, `getObjectInfo`, picklist values, etc.?
3. **Complex client interactivity?** Drag-drop, rich-text editing, charts, multi-step forms?
4. **Team expertise?** Mostly LWC / mostly React / mixed?
5. **Reuse?** Does the project already have shared LWC components this would extend? Or shared React components?
6. **External libraries needed?** Charts, editors, design-system imports outside SLDS?
7. **Mobile / embedded?** Salesforce mobile app, embedded portal, custom domain?

## Decision tree

```
Record page placement, single-record focus
  → LWC
    `@wire(getRecord)` is built-in; SLDS-native record-page UX

App Builder + simple reusable widget
  → LWC
    Lower bundle weight; well-trodden path

Complex interactive UI (drag-drop, multi-step wizard, rich editor, charts)
  AND React expertise on the team
  → React (RX-1 GraphQL fetch, RX-4 SLDS via tokens, RX-6 LWC interop if needed)

Existing project is mostly React; new surface
  → React (avoid mixing if you don't have to)

Mobile-first / hosted outside the org
  → React typically wins (server-side rendering, hydration story)

Quick admin tool / internal-only / one-shot
  → LWC
    LWC's tooling is faster for "throw together a quick tool"

Heavy third-party libs (Material UI, Three.js, Monaco editor)
  → React (LWC's module system is more constrained)

Mixing — incremental migration of an Aura/legacy app
  → Both, with RX-6 LWC<->React interop primitives
```

## Output

```
# Choice: <one-line description>

## Answers
- Surface:           Experience Cloud landing page
- Salesforce-native data: light (member count, latest bulletins via GraphQL)
- Interactivity:     moderate (filtering, infinite scroll on bulletin feed)
- Team:              mixed (3 React, 2 LWC)
- Reuse:             no shared components on this surface yet
- External libs:     react-virtual (for the feed virtualization)
- Mobile:            yes — responsive design, embedded in the member portal app

## Recommendation: **React** (RX-1 + RX-4 + SF-19)

### Why
- Embedded in the member portal mobile app — React's hydration story is cleaner than LWC's mobile package
- Virtualization needed (>500 bulletins potentially) — `@tanstack/react-virtual` is well-tested; LWC has no equivalent first-party
- Mixed team with React majority — going LWC here forces the React engineers to context-switch; cost > the ~20% bundle-size savings LWC would offer
- `@salesforce/react/graphql` covers the data needs (RX-1); FLS auto-enforced

### Implementation outline
- /sf-dev-kit:react-init BulletinFeed --type page
- @react-dev: implement with useQuery + useVirtualizer
- @qa: tests via Vitest + RTL (@react-dev's scaffold provides 4 starter cases)
- Deploy via /sf-dev-kit:diff-deploy (handles React bundles same as LWC)

### Patterns referenced
- RX-1 (Platform GraphQL fetch)
- RX-4 (SLDS via React tokens)
- RX-5 (i18n for date formatting on bulletins)
- SF-19 (virtualized list — same threshold as LWC; React lib differs)

### Alternatives considered
- **LWC**: would work; ~30% smaller bundle. The interactivity is doable but the team mismatch makes ongoing iteration slower
- **Plain HTML page**: no — need real-time filtering and the GraphQL bindings save a lot of code
```

## Rules

- **Don't mix unnecessarily.** If the project is LWC, default to LWC. If React, default to React. Mixing has bundle-size and mental-model cost
- **Default toward LWC for record-page placements.** `@wire(getRecord)` is hard to beat when you're literally on a record page
- **Default toward React when external libs dominate.** If the bulk of the component is third-party (a chart lib, an editor), React's npm tooling is friendlier
- **Show the migration path.** When recommending a switch (LWC → React or vice versa), mention RX-6 interop so the user knows incremental migration is possible
- **Don't predict team preference.** Ask question #4 explicitly; don't assume

## Consumers

- `@architect` invokes this when planning a new UI surface
- `/sf-dev-kit:adr` captures the decision; future teammates know why
- `@lwc-dev` and `@react-dev` accept the recommendation and proceed
