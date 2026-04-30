## IND-1: OmniScript Composition {#ind-omniscript}

**OmniScripts** are the wizard / multi-step UI runtime in OmniStudio. Each script is a JSON tree of steps and elements, deployed as `OmniProcess` metadata. Compose for reuse — a complex flow is a top-level OmniScript that calls smaller, single-purpose **embedded OmniScripts** (one per logical phase).

```json
// conceptual shape — actual XML/JSON varies per platform release
{
  "Name": "Telco_New_Activation",
  "Type": "OmniScript",
  "SubType": "Telco",
  "Language": "English",
  "Children": [
    { "Type": "Step", "Name": "Customer_Lookup", "Children": [
        { "Type": "DataRaptorExtractAction", "Name": "Get_Customer", "extractDataRaptor": "Telco_Customer_Get" },
        { "Type": "TypeaheadBlock", "Name": "Customer_Search", "remoteAction": "Telco_Customer_Search_IP" }
    ]},
    { "Type": "Step", "Name": "Plan_Selection", "Children": [
        { "Type": "OmniScript", "Name": "Embedded_Plan_Picker", "elementType": "EmbeddedScript",
          "Properties": { "type": "Telco", "subType": "PlanPicker", "language": "English" }
        }
    ]},
    { "Type": "IntegrationProcedureAction", "Name": "Submit_Order", "integrationProcedureKey": "Telco_OrderSubmit" }
  ]
}
```

**Rules**:
- **One OmniScript = one user journey.** Don't pack two unrelated flows into one script using conditionals
- **Embed for reuse.** A Plan Picker used in three places is one embedded script, not three copies
- **Steps are the visible boundary.** Each step is a navigable screen; UI granularity should match step granularity
- **Don't put logic in the JSON.** Use Integration Procedures (IND-3) and DataRaptors (IND-4) for data fetch/save; OmniScripts orchestrate UI + user input
- **Language is per-script.** Multi-language journeys ship one OmniScript per locale, sharing IPs and DataRaptors

## IND-2: FlexCards for Read-Only Surfaces {#ind-flexcard}

**FlexCards** are read-only, data-bound widgets — typically embedded on a record page or in another OmniScript step to show summary data. They consume DataRaptor or Integration Procedure output and render via configurable templates. Cheaper than LWC for purely-display use cases.

```json
// conceptual FlexCard definition
{
  "Name": "Customer_360_Summary",
  "Type": "Card",
  "DataSource": {
    "type": "Integration Procedure",
    "value": "Telco_Customer360_IP"
  },
  "Layout": "Grid",
  "Sections": [
    { "Title": "Account", "Fields": ["AccountName", "Industry", "AnnualRevenue"] },
    { "Title": "Recent Orders", "Type": "ChildCard", "ChildCardName": "Customer_Recent_Orders" }
  ]
}
```

**Rules**:
- **FlexCards are display, not edit.** For input surfaces, use OmniScript or LWC; FlexCards forward state changes only via Card Actions
- **Use parent/child cards for nested data.** A 1:N relationship renders cleanly as a parent FlexCard with a child-card list
- **Choose the data source by latency.** DataRaptor for in-org data (low latency); Integration Procedure for anything that needs orchestration or callouts
- **Card Actions, not custom JS.** When the user interacts with a FlexCard, route through Card Actions (open OmniScript, navigate, fire event); avoid inline custom JS
- **One FlexCard per shape.** Don't reuse a card for two unrelated record contexts via conditionals; ship two cards

## IND-3: Integration Procedures (IPs) {#ind-integration-procedure}

**Integration Procedures** are server-side orchestration: fetch from N sources, transform, return. Authored as JSON (`OmniProcess` of subtype `IntegrationProcedure`) and called from OmniScripts, FlexCards, REST clients, or Apex. Build IPs over Apex when the orchestration is declarative; reach for Apex when logic gets complex.

```json
// conceptual IP shape
{
  "Name": "Telco_Customer360_IP",
  "Type": "IntegrationProcedure",
  "SubType": "Telco",
  "Children": [
    { "Type": "DataRaptorExtractAction",  "Name": "Get_Account",    "extractDataRaptor": "Telco_Account_Get" },
    { "Type": "RemoteAction",             "Name": "Get_OpenOrders", "RemoteAction": "TelcoOrdersHelper.getOpenOrders" },
    { "Type": "ResponseAction",           "Name": "Compose_Response",
      "ResponseTemplate": {
        "account":   "%Get_Account%",
        "orders":    "%Get_OpenOrders%",
        "loadedAt":  "%CURRENT_DATETIME%"
      }
    }
  ]
}
```

