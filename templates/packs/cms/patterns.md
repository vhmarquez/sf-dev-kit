## CMS-1: Custom Content Types {#cms-content-type}

CMS organizes content by **content type** — a schema for a class of content (article, news, product card). Custom types are defined as `ManagedContentType` metadata; they live alongside built-in types (News, Image, Document) and produce the same JSON delivery shape.

```xml
<!-- force-app/main/default/managedContentTypes/Help_Article.managedContentType-meta.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<ManagedContentType xmlns="http://soap.sforce.com/2006/04/metadata">
    <developerName>Help_Article</developerName>
    <masterLabel>Help Article</masterLabel>
    <fullyQualifiedName>Help_Article</fullyQualifiedName>
    <managedContentNodeTypes>
        <developerName>title</developerName>
        <nodeType>Text</nodeType>
        <label>Title</label>
        <required>true</required>
    </managedContentNodeTypes>
    <managedContentNodeTypes>
        <developerName>body</developerName>
        <nodeType>RichText</nodeType>
        <label>Body</label>
    </managedContentNodeTypes>
    <managedContentNodeTypes>
        <developerName>category</developerName>
        <nodeType>Text</nodeType>
        <label>Category</label>
    </managedContentNodeTypes>
    <managedContentNodeTypes>
        <developerName>hero_image</developerName>
        <nodeType>Media</nodeType>
        <label>Hero Image</label>
    </managedContentNodeTypes>
</ManagedContentType>
```

**Rules**:
- **One content type per content shape.** Don't reuse "Article" for press releases AND blog posts; create distinct types so authors get the right form
- **Node types are limited.** `Text`, `RichText`, `Media`, `MultilineText`, `Date`, `DateTime`, `Url`, `Reference`. Coerce business types into these; you can't add custom node types
- **`Reference` nodes link to other CMS content.** Use them for "related articles" or "author"; not for linking to standard sObjects (use a custom URL/text node and resolve in code)
- **Don't model relational data in CMS.** It's a publish-and-deliver store, not a database. Reference data belongs in standard objects with a URL pointer to/from CMS

## CMS-2: Workspaces, Channels, and Publishing {#cms-publishing}

A **CMS workspace** is the editorial container; **channels** are publish surfaces (Experience site, public API, partner portal). Content lives in a workspace and is published to one or more channels independently. Use the API or `/services/data/v<X>/connect/cms/...` REST endpoints for programmatic publishing.

```apex
public with sharing class HelpArticlePublisher {

    /** Publish a CMS content version to one or more channels. */
    public static void publishToChannels(Id contentId, List<Id> channelIds) {
        for (Id channelId : channelIds) {
            // ConnectApi is the supported surface; bare REST is also available
            ConnectApi.ManagedContent.publish(
                /* communityId */ null,
                contentId,
                new ConnectApi.ManagedContentPublishInput()
            );
        }
    }

    /** Unpublish a piece of content — channel-scoped. */
    public static void unpublish(Id contentId, Id channelId) {
        ConnectApi.ManagedContent.unpublish(null, contentId, channelId);
    }
}
```

**Rules**:
- **Workspaces are the unit of authoring permissions.** One workspace per editorial team; share content via the channel layer rather than cross-workspace duplication
- **Publish state is per-channel.** A piece of content can be live on the public site and still in draft for the partner portal
- **Don't publish from a `before` trigger.** Publishing is a callout-equivalent operation; do it from a Queueable or after-commit context
- **Schedule publishing explicitly.** "Publish at this future time" is a content-version property; use it for embargoed releases instead of manual nightly jobs
- **Track who published what.** CMS audit lives outside the standard FieldHistory; capture publish events in a custom `Content_Publish_Log__c` if compliance needs it

## CMS-3: Multi-Locale Variants {#cms-locales}

CMS represents translations as **content variants** within a single content item — same identity, different language. Authors translate variants in the workspace; the delivery API serves the variant matching the request locale.

```apex
public class HelpArticleLocaleClient {

    /** Read a CMS item in a specific locale, falling back to the default if missing. */
    public static ConnectApi.ManagedContentVersion getInLocale(String contentKey, String locale) {
        try {
            return ConnectApi.ManagedContent.getManagedContentByContentKey(
                /* communityId */ null,
                contentKey,
                /* version    */ null,
                locale
            );
        } catch (ConnectApi.NotFoundException e) {
            // Variant for that locale doesn't exist — fall back to default
            return ConnectApi.ManagedContent.getManagedContentByContentKey(null, contentKey, null, null);
        }
    }
}
```

```javascript
// LWC consuming a localized content item via @wire
import { LightningElement, wire } from 'lwc';
import getLocalized from '@salesforce/apex/HelpArticleLocaleClient.getInLocale';
import LANG from '@salesforce/i18n/lang';

export default class AcmeHelpArticle extends LightningElement {
    @api contentKey;
    @wire(getLocalized, { contentKey: '$contentKey', locale: LANG })
    article;
}
```

