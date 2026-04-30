# React-on-Salesforce Standards

Practical standards for React components on the Salesforce platform. Read alongside `docs/lwc-standards.md` (much overlaps) and `docs/patterns/salesforce-patterns.md` (SF-15..20 apply equivalently — adapted in the `react` pattern pack as RX-1..6).

This document covers React-specific rules; cross-cutting standards (accessibility, i18n, security) are unified with LWC where they apply identically.

---

## Source Layout

Components live under `paths.reactSource` (default `force-app/main/default/react/`). One directory per component:

```
react/
└── OrderList/
    ├── OrderList.tsx
    ├── OrderList.module.css
    ├── OrderList.meta.xml
    ├── OrderList.test.tsx
    ├── index.ts
    └── README.md     (optional; doc lives in docs/react/)
```

Use `/argo:react-init` to scaffold consistent bundles.

---

## Component shape

### Function components only

```tsx
// DO
export function OrderList({ pageSize = 25 }: OrderListProps) {
  // hooks
}

// DO NOT
export class OrderList extends React.Component { /* ... */ }
```

Class components are not supported on the platform's React runtime. Hooks-only.

### TypeScript preferred

Default. JavaScript projects coexist but TypeScript catches platform-API misuse at compile time.

### Strict prop interfaces

```tsx
// DO
export interface OrderListProps {
  pageSize?: number;
  onSelect?: (orderId: string) => void;
}

// DO NOT
export function OrderList(props: any) { /* ... */ }
```

`any` is forbidden in production code. Use `unknown` and narrow.

---

## Data Access

### Use `@salesforce/react/graphql` for org data

```tsx
import { useQuery, useMutation } from '@salesforce/react/graphql';

const ORDERS_QUERY = `query Orders($limit: Int!) {
  uiapi { query { Order__c(first: $limit) { edges { node { Id Name { value } } } } } }
}`;

const { data, loading, error } = useQuery(ORDERS_QUERY, { variables: { limit: 25 } });
```

The GraphQL client:
- Auto-injects authentication (no `Authorization` header to manage)
- Enforces sharing and FLS automatically — same security model as LWC `@wire`
- Caches across components — refetch is cheap
- Handles loading/error states declaratively

### Never use raw `fetch` for org data

```tsx
// DO NOT
fetch('/services/data/v63.0/query?q=SELECT...')
```

The auth surface is not stable across deployment contexts (scratch org / sandbox / prod) and you'd lose Trust Layer features. Use the GraphQL client.

### Mutations

```tsx
const [createOrder, { loading }] = useMutation(CREATE_ORDER_MUTATION);

const handleSubmit = async (input: OrderInput) => {
  const { data, errors } = await createOrder({ variables: { input } });
  if (errors) { /* surface to user */ }
};
```

---

## Styling

### CSS Modules

```tsx
import styles from './OrderList.module.css';

<div className={styles.list}>{...}</div>
```

Classnames are scoped per-component. No global CSS leaks.

### SLDS tokens via CSS custom properties

```css
.list li {
  padding: var(--slds-g-spacing-medium);
  color: var(--slds-g-color-text-base-50);
  border-bottom: 1px solid var(--slds-g-color-border-base-1);
}
```

The platform exposes the SLDS design tokens as CSS custom properties. Use them — don't hardcode colors or spacing.

### No CSS-in-JS libraries that conflict with the platform

`styled-components` and `emotion` work, but introduce build complexity. CSS Modules is the recommended default.

### No `!important`, ever

Same rule as LWC. If you need to override SLDS, use a more-specific selector or a different component.

---

## Accessibility

Identical rules to LWC standards (`docs/lwc-standards.md` Accessibility section). Key points:
- Semantic HTML (`<button>`, not `<div onClick>`)
- ARIA attributes on custom-built interactive elements
- Keyboard navigation: Tab, Enter, Esc, arrow keys for list/menu
- Focus management on modal open / close
- Screen-reader text for icons (`aria-label`)
- Loading state announced (`role="status"` + sr-only text)

---

## Internationalization

Use `@salesforce/react/i18n` hooks:

```tsx
import { useLabel, useLocale, useFormatter } from '@salesforce/react/i18n';

const label = useLabel('My_Custom_Label');
const locale = useLocale();
const fmt = useFormatter({ style: 'currency' });
```

