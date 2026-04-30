### External Objects (Salesforce Connect)
- [ ] Adapter chosen explicitly (OData 4 / OData 2 / Cross-Org / Custom Apex) with rationale captured (EXT-1)
- [ ] Endpoint reached via Named Credential (SF-15) — no hardcoded URLs in the data source metadata
- [ ] Each `__x` object has exactly one external-id field; relationships use IndirectLookup or ExternalLookup, not standard Lookup (EXT-2)
- [ ] Live queries are guarded by callout governor budget; high-traffic UIs use `cacheable=true` plus Platform Cache (EXT-3)
- [ ] Writes use `as user` DML and handle `CalloutException` separately from `DmlException` (EXT-4)
- [ ] No External Object queries from `before` triggers (callouts forbidden there)
- [ ] Custom Apex Connectors honor only the capabilities they actually implement (EXT-5)
- [ ] Partial-failure path documented for transactions that touch both local and external objects
