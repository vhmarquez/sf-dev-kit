---
name: react-init
description: Scaffold a React-on-Salesforce component bundle at paths.reactSource. Generates .tsx + .module.css + .meta.xml + .test.tsx + index.ts following the project's React conventions, with `@salesforce/react/graphql` data fetching and SLDS tokens baked in.
---

You are scaffolding a React component bundle. Output goes to `<paths.reactSource>/<ComponentName>/`. Files generated: implementation, styles, meta XML, tests, public index, doc stub.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
REACT_SRC="$(sf_config_get '.paths.reactSource // \"force-app/main/default/react\"' "$ENV")"
REACT_DOCS="$(sf_config_get '.paths.reactDocs // \"docs/react\"' "$ENV")"
PREFIX="$(sf_config_get '.naming.react.prefix // empty' "$ENV")"
API_VERSION="$(sf_config_get '.platform.apiVersion' "$ENV")"
FRONTEND="$(sf_config_get '.platform.frontend // \"lwc\"' "$ENV")"

case "$FRONTEND" in
  *react*) ;;
  *) echo "[react-init] Project's platform.frontend does not include 'react'. Run: /sf-dev-kit:sf-init update platform.frontend"; exit 2 ;;
esac
```

## Input

`$ARGUMENTS`:
- `<ComponentName>` — required; PascalCase. Skill applies `naming.react.prefix` if set
- `--type page|panel|widget` — page (lightning__AppPage target), panel (LightningModalContent), widget (lightning__RecordPage). Default `page`
- `--lang ts|js` — TypeScript (default) or JavaScript
- `--no-graphql` — skip the GraphQL hook scaffolding (for components that don't read data)
- `--with-test` — also scaffold the test file (default true; `--no-test` to opt out)
- `--ci` — non-interactive

## Steps

### 1. Resolve and validate

```bash
if [[ -n "$PREFIX" ]] && [[ ! "$NAME" =~ ^${PREFIX} ]]; then
  NAME="${PREFIX}${NAME}"
fi
DIR="${REACT_SRC}/${NAME}"
[[ -d "$DIR" ]] && [[ "$FORCE" != "1" ]] && { echo "[react-init] ${DIR} exists; pass --force to overwrite"; exit 1; }
mkdir -p "$DIR"
```

### 2. Generate `<Name>.tsx`

```tsx
import { useQuery } from '@salesforce/react/graphql';
import { useLabel, useLocale, useFormatter } from '@salesforce/react/i18n';
import { Card, Button } from '@salesforce/react/slds-components';
import styles from './<Name>.module.css';

const ORDERS_QUERY = `
  query Orders($limit: Int!) {
    uiapi {
      query {
        Order__c(first: $limit, orderBy: { CreatedDate: { order: DESC } }) {
          edges {
            node {
              Id
              Name { value }
              Status__c { value }
              Total_Amount__c { value }
            }
          }
        }
      }
    }
  }
`;

export interface <Name>Props {
  pageSize?: number;
}

export function <Name>({ pageSize = 25 }: <Name>Props) {
  const labels = {
    title: useLabel('Order_List_Title'),
    empty: useLabel('No_Orders_Found'),
    error: useLabel('Order_List_Error'),
  };
  const locale = useLocale();
  const formatCurrency = useFormatter({ style: 'currency' });

  const { data, loading, error } = useQuery(ORDERS_QUERY, {
    variables: { limit: pageSize },
  });

  if (loading) return <Card><p>{useLabel('Loading')}</p></Card>;
  if (error) return <Card><p className={styles.error}>{labels.error}</p></Card>;

  const orders = data?.uiapi.query.Order__c.edges ?? [];
  if (orders.length === 0) return <Card><p>{labels.empty}</p></Card>;

  return (
    <Card heading={labels.title}>
      <ul className={styles.list}>
        {orders.map(({ node }) => (
          <li key={node.Id}>
            <span>{node.Name.value}</span>
            <span>{node.Status__c.value}</span>
            <span>{formatCurrency.format(node.Total_Amount__c.value)}</span>
          </li>
        ))}
      </ul>
    </Card>
  );
}

export default <Name>;
```

(Substitute `<Name>` with the actual component name. The GraphQL query is illustrative — the user adapts to their own object/fields. If `--no-graphql`, omit the `useQuery` block.)

### 3. Generate `<Name>.module.css`

```css
.list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.list li {
  display: grid;
  grid-template-columns: 1fr auto auto;
  gap: var(--slds-g-spacing-medium);
  padding: var(--slds-g-spacing-x-small) var(--slds-g-spacing-medium);
  border-bottom: 1px solid var(--slds-g-color-border-base-1);
}

