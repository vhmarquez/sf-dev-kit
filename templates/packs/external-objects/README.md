# External Objects (Salesforce Connect) Pack

Patterns for **External Objects via Salesforce Connect** — virtual `__x` objects that resolve their data live from external systems (OData 4, another Salesforce org, or a custom Apex connector) without replicating it into the org.

## When to use this pack

Install with `/argo:pattern-pack add external-objects` if your project:
- Surfaces ERP / billing / inventory / order data live, without ETL into Salesforce
- Federates data across multiple Salesforce orgs (cross-org reporting, M&A integration period)
- Wraps a non-standard external system (SOAP, REST, gRPC) in a Salesforce-native interface
- Needs the data to remain live (transactional reads) rather than nightly-synced

Don't install for:
- Small, slow-changing reference data (just sync it via Bulk API into a custom object)
- High-throughput write workloads (External Objects writes are not transactional with local DML)
- Data the agent / LWC needs sub-second response on (every read is a callout)

## What's in the pack

- **EXT-1: Picking the Adapter** — OData 4 vs OData 2 vs Cross-Org vs Custom Apex Connector
- **EXT-2: Defining the External Object and Sync Schema** — `__x` metadata, External Id, Indirect Lookup, External Lookup
- **EXT-3: Apex Querying with Pagination and Caching** — callout cost model, `cacheable=true`, Platform Cache
- **EXT-4: Writes and Write-Back Semantics** — DML on `__x`, partial failure with local DML, `CalloutException` vs `DmlException`
- **EXT-5: Custom Apex Connector for Non-OData Sources** — `DataSource.Connection` + `DataSource.Provider`, capability declaration

Plus checklist items covering Named Credential use, indirect-lookup design, callout-budget guarding, and partial-failure handling.

## What's not in the pack

- Bulk-loading / ETL-style sync — that's a project decision, not Salesforce Connect
- OData service authoring for non-Salesforce systems — that's an external concern

## Cross-references

- Base patterns: SF-15 (HTTP Callout via Named Credential), SF-9 (Wrapper / DTO Classes)
- Specialist agents: `@integration-architect` for adapter choice, `@apex-dev` for the connector implementation
- Companion packs: `data-cloud` (when external data should also flow into the harmonized profile), `change-data-capture` (CDC subscribers can fan out into external writes)

## References

- [Salesforce Connect documentation](https://help.salesforce.com/s/articleView?id=sf.platform_connect_about.htm)
- [`DataSource.Connection` reference](https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_class_DataSource_Connection.htm)
- [OData 4.0 specification](https://www.odata.org/documentation/)
