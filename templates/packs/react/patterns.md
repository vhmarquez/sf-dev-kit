## RX-1: Platform GraphQL Fetch (React) {#rx-graphql-fetch}

Use `@salesforce/react/graphql` for any org data. The SDK handles auth, sharing, and FLS — equivalent to LWC's `@wire(getRecord)`.

```tsx
import { useQuery, useMutation } from '@salesforce/react/graphql';

const ORDERS_QUERY = `
  query Orders($limit: Int!, $status: String) {
    uiapi {
      query {
        Order__c(
          first: $limit,
          where: { Status__c: { eq: $status } },
          orderBy: { CreatedDate: { order: DESC } }
        ) {
          edges {
            node {
              Id
              Name { value }
              Status__c { value }
              Total_Amount__c { value }
              Customer__r { Name { value } }
            }
          }
        }
      }
    }
  }
`;

export function OrderList({ status = 'OPEN', pageSize = 25 }: OrderListProps) {
  const { data, loading, error, refetch } = useQuery(ORDERS_QUERY, {
    variables: { limit: pageSize, status },
  });

  if (loading) return <Spinner />;
  if (error)   return <ErrorBanner error={error} onRetry={refetch} />;

  const orders = data?.uiapi.query.Order__c.edges ?? [];
  if (orders.length === 0) return <EmptyState />;

  return <OrderTable rows={orders.map(e => e.node)} />;
}
```

Mutations:

```tsx
const CANCEL_ORDER_MUTATION = `
  mutation CancelOrder($id: ID!) {
    uiapi {
      Order__cUpdate(input: { Id: $id, Order__c: { Status__c: "Cancelled" } }) {
        Record { Id Status__c { value } }
      }
    }
  }
`;

const [cancelOrder, { loading: cancelling }] = useMutation(CANCEL_ORDER_MUTATION);

const onCancel = async (id: string) => {
  const { data, errors } = await cancelOrder({ variables: { id } });
  if (errors) showError(errors[0].message);
  else        refetch();
};
```

**Rules**:
- Never use raw `fetch` for org data — auth is unstable across deployment contexts and you'd lose Trust Layer features
- Variable types match GraphQL schema: use `ID` not `string` for record ids; the SDK validates
- Refetch on mutation success rather than optimistic updates unless you've measured the latency
- Errors come back in two places: `error` (network/auth) and per-mutation `errors[]` (business). Handle both
- Cache: queries are cached across the page; subsequent components hitting the same shape don't re-fetch

## RX-2: Platform-Aware Auth (React) {#rx-platform-auth}

The platform manages session, refresh tokens, and per-user credentials. React components inherit this — never roll your own.

```tsx
// DO
import { useUser } from '@salesforce/react/auth';

const { id, profile, locale } = useUser();
```

```tsx
// DO NOT
async function login() {
  const res = await fetch('/services/oauth2/token', { method: 'POST', body: '...' });
  // never works in production; security-fail in scratch orgs
}
```

**Rules**:
- `useUser()` returns the current platform session's user — same identity LWC's `@salesforce/user/Id` exposes
- Per-user OAuth (Named Credential with per-user mode) for components that need user-specific external auth — the GraphQL client honors this automatically
- Don't read or store auth tokens in React state. The SDK handles token rotation
- For components hosted on Experience Cloud / custom domain, the platform runtime injects the session via the `<head>` tag at server-side render time. Don't try to bypass

## RX-3: Deployment (React) {#rx-deployment}

React bundles deploy via `sf project deploy start` exactly like LWC. The platform builds the React tree at deploy time.

```bash
# Whole project
sf project deploy start --target-org "$ORG"

# Single component
sf project deploy start --target-org "$ORG" --source-dir force-app/main/default/react/OrderList

# Diff deploy via /argo:diff-deploy
/argo:diff-deploy --vs main
```

The deployable artifact is the source files plus a generated build manifest. The platform's React runtime serves the components like any other component metadata.

**Rules**:
- Don't pre-bundle (no Webpack / Vite output committed) — the platform builds at deploy time
- TypeScript is supported; the platform compiles `.tsx` to `.jsx` to `.js` server-side
- Third-party npm dependencies must be on the platform's allowlist (a curated subset of npm). React, ReactDOM, popular utility libs (lodash-es, date-fns, zod, @tanstack/react-virtual) are allowed; UI frameworks (Material UI, Chakra) typically are not
- Bundle size limits are enforced at deploy time — `/argo:perf-review` flags bundles approaching the limit before deploy

## RX-4: SLDS via React Tokens {#rx-slds-tokens}

Use the platform's SLDS bindings — don't import LWC's SLDS bundle.

```tsx
// DO
import { Card, Button, Spinner, Modal } from '@salesforce/react/slds-components';

<Card heading="Orders" iconCategory="standard" iconName="orders">
  <Button variant="brand" onClick={onAdd}>New</Button>
</Card>
```