- Custom Labels: `useLabel('<DeveloperName>')` — equivalent to LWC's `import LBL from '@salesforce/label/c.<Name>'`
- Locale-aware formatting: `useFormatter` returns an `Intl.NumberFormat` / `Intl.DateTimeFormat` configured for the user's locale
- RTL: use logical CSS properties (`margin-inline-end`) or SLDS direction-aware utilities; avoid hardcoded `left`/`right`

Server messages thrown via `AuraHandledException` are not translated — pass a Custom Label key from Apex when you need translated error messages (same pattern as LWC).

---

## Performance

### Memoize selectively

```tsx
const sortedOrders = useMemo(() => orders.sort(byCreatedDate), [orders]);
const onClick = useCallback((id: string) => onSelect?.(id), [onSelect]);
```

Only memoize when the dependency is genuinely stable AND the computation/callback is in a hot render path. Premature memoization adds complexity without speed.

### Virtualize lists > ~500 rows

Use `@tanstack/react-virtual`:

```tsx
import { useVirtualizer } from '@tanstack/react-virtual';

const rowVirtualizer = useVirtualizer({
  count: orders.length,
  estimateSize: () => 36,
  getScrollElement: () => parentRef.current,
});
```

Same threshold as SF-19 (LWC). Below ~500 rows, plain rendering is simpler and faster.

### Lazy-load heavy components

```tsx
const RichTextEditor = React.lazy(() => import('./RichTextEditor'));

<Suspense fallback={<Spinner />}>
  <RichTextEditor />
</Suspense>
```

Same threshold and rationale as SF-20 (LWC dynamic import).

### Don't lift state too high

State that only one component needs lives in that component, not in a shared store. Premature Redux / Zustand introduction is a perf antipattern.

---

## Testing

### Vitest (preferred) or Jest

The skill `/argo:react-init` scaffolds Vitest by default. Match what `quality.unitTestCommand` runs.

### React Testing Library

```tsx
import { render, screen, userEvent } from '@testing-library/react';

test('renders order count', async () => {
  render(<OrderList orders={[/* ... */]} />);
  expect(screen.getByText(/3 orders/)).toBeInTheDocument();
});
```

Test behavior, not implementation. Query by accessibility-friendly attributes (`getByRole`, `getByLabelText`) over CSS selectors.

### Mock platform modules consistently

The plugin's scaffold mocks `@salesforce/react/graphql`, `@salesforce/react/i18n`, `@salesforce/react/slds-components`. Reuse those mocks across the project — define them in a shared `tests/setup.ts`.

### Four states minimum

Same as LWC: data loaded, empty, error, loading. Plus user interactions for any clickable element.

---

## LWC ↔ React Interop

For incremental migration or mixed UIs:

### Embed React in an LWC

```html
<!-- LWC HTML -->
<template>
  <lightning-react-host component="c/orderList"></lightning-react-host>
</template>
```

`<lightning-react-host>` is the platform-provided shell that mounts a React bundle inside an LWC parent.

### Embed an LWC in React

```tsx
import { LwcContainer } from '@salesforce/react/lwc-interop';

<LwcContainer name="c/legacyOrderForm" attrs={{ recordId: orderId }} />
```

Pass primitive attributes only; complex state belongs in the parent.

### When to mix

Acceptable transition state during migration. Long-term, pick one framework per surface and stick with it — mixing imposes mental overhead and bundle-size cost.

---

## Deployment

React bundles deploy via `sf project deploy start` exactly like LWC bundles. The platform builds the React tree at deploy time; the deployed artifact is the source files plus a generated build manifest.

- `/argo:diff-deploy` — deploys only changed React bundles since `<ref>`
- `/argo:deploy` — full deploy (or specific paths)
- `/argo:perf-review` — covers React bundles in v2.4+; reports bundle size, render-blocking imports, lazy-load opportunities

---

## Documentation

Each React component gets a doc at `paths.reactDocs/<ComponentName>.md` (default `docs/react/`). Format mirrors `paths.lwcDocs`:

```markdown
# OrderList

(One-sentence purpose.)

## Props

| Name | Type | Default | Purpose |
|------|------|---------|---------|

## Data

(GraphQL queries + mutations used; FLS rules)

## Targets

(Lightning page contexts where it's exposed)

## Tests

(Path + summary of what's covered)
```

Index in `docs/react/README.md`.

---

## Cross-References

- LWC standards (most rules apply identically): `docs/lwc-standards.md`
- Pattern pack `react` (RX-1..6): install via `/argo:pattern-pack add react`
- Apex standards (for backing controllers): `docs/apex-standards.md`
- Quality checklist (unified pre-flight): `docs/quality-checklist.md`