```apex
// Calling an IP from Apex
public class CustomerSummaryService {
    public static Map<String, Object> get360(Id accountId) {
        Map<String, Object> input  = new Map<String, Object>{ 'accountId' => accountId };
        Map<String, Object> options = new Map<String, Object>{ 'chainable' => false };
        return (Map<String, Object>) omnistudio.IntegrationProcedureService.runIntegrationService(
            'Telco_Customer360_IP', input, options
        );
    }
}
```

**Rules**:
- **Cache reads at the IP level.** An IP that calls 4 DataRaptors should cache the read steps via the IP cache option, not at each DR
- **Don't put business logic in IPs.** IPs orchestrate; logic belongs in DataRaptors (data shape) or Apex (algorithms). IP conditionals should be data-driven, not branch-heavy
- **Chain IPs deliberately.** A "supersized" IP with 30 steps is brittle; decompose into per-domain IPs and chain
- **REST exposure goes through Industries REST endpoints, not Apex REST.** Use `/services/apexrest/v1/integrationprocedures/<key>/<name>` rather than re-wrapping
- **Test IPs with the OmniStudio simulator.** Each IP has a built-in test harness; document the canonical test inputs in the IP's notes block

## IND-4: DataRaptors as the Data Layer {#ind-dataraptor}

**DataRaptors** are declarative SOQL/DML wrappers — Extract (read), Transform (reshape), Load (write), Turbo (high-performance read). Author as `OmniDataTransform` metadata. Use DataRaptors as the canonical data layer; Apex stays for logic that DataRaptors can't express.

```text
DataRaptor Type    | Use case
-------------------+--------------------------------------------------------
Extract            | SOQL → JSON tree (with formula transforms inline)
Turbo Extract      | High-throughput SOQL → JSON; no formulas; faster
Transform          | JSON ↔ JSON; no SOQL; for reshaping IP state
Load               | JSON → DML (insert/update/upsert) on standard sObjects
```

```yaml
# conceptual: Telco_Account_Get DataRaptor (Extract)
extract:
  primaryObject: Account
  filter:
    field: Id
    operator: =
    value: "{accountId}"           # IP / OmniScript variable
  fields:
    - { source: Id,             target: id }
    - { source: Name,           target: name }
    - { source: Industry,       target: industry }
    - { source: AnnualRevenue,  target: annualRevenue }
  related:
    - object: Contact
      relationship: Contacts
      fields:
        - { source: FirstName, target: firstName }
        - { source: LastName,  target: lastName }
        - { source: Email,     target: email }
```

**Rules**:
- **Turbo Extract for hot reads.** Detail pages and search results benefit; Turbo skips the formula stage so write reusable extracts in plain Extract and ship Turbo variants for performance-critical paths
- **One DataRaptor per shape, not per caller.** A DR is reusable; copying for "this IP needs 3 fewer fields" creates drift
- **Run with `WITH USER_MODE` semantics.** DataRaptors honor sharing by default; explicit `Without Sharing` toggle requires justification
- **Don't load PII through Extract DataRaptors without masking.** If the consumer is a customer-facing OmniScript, mask sensitive fields at the DR layer
- **Validate Load input.** Load DRs are write-anything-the-caller-sends — author validation rules in the DR or in a wrapping IP, not in the consumer

## IND-5: Enterprise Product Catalog (EPC) and CPQ Integration {#ind-epc}

**EPC** models products, attributes, rules, and offers for industries-shaped catalogs (Telco, Insurance, Energy). The product graph drives both CPQ (Configure-Price-Quote) and Order Management. EPC objects are platform sObjects (`Product2` extended, `vlocity_cmt__ProductChildItem__c`, etc.); the trick is keeping the catalog source-controlled.

```text
Product2 (root)
   ├── ChildProduct (composition)        — bundles
   ├── AttributeAssignment              — configurable options
   ├── ProductRelationship              — promotions, dependencies
   ├── PricingPlan                      — list / discount / promo
   └── EligibilityRule                  — who can buy this offer
```

