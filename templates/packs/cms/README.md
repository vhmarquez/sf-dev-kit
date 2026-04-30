# Salesforce CMS Pack

Patterns for **Salesforce CMS** — content types, workspaces, channels, multi-locale variants, and headless content delivery to Experience Cloud and external surfaces.

## When to use this pack

Install with `/argo:pattern-pack add cms` if your project:
- Authors marketing or external-facing content with a non-developer team
- Publishes content to multiple surfaces (Experience site, mobile app, partner portal, marketing pages) from one source
- Ships content in multiple locales
- Delivers content headless to non-Salesforce surfaces via the Connect Delivery API

Don't install for:
- Self-service support knowledge bases (Knowledge is the better surface)
- Record-attached documents (Files is the simpler product)
- Pure marketing automation (Marketing Cloud has its own content authoring)

## What's in the pack

- **CMS-1: Custom Content Types** — `ManagedContentType` metadata, supported node types, when to split a type
- **CMS-2: Workspaces, Channels, and Publishing** — editorial vs. delivery layers, programmatic publish via ConnectApi
- **CMS-3: Multi-Locale Variants** — variant lifecycle, locale negotiation in LWC via `@salesforce/i18n/lang`
- **CMS-4: Headless Delivery via Connect REST** — Delivery API, CDN caching, Connected App auth
- **CMS-5: CMS vs Knowledge vs Files** — picking the right surface, why duplication leads to drift

Plus checklist items covering content-type design, publish-context safety, locale negotiation, headless caching, and surface choice.

## What's not in the pack

- Knowledge article authoring — different product, different lifecycle
- Files / Attachments — see base SF patterns for record-scoped attachments
- Marketing Cloud Personalization / Journey Builder content — separate domain

## Cross-references

- Base patterns: SF-15 (Named Credentials — for headless tokens), SF-18 (LWC Internationalization)
- Companion packs: `react` (RX-1..6 — when delivering CMS to React-on-Salesforce surfaces)
- Specialist agents: `@lwc-dev` and `@react-dev` for the rendering layer

## References

- [Salesforce CMS documentation](https://help.salesforce.com/s/articleView?id=sf.community_managed_content_overview.htm)
- [`ManagedContentType` metadata reference](https://developer.salesforce.com/docs/atlas.en-us.api_meta.meta/api_meta/meta_managedcontenttype.htm)
- [Connect REST API for Managed Content](https://developer.salesforce.com/docs/atlas.en-us.chatterapi.meta/chatterapi/connect_resources_managed_content.htm)
