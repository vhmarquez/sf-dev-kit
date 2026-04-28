# LWC CSS & JavaScript Standards

Practical LWC standards for this Salesforce project. Read alongside `docs/patterns/salesforce-patterns.md` (generic platform patterns) and `docs/patterns/project-patterns.md` (project-specific patterns).

---

## CSS Standards

### Use SLDS Utility Classes First

Before writing custom CSS, check if an SLDS utility class exists.

```html
<!-- DO: SLDS utilities for spacing, alignment, typography -->
<div class="slds-m-bottom_medium slds-p-around_small">
  <h2 class="slds-text-heading_medium slds-m-bottom_small">Title</h2>
  <p class="slds-text-body_regular slds-text-color_weak">Description</p>
</div>

<!-- DO: SLDS grid for layout -->
<div class="slds-grid slds-wrap slds-gutters">
  <div class="slds-size_1-of-1 slds-medium-size_1-of-2">Column 1</div>
  <div class="slds-size_1-of-1 slds-medium-size_1-of-2">Column 2</div>
</div>
```

Common utilities:
- **Spacing**: `slds-m-{direction}_{size}` (margin), `slds-p-{direction}_{size}` (padding)
- **Directions**: `top`, `bottom`, `left`, `right`, `around`, `vertical`, `horizontal`
- **Sizes**: `xxx-small`, `xx-small`, `x-small`, `small`, `medium`, `large`, `x-large`, `xx-large`
- **Grid**: `slds-grid`, `slds-wrap`, `slds-gutters`, `slds-size_X-of-12`
- **Responsive**: `slds-small-size_*`, `slds-medium-size_*`, `slds-large-size_*`
- **Text**: `slds-text-heading_{size}`, `slds-text-body_{size}`, `slds-text-align_{direction}`
- **Visibility**: `slds-show`, `slds-hide`, `slds-show_{breakpoint}`, `slds-hide_{breakpoint}`

### Never Use `!important`

```css
/* BAD */
.slds-button { color: blue !important; }

/* GOOD: Use styling hooks */
:host {
  --slds-c-button-color-text: blue;
}

/* GOOD: Increase specificity with your own class */
.my-button.my-button { color: blue; }
```

### Use `:host` and Styling Hooks

```css
/* Style the component root */
:host {
  display: block;
  --slds-c-card-color-background: var(--my-card-bg, #ffffff);
}

/* Define custom properties with SLDS fallbacks */
.card-header {
  border-left: 4px solid var(--slds-c-brand-border-color, #0070d2);
  padding-left: var(--slds-spacing-small, 0.75rem);
}
```

### Never Override SLDS Class Internals

```css
/* BAD: Targets SLDS internals — breaks on SLDS updates */
.slds-button { padding: 20px; }
.slds-card__header { background: blue; }
lightning-card >>> .slds-card__header { color: red; }

/* GOOD: Create your own classes */
.my-card-header { background: blue; }

/* GOOD: Use styling hooks for base components */
:host { --slds-c-card-color-background: #f3f3f3; }
```

### No Hardcoded Colors or Spacing

```css
/* BAD */
.my-component { margin: 16px; color: #0070d2; }

/* GOOD: Use SLDS spacing tokens */
.my-component {
  margin: var(--slds-spacing-medium);
  color: var(--slds-c-text-color-brand);
}

/* BETTER: Use SLDS utility classes in HTML instead */
```

### No Direct DOM Manipulation for Styling

```javascript
// BAD
this.template.querySelector('.my-div').style.color = 'red';

// GOOD: Toggle a CSS class
this.template.querySelector('.my-div').classList.add('error-state');
```

```css
.error-state { color: var(--slds-c-text-color-error, #c23030); }
```

### Responsive Design

Use SLDS responsive grid classes — don't hardcode breakpoints in JS.

```html
<!-- Full width on mobile, half on tablet, third on desktop -->
<div class="slds-grid slds-wrap slds-gutters">
  <div class="slds-size_1-of-1 slds-medium-size_1-of-2 slds-large-size_1-of-3">
    Card content
  </div>
</div>

<!-- Responsive visibility -->
<nav class="slds-show slds-hide_large">Mobile menu</nav>
<nav class="slds-hide slds-show_large">Desktop menu</nav>
```

---

## JavaScript Standards

### Reactivity

```javascript
// Plain properties for scalars (reactive by default)
count = 0;
name = 'default';
isLoading = false;

// @track for objects/arrays with nested mutation
@track user = { firstName: 'John', address: { city: 'NYC' } };

// @api for public properties (set by parent or Experience Builder)
@api recordId;
@api cardTitle;

// Getters for computed values (re-evaluated on dependency change)
get fullName() { return `${this.firstName} ${this.lastName}`; }
get hasRecords() { return this.records?.length > 0; }
```

**Rules**:
- Don't use `@track` on primitives — it's redundant
- Never mutate `@api` properties directly — copy to local variable if needed
- Use getters for derived/computed values, not `renderedCallback`

### Lifecycle Hooks