**Rules**:
- **Source-control the catalog.** EPC objects are exportable as metadata via DataPacks or the standard metadata API for `Product2`-shaped content. Treat them like any other deploy-managed config
- **Don't mass-edit in production.** Product changes ripple through orders mid-lifecycle. Stage in a sandbox, snapshot, deploy
- **Attribute-driven configuration over per-product Apex.** A "Telco Plan with optional roaming add-on" is an attribute, not three separate Product2 rows
- **Promotions are time-bounded.** Always set `EffectiveDate` / `ExpirationDate` on promotional pricing plans; expired promotions clutter quote pickers
- **Rules engine, not Apex.** EligibilityRule and AdvancedRule cover most of "show this offer if X"; reach for Apex extension only when the rule can't be expressed declaratively

## IND-6: Apex Extension and Test Coverage for OmniStudio {#ind-apex-extension}

OmniStudio supports custom Apex classes called from IPs (`RemoteAction`) and OmniScripts (`Custom`). The pattern: keep extension classes thin, with a single public method that takes the IP/Script context and returns a result. Test like any other Apex — but mock the OmniStudio framework calls.

```apex
global with sharing class TelcoOrdersHelper implements omnistudio.VlocityOpenInterface {

    /** Single entry point — IP step calls invokeMethod with methodName + input/options/output. */
    global Boolean invokeMethod(
        String methodName,
        Map<String, Object> input,
        Map<String, Object> output,
        Map<String, Object> options
    ) {
        try {
            switch on methodName {
                when 'getOpenOrders' {
                    Id accountId = (Id) input.get('accountId');
                    output.put('orders', fetchOpenOrders(accountId));
                    return true;
                }
                when else {
                    output.put('error', 'Unknown method: ' + methodName);
                    return false;
                }
            }
        } catch (Exception e) {
            Logger.log('TelcoOrdersHelper.' + methodName + ': ' + e);
            output.put('error', e.getMessage());
            return false;
        }
    }

    private List<Map<String, Object>> fetchOpenOrders(Id accountId) {
        // domain logic — testable in isolation
        return Order_Repository.openByAccount(accountId);
    }
}
```

```apex
@isTest
private class TelcoOrdersHelperTest {
    @isTest
    static void getOpenOrders_returnsList() {
        Account a = TestData.account(); insert a;
        TestData.openOrdersFor(a, 3);

        Map<String, Object> input  = new Map<String, Object>{ 'accountId' => a.Id };
        Map<String, Object> output = new Map<String, Object>();

        Boolean ok = new TelcoOrdersHelper().invokeMethod('getOpenOrders', input, output, new Map<String, Object>());
        System.assert(ok);
        List<Object> orders = (List<Object>) output.get('orders');
        System.assertEquals(3, orders.size());
    }
}
```

**Rules**:
- **One `invokeMethod` per class, dispatched by `methodName`.** Many small classes confuse the IP authors; one well-organized helper per domain is cleaner
- **Domain logic stays in regular service classes.** `invokeMethod` is the OmniStudio entry point; the actual business logic should be unit-testable without the OmniStudio framework
- **Always populate `output` on error.** Returning `false` without an error message leaves the IP author guessing
- **75% coverage target applies.** Test the dispatcher AND the underlying service. Don't skip coverage on extension classes — they're as load-bearing as any standard Apex
- **Use `as user` DML in extensions.** Customer-portal OmniScripts run as the running user; extensions must respect FLS and sharing

---

## Anti-patterns

- **One mega-OmniScript per business unit.** Each conditional branch is a fresh path to maintain. Decompose into per-journey scripts and embed
- **Logic in OmniScript JSON.** Conditionals and computations belong in IPs and DataRaptors; OmniScripts compose UI and call them
- **DataRaptor per caller.** Drift across copies makes a small schema change a cross-codebase refactor. One DR per shape
- **Apex Extension as the dumping ground.** When the extension class grows past 200 lines, the logic isn't OmniStudio-shaped — pull it into a normal service class and have the extension method delegate
- **In-prod EPC edits.** Changes ripple through live orders. Always stage in sandbox + deploy
- **`Without Sharing` DataRaptors without justification.** Sharing bypasses leak data through OmniScripts; always document the reason in the DR's description
- **FlexCards for editable surfaces.** They're read-only by design; trying to wedge edits in produces brittle Card Actions
- **Calling an OmniScript directly from a low-volume LWC** when a FlexCard would do. OmniScripts have higher overhead — pick the lighter surface for read-only views
- **Missing the IP cache option.** Repeated downstream calls within a session re-hit DataRaptors; turn on cache for read-mostly IPs
