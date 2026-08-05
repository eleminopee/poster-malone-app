# Poster Malone — Inventory & Listing Automation

A native macOS app (Swift 6 / SwiftUI) that runs a one-person limited-edition
art-print resale business end to end: inventory, multi-channel listing
automation, photo pipeline, sales, expenses, and tax reporting.

It replaced a Google Sheets + Apps Script workflow and is used daily to manage
roughly **1000+ active inventory items** across **2,400+ completed sales**, on
eBay and a Shopify storefront.

> Built solo as a working business tool, not a tutorial project. Every feature
> exists because a real workflow needed it.

---

<img width="2560" height="1439" alt="PM_Inventory_Table" src="https://github.com/user-attachments/assets/46341b36-573c-4b9b-b4d8-3882f9e17a8d" />


---

## What it does

| Area | Capability |
|---|---|
| **Inventory** | ~1000 items, sortable/filterable table, saved views, bulk operations, soft-delete with 30-day recovery |
| **eBay** | OAuth + Trading API, File Exchange CSV generation with staggered listing schedules, sold-order sync, duplicate-listing detection |
| **Shopify** | GraphQL Admin API — product create/update, metafields, collections, variant pricing, sales-channel publishing |
| **Photos** | Google Drive integration (service-account JWT + user OAuth), per-SKU folders, automatic public-URL generation |
| **Instagram** | Graph API posting queue, content calendar, duplicate-print detection across multiple copies of the same item |
| **Finance** | Expense ledger, Schedule C–shaped tax worksheet, CSV export |
| **Analytics** | Sell-through, aging tiers, margin analysis, profit breakdowns by artist/gallery/format |
| **Comics** | A second, fully parallel inventory subsystem for graphic novels — ISBN lookup, its own store, sales, and analytics |

---

## Architecture

**Stack:** Swift 6 · SwiftUI · `@Observable` · async/await · local JSON persistence · macOS 15+

```
PosterMalone/
├── Models.swift              # Core types (deliberately stable / no-touch)
├── InventoryStore.swift      # Single source of truth; derived sets + coalesced persistence
├── PMRouter.swift            # Navigation state, deep-link intents, global toasts
├── PMTheme.swift             # Design-token system (colors, type, spacing, components)
│
├── Services/
│   ├── EbayService.swift          # OAuth, Trading API (XML), listing lifecycle
│   ├── ShopifyService.swift       # GraphQL Admin API
│   ├── GoogleDriveService.swift   # Service-account JWT + user OAuth, folder reconciliation
│   ├── InstagramService.swift     # Graph API publishing
│   └── TaxReportService.swift     # Schedule C worksheet generation
│
├── Views/                    # Inventory table, Today cockpit, Analytics, automation sheets
└── Comics/                   # Parallel subsystem: own models, store, views, eBay export
```

**Some deliberate design decisions:**

- **Derived state computed once per mutation, not per render.** Business-rule
  scans (needs-listing, missing-description, not-on-Shopify, needs-photos) run
  in a single pass inside the store and are exposed as pre-computed sets, so
  views do O(1) lookups instead of O(n) filters during rendering.
- **Coalesced persistence.** Writes are debounced and serialized on a
  background queue, with a synchronous drain on quit and on app-resign so no
  data is lost.
- **Additive module boundaries.** The Comics subsystem was added with zero
  changes to poster functionality — its own store, own JSON files, own views,
  hooked in through three additive wiring points.

---

## Engineering problems worth reading about

These are the parts I'd want to talk through in an interview.

### 1. A table that took ~60 seconds to sort

Clicking a column header on the 920-row inventory table froze the app for
close to a minute.

**Diagnosis:** Three compounding causes, found by isolating each layer.

1. The `Table` was bound to a sort order *and* an `onChange` handler re-ran the
   entire filter pipeline — sorting the data twice per click.
2. That handler reassigned the whole backing array, which changed the identity
   of every row and forced SwiftUI to tear down and rebuild all 920 row views.
3. The sort comparator read a computed property that called
   `Calendar.current.dateComponents(...)` on **every access**. `Calendar.current`
   re-resolves the calendar each time it's touched, and a sort performs
   O(n log n) comparisons — thousands of calendar resolutions per click.

**Fix:** Cached day-counts in a dictionary rebuilt once per data change against
a single shared `Calendar` and a single captured "now"; routed both the sort
comparator and the cell renderer through the cache. Sorting became instant.

**Takeaway:** the expensive thing wasn't the algorithm — it was a property that
looked free at the call site.

### 2. A UI freeze caused by 920 concurrent actor hops

Clearing a search box (collapsing from a few rows back to the full list) beach-balled the app.

**Diagnosis:** Each row's thumbnail view fired an async `.task` on creation.
Repopulating the table instantiated 920 of them simultaneously, all awaiting a
single actor-isolated image cache — **even for images already cached.** The
serialized actor hops plus their main-thread state updates flooded the run loop.

**Fix:** Added a synchronous, thread-safe cache layer readable during the render
pass. Cached thumbnails now resolve with zero async work and their `.task`
early-returns; only genuine cache misses go asynchronous.

**Takeaway:** `async` isn't free. An await that "usually hits cache" still costs
a suspension point, and that cost multiplies by row count.

### 3. Detecting duplicate listings after a bad batch

A rescheduling run created new eBay listings without ending the originals,
leaving 14 SKUs live twice.

Because listings are created asynchronously by eBay from an uploaded CSV, the
app never gets an atomic "created X, now end Y" moment — so a true preventive
guard isn't achievable in this workflow. I built detection instead: a background
check on view-open that groups all live listings by SKU and surfaces any
appearing more than once, plus a detail view showing each duplicate's item IDs.

Deliberately **detect-and-alert only, never auto-end** — during cleanup, two
"duplicates" turned out to be entangled with real sales, which an automated
ender would have destroyed.

**Takeaway:** when the failure mode is irreversible, the right automation is
the one that stops short and asks a human.

### 4. Duplicate-content detection for Instagram

Owning ten copies of one print means ten SKUs but only one piece of social
content. Posting one copy now automatically holds back the others (matched on
artist + title) and surfaces them in a dedicated view — while keeping genuinely
distinct variants ("The Matrix" vs. "The Matrix Digital Rain Variant") separate.
Implemented as a derived filter rather than a data mutation, so un-marking a
post immediately restores its siblings.

---

## Running this project

The repository contains no credentials. Every integration reads its keys at
runtime from the macOS Keychain, entered once via **Admin → Credentials**.

To build and run you'd need your own:

| Integration | Where to get credentials |
|---|---|
| eBay | [developer.ebay.com](https://developer.ebay.com) — production keyset |
| Shopify | Shopify Admin → Develop apps → Admin API token |
| Google Drive | Google Cloud Console — OAuth client + service account |
| Instagram | Meta for Developers — Graph API page token |
| Anthropic | [console.anthropic.com](https://console.anthropic.com) |

Requires Xcode 16+ and macOS 15+.

---

## Notes

This is a working production tool for a real business, published as a portfolio
piece. Data files, credentials, and business records are excluded from the
repository.