```javascript
connectedCallback() {
    // DO: Initialize data, subscribe to LMS, start event listeners
    this.subscribeToMessageChannel();
    this.loadData();
}

renderedCallback() {
    // DO: DOM measurements, third-party library init (with guard)
    if (!this._chartInitialized && this.template.querySelector('.chart')) {
        this._chartInitialized = true;
        this.initChart();
    }
    // DON'T: Update @track properties here (causes infinite loop)
}

disconnectedCallback() {
    // DO: Clean up subscriptions, timers, event listeners
    unsubscribe(this.subscription);
    this.subscription = null;
    clearTimeout(this.debounceTimer);
}
```

**Rules**:
- `connectedCallback`: Init data, subscriptions, listeners
- `renderedCallback`: DOM-dependent work only, always use a guard flag to prevent re-runs
- `disconnectedCallback`: Clean up everything — subscriptions, timers, listeners

### Template Directives

```html
<!-- lwc:if — removes from DOM (better for large conditional blocks) -->
<template lwc:if={showForm}>
  <div class="large-form">...</div>
</template>
<template lwc:elseif={showError}>
  <div class="error-state">...</div>
</template>
<template lwc:else>
  <div class="empty-state">...</div>
</template>

<!-- lwc:for — always provide lwc:key with unique ID -->
<template lwc:for={items} lwc:key="id">
  <c-list-item data={item}></c-list-item>
</template>

<!-- lwc:spread — dynamic properties on base components -->
<lightning-input lwc:spread={inputConfig}></lightning-input>
```

**Rules**:
- Prefer `lwc:if` over `if:true` for conditional blocks (newer, supports else/elseif)
- Always provide `lwc:key` with a stable unique identifier (not array index)
- Use `lwc:spread` instead of manually binding 5+ properties

### Event Handling

```javascript
// Dispatching: always set bubbles + composed for cross-component events
this.dispatchEvent(new CustomEvent('itemselected', {
    detail: { itemId: this.selectedId, itemName: this.selectedName },
    bubbles: true,
    composed: true
}));

// Handling in parent HTML
// <c-child onitemselected={handleItemSelected}></c-child>

handleItemSelected(event) {
    const { itemId, itemName } = event.detail;
}
```

**Rules**:
- Event names: lowercase, no hyphens (e.g., `itemselected` not `item-selected`)
- Always `bubbles: true, composed: true` for events that cross component boundaries
- Keep `detail` payload minimal — pass IDs, let parent query if it needs more data

### Debouncing

```javascript
debounceTimer;

handleSearchInput(event) {
    this.searchTerm = event.target.value;
    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
        this.performSearch();
    }, 300);
}

disconnectedCallback() {
    clearTimeout(this.debounceTimer);
}
```

**Rule**: Debounce any handler that triggers Apex calls, SOSL searches, or wire refreshes on user input.

### Batching State Updates

```javascript
// BAD: Multiple assignments trigger multiple re-renders
this.records = newRecords;
this.totalCount = newRecords.length;
this.isLoading = false;
this.hasError = false;

// GOOD: LWC batches synchronous assignments in the same microtask
// (the above is actually fine in LWC — but avoid spreading across async boundaries)

// BAD: Assignments in separate async callbacks
setTimeout(() => { this.records = data; }, 0);
setTimeout(() => { this.isLoading = false; }, 0);

// GOOD: Single callback
this.records = data;
this.isLoading = false;
```

---

## Accessibility

### Always Provide Labels

```html
<!-- Base components: use label prop -->
<lightning-input label="Email" value={email}></lightning-input>
<lightning-button label="Submit" title="Submit the form"></lightning-button>
<lightning-datatable aria-label="List of contacts" ...></lightning-datatable>

<!-- Custom elements: use aria-label -->
<input type="text" aria-label="Search contacts" />

<!-- Screen reader only text -->
<span class="slds-assistive-text">Additional context for screen readers</span>
```

### Keyboard Navigation

```html
<!-- Use semantic HTML — buttons, not styled divs -->
<button onclick={handleClick}>Submit</button>  <!-- DO -->
<div class="button" onclick={handleClick}>Submit</div>  <!-- DON'T -->

<!-- Manage tabindex for custom interactive elements -->
<li role="menuitem" tabindex={isActive ? '0' : '-1'}>{item.label}</li>
```

### Focus Management

```javascript
// Set focus when opening dialogs/modals
handleOpenDialog() {
    this.showDialog = true;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
        this.template.querySelector('.dialog-input')?.focus();
    }, 0);
}

// Return focus when closing
handleCloseDialog() {
    this.showDialog = false;
    this.template.querySelector('.trigger-button')?.focus();
}
```

### ARIA for Dynamic Content

```html
<!-- Live region for async updates -->
<div aria-live="polite" aria-atomic="true" class="slds-assistive-text">
  {statusMessage}
</div>

<!-- Expandable sections -->
<button aria-expanded={isExpanded} aria-controls="section-1" onclick={toggleSection}>
  Toggle Section
</button>
<div id="section-1" lwc:if={isExpanded}>Section content</div>
```
