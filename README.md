# Poster Malone — Inventory & Listing Automation

A native macOS app (Swift 6 / SwiftUI) that runs a one-person limited-edition
art-print resale business end to end: inventory, multi-channel listing
automation, photo pipeline, sales, expenses, and tax reporting.

It replaced a Google Sheets + Apps Script workflow and is used daily to manage
roughly **1,000 active inventory items** across **2,400+ completed sales**, on
eBay and a Shopify storefront.

> **How this was built:** I run the business this app was built for. I'm not a
> software engineer — I designed and directed this project working with Claude
> (Anthropic's AI) as the developer. I defined every requirement, made the
> product and data-safety decisions, tested each build against real inventory,
> and drove the fixes when something broke. The code was AI-written; the
> product is mine. See [My role in this project](#my-role-in-this-project).

![Inventory](docs/screenshots/inventory.png)

---

## What it does

| Area | Capability |
|---|---|
| **Inventory** | ~1,000 items, sortable/filterable table, saved views, bulk operations, soft-delete with 30-day recovery |
| **eBay** | OAuth + Trading API, File Exchange CSV generation with staggered listing schedules, sold-order sync, duplicate-listing detection |
| **Shopify** | GraphQL Admin API — product create/update, metafields, collections, variant pricing, sales-channel publishing |
| **Photos** | Google Drive integration (service-account JWT + user OAuth), per-SKU folders, automatic public-URL generation |
| **Instagram** | Graph API posting queue, content calendar, duplicate-print detection across multiple copies of the same item |
| **Finance** | Expense ledger, Schedule C–shaped tax worksheet, CSV export |
| **Analytics** | Sell-through, aging tiers, margin analysis, profit breakdowns by artist/gallery/format |
| **Comics** | A second, fully parallel inventory subsystem for graphic novels — ISBN lookup, its own store, sales, and analytics |

---

## The daily workflow

The app is organized around what actually has to happen each day to keep a
resale business moving.

### Today

The landing screen. Rather than dumping data, it surfaces only what needs
attention right now — items processed but not yet listed, listings live on eBay
but missing from Shopify, items with no photos (which silently blocks listing,
Shopify, and Instagram), sales missing financial data, and inventory aging past
a year. Each card is a shortcut: tapping one filters the inventory to exactly
those items.

![Today](docs/screenshots/today.png)

### Inventory

The core table. ~1,000 items with saved views, column filters, price and
age ranges, and an attention-chip row for the recurring gaps. Items are
selected with checkboxes, and a bulk action bar handles the multi-item
operations: mark listed, mark sold, export to eBay, push to Shopify.

A detail panel shows the full record — photos, pricing across both channels,
storage location (drawer and sleeve), edition details, and acquisition cost.

### Listing to eBay

Items are exported as a File Exchange CSV with staggered schedule times, so a
batch of listings goes live spaced out rather than all at once. The app also
syncs sold orders back from eBay, tracks listing status, and audits live
listings for duplicates.

### Pushing to Shopify

A direct GraphQL integration creates or updates products with titles,
descriptions, pricing, metafields, collections, and SEO fields, then publishes
to the Online Store and Google/YouTube sales channels. Successfully pushed
items update their status and clear themselves from the queue.

### Photos

Each item has a Google Drive folder named by SKU. The app creates the folder,
lists the images, makes them publicly viewable, and stores the URLs — so photos
taken on a phone flow into listings without manual uploading.

### Instagram

Posts are queued from inventory and posted through the Graph API, with a month
calendar view for planning cadence. Because the business often holds multiple
copies of the same print, posting one copy automatically holds the others back
so the same image isn't posted twice.

### Sales, expenses, and tax

Sold items move to a sales record with gross, fees, and net. Expenses are
tracked by category, and a tax view assembles both into a Schedule C–shaped
worksheet with monthly and quarterly breakdowns, exportable as CSV.

### Analytics

![Analytics](docs/screenshots/analytics.png)

All-time performance, rolling sell-through with a linear-regression forecast,
revenue over time, monthly revenue, and profit breakdowns by artist, gallery,
and format.

### Comics

A separate business line — graphic novels and omnibuses, sold on eBay only.
Built as its own subsystem with its own inventory, sales, personal collection,
and analytics, so it can't affect the poster side. Books are added by ISBN,
which pulls title, author, publisher, and year automatically.

---

## How it's built

**Stack:** Swift 6 · SwiftUI · `@Observable` · async/await · local JSON persistence · macOS 15+

```
PosterMalone/
├── Models.swift              # Core data types
├── InventoryStore.swift      # Single source of truth; derived sets + persistence
├── PMRouter.swift            # Navigation state, deep-link intents, toasts
├── PMTheme.swift             # Design-token system (colors, type, spacing)
│
├── Services/
│   ├── EbayService.swift          # OAuth, Trading API (XML), listing lifecycle
│   ├── ShopifyService.swift       # GraphQL Admin API
│   ├── GoogleDriveService.swift   # Service-account JWT + user OAuth
│   ├── InstagramService.swift     # Graph API publishing
│   └── TaxReportService.swift     # Schedule C worksheet generation
│
├── Views/                    # Inventory table, Today, Analytics, automation sheets
└── Comics/                   # Parallel subsystem: own models, store, views, export
```

Notable characteristics of the implementation:

- **Derived state is computed once per data change, not per render.** The
  recurring business-rule scans (needs listing, missing description, not on
  Shopify, needs photos) run in a single pass and are exposed as pre-computed
  sets, which keeps the ~1,000-row table responsive.
- **Writes are debounced and serialized**, with a synchronous flush on quit so
  no data is lost.
- **The Comics module is fully additive** — its own store, its own data files,
  its own views — so a new business line couldn't destabilize the one that pays
  the bills.
- **No credentials in the repository.** Every integration reads its keys at
  runtime from the macOS Keychain.

---

## My role in this project

I'm the operator of the business, not a professional developer. What I brought:

**Requirements from real operations.** Every feature traces back to something
that was costing time or money. The Shopify gap tracker exists because listings
were living on eBay only and I couldn't see which. The Instagram duplicate
detector exists because I own ten copies of some prints and was about to post
the same image twice. The tax worksheet exists because I was assembling
Schedule C numbers by hand.

**Product decisions and their tradeoffs.** When duplicate eBay listings turned
up, the obvious ask was "automatically end the extras." I decided against it:
during cleanup, two of the duplicates turned out to be attached to real sales,
and an automated ender would have destroyed them. The feature ships as
detect-and-alert only, with a human making the final call. Similar reasoning
kept Instagram posting manual after an automated version proved unreliable —
speed wasn't worth the brand risk.

**Testing against real data.** Every build ran against ~1,000 live items and
2,400+ sales records. I reported precise symptoms rather than "it's broken" —
which is what made the hard problems findable. When a performance fix was wrong,
the specific report ("now clicking the header does nothing, and clearing the
search spins") is what led to the actual cause.

**Domain knowledge the AI didn't have.** Collectors search by artist name
first, which drives the title format on both channels. eBay's Links Policy
prohibits pointing listings at an outside store — I caught a suggested feature
that would have violated it. "The Matrix," "The Matrix Digital Rain Variant,"
and "The Matrix GID Variant" are three different prints, not one, which is why
duplicate matching is exact rather than fuzzy.

**Data safety.** I decided what could and couldn't be published here, and
sanitized credentials, folder IDs, and personal information before this
repository was created.

**What I learned along the way.** Enough Swift and SwiftUI to read a diff and
follow the logic; how OAuth flows and API scopes work in practice (including
debugging a permissions error against Shopify's docs); why a hardcoded model
identifier eventually returns a 404; and how to keep a build stable while adding
to it — verifying each change against a checklist before moving on.

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