.error {
  color: var(--slds-g-color-error-base-50);
}
```

### 4. Generate `<Name>.meta.xml`

Pick targets based on `--type`:
- `page` → `lightning__AppPage`, `lightning__HomePage`
- `panel` → `lightning__AppPage` only
- `widget` → `lightning__RecordPage`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ReactComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>{{API_VERSION}}</apiVersion>
    <isExposed>true</isExposed>
    <masterLabel>{{Master Label}}</masterLabel>
    <description>{{One-sentence purpose}}</description>
    <targets>
        <target>lightning__AppPage</target>
        <target>lightning__HomePage</target>
    </targets>
</ReactComponentBundle>
```

### 5. Generate `<Name>.test.tsx` (unless `--no-test`)

```tsx
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { <Name> } from './<Name>';

vi.mock('@salesforce/react/graphql', () => ({
  useQuery: vi.fn(),
}));
vi.mock('@salesforce/react/i18n', () => ({
  useLabel: (name: string) => name,
  useLocale: () => 'en-US',
  useFormatter: () => ({ format: (v: unknown) => String(v) }),
}));
vi.mock('@salesforce/react/slds-components', () => ({
  Card: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  Button: (props: React.ButtonHTMLAttributes<HTMLButtonElement>) => <button {...props} />,
}));

import { useQuery } from '@salesforce/react/graphql';

describe('<Name>', () => {
  beforeEach(() => {
    vi.mocked(useQuery).mockReset();
  });

  it('renders loading state', () => {
    vi.mocked(useQuery).mockReturnValue({ loading: true, data: undefined, error: undefined } as never);
    render(<<Name> />);
    expect(screen.getByText('Loading')).toBeDefined();
  });

  it('renders empty state when no orders', () => {
    vi.mocked(useQuery).mockReturnValue({
      loading: false,
      data: { uiapi: { query: { Order__c: { edges: [] } } } },
      error: undefined,
    } as never);
    render(<<Name> />);
    expect(screen.getByText('No_Orders_Found')).toBeDefined();
  });

  it('renders error state when query fails', () => {
    vi.mocked(useQuery).mockReturnValue({
      loading: false,
      data: undefined,
      error: new Error('Network'),
    } as never);
    render(<<Name> />);
    expect(screen.getByText('Order_List_Error')).toBeDefined();
  });

  it('renders order list', () => {
    vi.mocked(useQuery).mockReturnValue({
      loading: false,
      data: {
        uiapi: { query: { Order__c: { edges: [
          { node: { Id: 'a01', Name: { value: 'Order 1' }, Status__c: { value: 'OPEN' }, Total_Amount__c: { value: 42 } } },
        ] } } },
      },
      error: undefined,
    } as never);
    render(<<Name> />);
    expect(screen.getByText('Order 1')).toBeDefined();
    expect(screen.getByText('OPEN')).toBeDefined();
  });
});
```

### 6. Generate `index.ts`

```ts
export { <Name> } from './<Name>';
export type { <Name>Props } from './<Name>';
export { default } from './<Name>';
```

### 7. Generate doc stub

`<paths.reactDocs>/<Name>.md`:
```markdown
# <Name>

(One-sentence purpose.)

## Props

| Name | Type | Default | Purpose |
|------|------|---------|---------|
| `pageSize` | `number` | `25` | Page size for the orders query |

## Data

Reads `Order__c` via the platform GraphQL surface. Honors FLS automatically.

## Targets

- `lightning__AppPage`
- `lightning__HomePage`
```

Update `<paths.reactDocs>/README.md` index.

### 8. Output

```
[react-init] Scaffolded force-app/main/default/react/OrderList/

  OrderList.tsx               (with @salesforce/react/graphql + i18n hooks)
  OrderList.module.css        (SLDS tokens, CSS Modules)
  OrderList.meta.xml          (API 66.0, exposed, lightning__AppPage)
  OrderList.test.tsx          (4 cases: loading, empty, error, list)
  index.ts                    (public exports)
  docs/react/OrderList.md     (doc stub; index updated)

## Suggested next steps
- Adapt the GraphQL query to the right object/fields for your use case
- Add the labels Order_List_Title / No_Orders_Found / Order_List_Error / Loading via Setup → Custom Labels (or include them in the deploy)
- Run `npm run test:react -- OrderList` to verify the test scaffolding works
- Hand off to @react-dev for any non-trivial logic
```

CI mode JSON: `{"name":"OrderList","path":"force-app/main/default/react/OrderList","files":[...]}`.

## Exit codes
- 0 — scaffolded
- 1 — directory exists (use `--force`)
- 2 — config error / `platform.frontend` doesn't include react

## Rules

- **Don't scaffold over an existing component without `--force`.** Avoid clobber
- **Honor the project's TypeScript/JavaScript choice.** Detect from existing files in `paths.reactSource`; default TS for new projects
- **Don't fabricate Custom Labels.** The scaffold references labels by Custom Label DeveloperName; the user creates them in the org
- **Test mocks should match what the runtime ships.** When `@salesforce/react/*` modules change, this skill's scaffolding template needs to keep up
