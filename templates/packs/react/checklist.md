### React on Salesforce
- [ ] Function components only (no class components — RX-1)
- [ ] All org data via `@salesforce/react/graphql` `useQuery`/`useMutation`; no raw `fetch` (RX-1)
- [ ] No hand-rolled OAuth or session management — use `useUser()` and platform-managed auth (RX-2)
- [ ] CSS Modules for component styles; SLDS tokens (CSS custom properties) for colors/spacing; no hardcoded values (RX-4)
- [ ] All user-visible strings via `useLabel('<Custom_Label_DeveloperName>')` (RX-5)
- [ ] No design-system mixing (Material UI, Bootstrap) without an `/sf-dev-kit:adr`-recorded decision
- [ ] Tests cover four states minimum: loading, empty, error, populated (plus user interaction)
- [ ] LWC↔React interop only via `<lightning-react-host>` / `<LwcContainer>`; no shared state across the boundary (RX-6)
