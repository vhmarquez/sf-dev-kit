## DC-1: Data Streams and Data Lake Objects {#dc-streams}

A **Data Stream** ingests data into Data Cloud — from Salesforce CRM (CRM connector), an S3 bucket, an Ingestion API, or another Connector. The stream lands raw rows in a **Data Lake Object (DLO)**: schema-on-write, separate from your CRM data, queryable but not directly mappable to standard objects until it's promoted to a Data Model Object (DC-2).

```text
┌──────────────────┐    ingest    ┌─────────┐   map   ┌──────────────────┐
│  Source system    │  ─────────►  │   DLO   │ ──────► │      DMO         │
│  (S3 / API / CRM) │              │ (raw)   │         │  (harmonized)    │
└──────────────────┘              └─────────┘         └──────────────────┘
```

Author streams as metadata where possible (SF supports it for the most common connectors); fall back to the Data Cloud setup UI for sources that aren't yet metadata-backed.

```yaml
# Conceptual — per-org the exact metadata XML is connector-specific
dataStream:
  name: ERP_Orders_Stream
  sourceConnector: AmazonS3
  bucket: erp-events-prod
  prefix: orders/
  refreshFrequency: PT1H        # ISO-8601 duration; hourly
  dlo:
    name: ERP_Orders_DLO
    primaryKey: order_id
    timestampField: event_time
    fields:
      - { name: order_id,    type: text,     length: 100, primaryKey: true }
      - { name: customer_id, type: text,     length: 100 }
      - { name: total,       type: number,   precision: 18, scale: 2 }
      - { name: event_time,  type: dateTime, timestampField: true }
```

**Rules**:
- **Pick the right connector for the source.** CRM Connector is real-time-ish (CDC under the hood); S3 / SFTP / API connectors are batch. Don't use a polling REST connector for high-volume sources — use the Ingestion API
- **DLO is raw.** Don't reshape data at the DLO layer; do it in the DMO mapping or via Data Transforms (DC-3)
- **Primary key + timestamp field are mandatory** for upserts to work; missing them produces append-only DLOs with no dedup
- **Refresh cadence is per-source.** Match it to source freshness — hourly for steady-state, daily for batch loads. Sub-hourly costs more
- **DLOs are columnar storage.** Wide tables work; small frequent updates don't. Design for analytical access patterns

## DC-2: Data Model Objects and Identity Resolution {#dc-dmo-identity}

A **Data Model Object (DMO)** is the harmonized, semantically-typed shape — Customer, Order, Engagement. Multiple DLOs can map into the same DMO; that's how Data Cloud unifies records from different sources. **Identity Resolution** rules then collapse rows referring to the same real-world person across DLOs into a **Unified Individual**.

```text
DLO: ERP_Orders                                ┐
DLO: Web_Orders         ──── DMO: Order ◄──────┤
DLO: POS_Orders                                ┘
                                  │
                            (FK on customer_id)
                                  ▼
DLO: ERP_Customers                             ┐
DLO: Web_Profiles      ──── DMO: Individual ◄──┤  ──► Identity Resolution
DLO: Loyalty_Members                           ┘   (match: email | phone | hashed_id)
```

Identity resolution runs as a scheduled job; the result is a `Unified Link` table that maps source-system ids to a single Unified Id you query against.

**Rules**:
- **Map every DLO to at least one DMO before relying on it for activation.** Unmapped DLOs are queryable but invisible to segments and calculated insights
- **Identity rules are precision/recall trade-offs.** Tighten match criteria (exact email + name) for high-precision, loosen for recall. Pick per use case
- **Don't run identity resolution on insufficient match keys.** Email-only matching collapses spousal accounts; layer at least two keys
- **Hashed identifiers preserve privacy.** Use SHA-256 hashed email/phone for matching when source DLOs include hashes; the rule still resolves them
- **Unified Individual is canonical.** Downstream queries should join through Unified Link, not back to source DLOs, to avoid double-counting

## DC-3: Calculated Insights and Segments {#dc-insights-segments}

**Calculated Insights** are scheduled SQL queries that produce derived metrics per DMO row (lifetime value, churn risk, last-90-day visit count). **Segments** are filters on DMOs (with insights joined in) that produce activation-eligible audience sets. Both are metadata-backed and source-controlled.

```sql
-- calculatedInsights/Customer_LTV.calculatedInsight-meta.xml (conceptual SQL)
SELECT
    Individual__dlm.UnifiedRecordId__c     AS unifiedId,
    SUM(Order__dlm.Total__c)               AS lifetime_value,
    MAX(Order__dlm.Order_Date__c)          AS last_order_date,
    COUNT(Order__dlm.Id__c)                AS order_count
FROM Individual__dlm
JOIN Order__dlm ON Order__dlm.Customer__c = Individual__dlm.UnifiedRecordId__c
WHERE Order__dlm.Order_Date__c >= TIMESTAMPADD(DAY, -730, CURRENT_TIMESTAMP)
GROUP BY Individual__dlm.UnifiedRecordId__c;
```

```yaml
# segments/High_Value_At_Risk.segment-meta.xml (conceptual)
segment:
  name: High_Value_At_Risk
  baseDmo: Individual
  filters:
    - field: lifetime_value           # from Customer_LTV insight
      operator: greaterThanOrEqual
      value: 5000
    - field: last_order_date
      operator: lessThan
      value: !relativeDate { days: -90 }
  refreshFrequency: PT4H
```