```css
/* DO — SLDS tokens via CSS custom properties */
.list li {
  padding: var(--slds-g-spacing-medium);
  border-bottom: 1px solid var(--slds-g-color-border-base-1);
}

/* DO NOT — hardcoded values */
.list li {
  padding: 16px;
  border-bottom: 1px solid #ccc;
}
```

**Rules**:
- `@salesforce/react/slds-components` is the React-native binding of SLDS Lightning components. Same design tokens, same accessibility primitives, same theming hooks — just React idiomatic
- CSS Modules + SLDS custom properties for any component-specific styling
- Don't mix in another design system (Material UI, Chakra). It's expensive in bundle size and visually jarring against SLDS-styled neighbors
- Dark mode / theming: SLDS tokens flip automatically when the org's theme changes; don't hardcode colors

## RX-5: Internationalization (React) {#rx-i18n}

Mirror SF-18, but with React hooks. Custom Labels, locale-aware formatting, RTL support.

```tsx
import { useLabel, useLocale, useFormatter, useTimezone } from '@salesforce/react/i18n';

export function OrderRow({ order }: { order: Order }) {
  const labels = {
    title:    useLabel('Order_Title'),
    total:    useLabel('Order_Total'),
    placed:   useLabel('Order_Placed_At'),
  };
  const locale = useLocale();
  const tz = useTimezone();

  const fmtCurrency = useFormatter({
    style: 'currency',
    currency: order.currencyIsoCode,
  });
  const fmtDate = useFormatter({
    dateStyle: 'medium',
    timeZone: tz,
  });

  return (
    <article aria-label={labels.title}>
      <p>{labels.total}: {fmtCurrency.format(order.total)}</p>
      <p>{labels.placed}: {fmtDate.format(new Date(order.placedAt))}</p>
    </article>
  );
}
```

**Rules**:
- All user-visible strings via `useLabel('<Custom_Label_DeveloperName>')`. The Trust Layer can audit this
- Pluralization, dates, currency, percent: `useFormatter` (an `Intl.*` factory bound to the user's locale)
- RTL: SLDS tokens already encode logical directions; use logical CSS properties (`margin-inline-end`) instead of `margin-right` for any custom CSS
- Server-thrown errors from Apex are not auto-translated — pass a Custom Label DeveloperName from Apex (`throw new AuraHandledException(System.Label.Error_Code)`); React catches and resolves via `useLabel` on the client

## RX-6: LWC ↔ React Interop {#rx-lwc-react-interop}

For incremental migration or mixed UIs, the platform supports embedding each framework in the other.

### React inside LWC

```html
<!-- LWC HTML -->
<template>
  <lightning-react-host
      component="c/orderList"
      attrs={reactAttrs}
      onreactevent={handleReactEvent}>
  </lightning-react-host>
</template>
```

```js
// LWC JS
import { LightningElement } from 'lwc';
export default class HostingComponent extends LightningElement {
    reactAttrs = { pageSize: 50, status: 'OPEN' };
    handleReactEvent(event) {
        // event.detail carries the data the React component dispatched
    }
}
```

### LWC inside React

```tsx
import { LwcContainer } from '@salesforce/react/lwc-interop';

export function ReactPage() {
  return (
    <article>
      <h2>Orders</h2>
      <LwcContainer
        name="c/legacyOrderForm"
        attrs={{ recordId: orderId }}
        onLwcEvent={handleLwcEvent}
      />
    </article>
  );
}
```

**Rules**:
- Pass primitive attributes only (string, number, boolean). Complex objects don't survive the boundary cleanly
- Communication uses CustomEvents in both directions: React dispatches `new CustomEvent('reactEvent', { detail })`; LWC dispatches via `this.dispatchEvent(...)`
- Don't try to share state across the boundary. Each side owns its own state; the parent (LWC or React) is the source of truth
- Mixing is **transitional**, not architectural. Pick one framework per surface long-term — bundle-size cost and mental overhead don't go away

---

## Anti-patterns

- **Hand-rolled OAuth in React.** The platform manages auth; bypassing it doesn't work in production and breaks the Trust Layer
- **Material UI / Chakra / Bootstrap as the primary design system.** They fight SLDS. Pick SLDS or pick the other and accept losing Salesforce-native theming — but don't combine
- **Class components.** Not supported on the platform's React runtime
- **Pre-bundling source.** Don't commit `dist/` or `build/`; the platform builds at deploy time
- **Optimistic updates without measurement.** They're not free — invalidation logic adds bugs. Use them only when you've shown latency is unacceptable
- **State management libraries (Redux/Zustand) for everything.** Component-local state is fine for most things. Lift only when state is genuinely shared
