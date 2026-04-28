# Project Context

> **Schema note**: This document follows a prescribed structure used by the AI workflow agents. Sections must appear in this order: Overview → Object Model → Message Channels → Domain Glossary → Project-Specific Constraints. Agents read this file to understand domain context that cannot be derived from source code alone. Keep entries concise — link out to longer references where needed.

---

## Overview

_TODO_: One paragraph describing what this Salesforce project is for and who uses it.

---

## Object Model

### Standard Objects

_TODO_: For each in-use standard object (Account, Contact, Case, etc.), document:
- **Key fields** — list field API names
- **Relationships** — parent and child relationships

### Custom Objects

_TODO_: Table of custom objects. Format:

| API Name | Purpose | Key Fields / Relationships |
|----------|---------|----------------------------|
| `Example__c` | _Description_ | `Field__c` (type/relationship) |

### Custom Metadata Types

_TODO_: Table of custom metadata types and their purpose.

---

## Message Channels

_TODO_: For each Lightning Message Service channel, document:
- **Channel name** (`MyChannel__c`)
- **Publisher** — which component publishes
- **Subscribers** — which components subscribe
- **Fields / payload shape**

If the project does not use LMS, write "None — this project does not use LMS."

---

## Domain Glossary

_TODO_: Table of project-specific terms, acronyms, and concepts.

| Term | Meaning |
|------|---------|
| _Term_ | _Definition_ |

---

## Project-Specific Constraints

_TODO_: Anything else the AI workflow agents need to know that isn't derivable from source code. Examples:
- Active Flows that aren't in source control
- Test data utilities that exist in the org but not in source
- Custom logging utilities (e.g., a `Logger` class with `Log__c` object)
- Trigger frameworks already in source
- Reusable shared LWCs that should be reused before recreating