**Rules**:
- **Calculated Insights run on a schedule, not in real-time.** A "current LTV" insight is current-as-of-last-run; design refresh cadence around when downstream segments need it
- **Segments are evaluated on activation.** Activation systems (Marketing Cloud, ad platforms) consume the audience as of the last segment refresh, not the moment of activation
- **Push expensive joins into insights.** Segments with multi-DMO joins are slow at activation time; pre-compute the join in an insight, then segment on the result
- **Don't bypass the DMO for segmentation.** Segments must filter DMOs (or DMO-shaped insights), not raw DLOs. Going around the DMO loses identity resolution
- **Source-control insights and segments.** Both have metadata XML; commit them and review like any other metadata change

## DC-4: Activation to External Systems {#dc-activation}

**Activations** push segment audiences to external systems — Marketing Cloud, Google Ads, Meta, custom webhooks. Each activation has a **target** (the connected destination), an **attribute mapping** (which DMO fields to send), and a **schedule** or trigger model.

```yaml
# activations/Send_HVAR_To_MC.activation-meta.xml (conceptual)
activation:
  name: Send_HVAR_To_MC
  segment: High_Value_At_Risk
  target:
    type: MarketingCloud
    namedCredential: MC_Hub_Prod
    dataExtension: HVAR_Audience
  attributes:
    - { dmoField: Email__c,       targetField: Email,        encrypt: false }
    - { dmoField: First_Name__c,  targetField: FirstName,    encrypt: false }
    - { dmoField: lifetime_value, targetField: LTV,          encrypt: false }
  schedule:
    cron: "0 6 * * *"             # daily at 06:00 UTC
    incremental: true             # only changed rows since last activation
```

**Rules**:
- **Use Named Credentials for activation auth.** Never embed API keys in activation metadata
- **Incremental activation is cheaper.** Full-segment refresh on every run pumps duplicates downstream; opt into incremental unless the target requires full audiences
- **Map the minimum useful field set.** Every attribute mapped is data leaving Salesforce; respect the principle of least privilege
- **Coordinate cadence with the target.** Marketing Cloud has its own send windows; activating into a quiet window is wasted work
- **Suppression lists matter.** Always include an activation-side suppression DMO (do-not-contact, hard-bounce) and apply before the export

## DC-5: Querying Data Cloud from Apex / Agents {#dc-query-apex}

Data Cloud is queryable from Apex via the **Data Cloud SQL API** (Connect REST endpoint) — not standard SOQL. Tables are `<DMO>__dlm` for DMOs and `<DLO>__dll` for raw DLOs; the dialect is ANSI SQL with Data Cloud extensions for time travel and identity-link joins.

```apex
public with sharing class DataCloudQueryClient {

    /** Run a Data Cloud SQL query and return parsed rows. */
    public static List<Map<String, Object>> sql(String sqlText) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Data_Cloud_API/api/v1/query');  // Named Credential
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String, Object>{ 'sql' => sqlText }));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new CalloutException('Data Cloud query failed: ' + res.getBody());
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (List<Map<String, Object>>) body.get('data');
    }

    /** Read the lifetime-value insight for a unified individual. */
    public static Decimal getLtv(Id unifiedId) {
        String sql =
            'SELECT lifetime_value FROM Customer_LTV__cio ' +
            'WHERE UnifiedRecordId__c = ' + JSON.serialize(unifiedId) + ' LIMIT 1';
        List<Map<String, Object>> rows = sql(sql);
        return rows.isEmpty() ? null : (Decimal) rows[0].get('lifetime_value');
    }
}
```

For agent actions, expose this as an MCP tool (see SF-16 + AGT-4) so an Agentforce agent can ground responses against Data Cloud insights. Always honor `WITH USER_MODE` semantics — Data Cloud has its own permission model (Data Spaces, Data Cloud Permission Sets) that must be configured on the Connected App / running user.

**Rules**:
- **Always Named Credential for Data Cloud auth.** Like any callout
- **Cache calculated insights aggressively when read from agents.** They refresh on a schedule; agents reading them on every request multiply load unnecessarily
- **Use the SQL API, not SOQL.** Standard SOQL on `__dlm` tables is limited; SQL API supports joins, aggregations, time travel
- **Respect Data Spaces.** A query running in Data Space A can't see Data Space B; the Connected App's data-space binding determines access
- **Cap query response size.** A `SELECT *` against a billion-row DMO is a way to time out the callout. Always project narrowly and `LIMIT`

---

## Anti-patterns

- **Skipping DMO mapping and querying DLOs directly.** Loses identity resolution; downstream segments and insights become noisy
- **Using polling REST as the ingest path for high-volume sources.** Hits source-system rate limits and lags. Use Ingestion API or the source-native connector
- **Identity resolution on email alone.** Collapses households into single individuals. Always layer at least two match keys
- **Real-time-shaped UIs over Calculated Insights.** Insights refresh on a schedule; expecting per-second freshness produces stale UI
- **Activating without a suppression list.** Hard-bounce and unsubscribed addresses leak through; downstream systems penalize the sender
- **Embedding Data Cloud API credentials in activation metadata.** Always Named Credential; rotate via the auth provider
- **Cross-Data-Space queries assuming visibility.** Each Data Space is a permission boundary; the running user / Connected App must be authorized for both spaces
- **Using Data Cloud as a source-of-truth for transactional data.** It's an analytical / activation surface — CRM remains canonical for transactional records