**Rules**:
- **Define the default locale at workspace creation.** It's the fallback every other variant is keyed against
- **Translate per content version, not per workspace.** A new version of an article is its own translation lifecycle — don't reuse the previous version's translations
- **Use `@salesforce/i18n/lang` for the running user's locale.** Don't pass a hardcoded locale from the client
- **Reject locale mismatches early.** If a portal serves only `en_US` and `es_MX`, the request layer should normalize unknown locales to `en_US` before hitting the CMS API
- **Store untranslated keys in the source variant only.** Don't ship "Lorem ipsum"–shaped placeholders into translated variants; translators see them as ready-to-localize content

## CMS-4: Headless Delivery via Connect REST {#cms-headless}

CMS content can be served headless to non-Salesforce surfaces (mobile apps, marketing pages, partner portals) via the **Connect REST API for Managed Content**. Auth via Connected App; rate-limited like other Connect APIs. Cache aggressively at the CDN layer for public content.

```http
GET /services/data/v62.0/connect/cms/delivery/channels/<channelId>/contents?contentKeyOrIds=<id1,id2>
Authorization: Bearer <token>
Accept: application/json
```

```javascript
// External Node service caching public CMS content with stale-while-revalidate
async function getArticles(ids) {
    const cached = cache.get(ids.join(','));
    if (cached && Date.now() - cached.fetchedAt < TTL_MS) {
        return cached.data;
    }
    const res = await fetch(
        `${SF_BASE}/services/data/v62.0/connect/cms/delivery/channels/${CHANNEL_ID}/contents?contentKeyOrIds=${ids.join(',')}`,
        { headers: { Authorization: `Bearer ${await getToken()}` } }
    );
    const data = await res.json();
    cache.set(ids.join(','), { data, fetchedAt: Date.now() });
    return data;
}
```

**Rules**:
- **Use the Delivery API, not the Authoring API, for read-only consumers.** The delivery surface is built for high-throughput reads; authoring is throttled assumes interactive editor traffic
- **Cache public content at a CDN.** Salesforce's per-org throughput is finite; a CDN absorbs traffic spikes and shields the org
- **Reference media URLs are short-lived if signed.** If the channel uses signed media URLs, callers must re-fetch on a cache miss rather than persisting URLs
- **Don't expose the Connected App token client-side.** Proxy through a small server (Heroku / Cloudflare Worker / Lambda) that handles token refresh
- **Track delivery API usage.** Org limits cap the call volume; `/services/data/v<X>/limits` is your forecast

## CMS-5: CMS vs Knowledge vs Files {#cms-vs-others}

Salesforce ships three content surfaces — CMS, Knowledge, and Files. They overlap; pick by author, audience, and lifecycle.

| Surface | Author | Audience | Lifecycle | When to choose |
|---------|--------|----------|-----------|----------------|
| **CMS** | Marketing / content authors | External (Experience Cloud, headless surfaces) | Versioned, channel-published | Public content, multi-locale, multi-channel publishing |
| **Knowledge** | Service / support agents | Internal agents + external customers | Article workflow, validation, ratings | Self-service knowledge base, search-driven |
| **Files** | Anyone with CRUD | Internal + record-attached | File version history; no publishing model | Documents attached to records, internal collateral |

**Rules**:
- **Marketing content is CMS.** Knowledge for support; Files for record attachments
- **Don't fork the same content across surfaces.** A help article duplicated to CMS *and* Knowledge drifts. Pick the canonical surface and link from the others
- **Knowledge has built-in moderation.** CMS doesn't. If approval workflows are core, Knowledge is closer to ready-built
- **Migration goes one way.** Knowledge → CMS is a re-author (different schema). Plan the canonical surface before content volume grows
- **Search is different per surface.** Knowledge search is article-aware (synonyms, promoted results); CMS search is content-key-aware. Don't expect the same UX

---

## Anti-patterns

- **Reusing one content type for unrelated shapes.** Authors get the wrong form fields; downstream consumers can't filter cleanly. One type per shape
- **Modeling relational reference data in CMS.** CMS is publish-and-deliver. Master data belongs in sObjects; CMS holds the rendered content
- **Publishing from a `before` trigger.** Publish is a heavy operation; do it after commit, in a Queueable
- **Storing the same content in CMS and Knowledge "just in case."** Duplicates drift. Pick canonical, link from the other surface
- **Building locale negotiation in the client.** Use `@salesforce/i18n/lang` and let the platform pick the variant
- **Embedding the Connected App token in a public website.** Token theft is one DevTools tab away. Always proxy
- **Treating CMS as a CDN.** It's the source of truth; cache it on a real CDN for traffic-bearing surfaces
