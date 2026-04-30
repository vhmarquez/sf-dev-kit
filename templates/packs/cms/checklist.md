### Salesforce CMS
- [ ] One `ManagedContentType` per distinct content shape; no overloaded types (CMS-1)
- [ ] Reference data lives in sObjects, not CMS — content holds the rendered version, sObjects hold the master record
- [ ] Publishing happens from a Queueable / after-commit context; never from a `before` trigger (CMS-2)
- [ ] Per-channel publish state honored — content can be live in one channel and draft in another
- [ ] Multi-locale variants honor `@salesforce/i18n/lang` for locale negotiation; client never hardcodes a locale (CMS-3)
- [ ] Headless consumers use the Connect Delivery API, not the authoring API (CMS-4)
- [ ] Connected App tokens are never exposed client-side; an external proxy handles auth
- [ ] Public traffic is cached at a real CDN; CMS endpoints are not load-bearing for high-throughput reads
- [ ] Content surface chosen deliberately (CMS vs. Knowledge vs. Files) and documented in an ADR (CMS-5)
