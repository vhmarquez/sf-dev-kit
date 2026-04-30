# Industries (OmniStudio) Pack

Patterns for **Salesforce Industries / OmniStudio** (the former Vlocity stack) — OmniScripts, FlexCards, Integration Procedures, DataRaptors, Enterprise Product Catalog (EPC), and the Apex extension surface.

## When to use this pack

Install with `/argo:pattern-pack add industries` if your project:
- Builds on top of Salesforce Industries (Communications, Media, Energy, Insurance, Health, Public Sector)
- Uses OmniStudio components for guided customer journeys, agent screens, or partner portals
- Configures product catalogs through EPC for industry-shaped CPQ
- Extends OmniStudio orchestrations with custom Apex classes via `omnistudio.VlocityOpenInterface`

Don't install for:
- Pure CRM / non-industries projects (base SF-1..20 patterns are enough)
- Projects using only the standard `Product2` / CPQ — the EPC patterns assume the industries-shaped catalog
- Cases where Lightning Flow / standard LWC would do — OmniStudio adds runtime overhead and a parallel author surface

## What's in the pack

- **IND-1: OmniScript Composition** — one journey per script, embedded scripts for reuse, no logic in JSON
- **IND-2: FlexCards for Read-Only Surfaces** — read-only display widgets; Card Actions for interactivity
- **IND-3: Integration Procedures (IPs)** — server-side orchestration, IP cache, REST exposure
- **IND-4: DataRaptors as the Data Layer** — Extract / Turbo / Transform / Load; one DR per shape
- **IND-5: Enterprise Product Catalog (EPC) and CPQ Integration** — source-controlled catalog, attribute-driven configuration
- **IND-6: Apex Extension and Test Coverage for OmniStudio** — `VlocityOpenInterface`, one `invokeMethod` per class, full coverage

Plus checklist items covering script decomposition, IP cache, DataRaptor sharing, EPC deploy hygiene, and Apex extension testing.

## What's not in the pack

- Vlocity DataPacks tooling — that's a deploy/migration concern, not a pattern
- Industry-specific objects (Communications-specific `vlocity_cmt__*`, Health-specific `vlocity_h__*`) — patterns are framework-level
- OmniStudio's deprecated tooling (Cards Framework v1, the legacy Vlocity action framework) — assumes the supported, platform-integrated surfaces

## Cross-references

- Base patterns: SF-7 (Trigger Handler — for triggers fired by OmniScript-driven DML), SF-9 (Wrapper / DTO Classes — for IP response shapes), SF-15 (Named Credentials — for IP HTTP actions)
- Specialist agents: `@apex-dev` for the extension layer, `@data-architect` for EPC modeling, `@architect` for journey decomposition

## References

- [OmniStudio Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.omnistudio_developer.meta/omnistudio_developer/)
- [Integration Procedures Reference](https://help.salesforce.com/s/articleView?id=sf.os_integration_procedures.htm)
- [DataRaptor Reference](https://help.salesforce.com/s/articleView?id=sf.os_dataraptors.htm)
- [`omnistudio.VlocityOpenInterface`](https://developer.salesforce.com/docs/atlas.en-us.omnistudio_apex_api.meta/omnistudio_apex_api/apex_VlocityOpenInterface.htm)
