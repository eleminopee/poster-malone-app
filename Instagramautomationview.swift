import SwiftUI

// ============================================================================
// InstagramAutomationView.swift — the feed planner
// Glow stat pills, dark queue/posted lists with glowing status dots, PM-styled
// schedule form and result toast. All queue mechanics — add/edit/remove,
// swipe to mark posted/unmark, paper-trail writes, igStatus sync — unchanged.
// ============================================================================

// MARK: - Main View

struct InstagramAutomationView: View {
    @Environment(InventoryStore.self) var store
    @Environment(CredentialsManager.self) var credentials
    @State private var selectedTab: IGTab = .queue
    @State private var postResult: String? = nil

    enum IGTab { case schedule, queue, calendar, duplicates, posted }

    var body: some View {
        VStack(spacing: 0) {
            igStatsBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(PM.surface)

            PMNeonDivider(color: PM.pink).opacity(0.5)

            Picker("", selection: $selectedTab) {
                Text("Schedule Posts").tag(IGTab.schedule)
                Text("Queue (\(store.pendingIGPosts.count))").tag(IGTab.queue)
                Text("Calendar").tag(IGTab.calendar)
                Text("Duplicates (\(IGDuplicateKey.duplicateItems(store: store).count))").tag(IGTab.duplicates)
                Text("Posted (\(store.igQueue.filter { $0.status == .posted }.count))").tag(IGTab.posted)
            }
            .pickerStyle(.segmented)
            .padding(14)

            Divider().overlay(PM.borderSubtle)

            switch selectedTab {
            case .schedule:   IGScheduleTab()
            case .queue:      IGQueueTab()
            case .calendar:   IGCalendarTab()
            case .duplicates: IGDuplicatesTab()
            case .posted:     IGPostedTab()
            }
        }
        .pmScreen()
        .navigationTitle("Instagram Automation")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    markNextReady()
                } label: {
                    Label("Post Next", systemImage: "camera.badge.clock")
                }
                .disabled(store.pendingIGPosts.isEmpty)
                .help(store.pendingIGPosts.isEmpty ? "No items in queue" :
                      "Mark \(store.pendingIGPosts.first?.sku ?? "") as ready — then post via PM Automation")
            }
        }
        .overlay(alignment: .bottom) {
            if let result = postResult {
                Text(result)
                    .font(.pmBody(size: 13, weight: .medium))
                    .foregroundStyle(PM.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(PM.raised.opacity(0.97),
                                in: RoundedRectangle(cornerRadius: PM.Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PM.Radius.lg, style: .continuous)
                            .strokeBorder(PM.pink.opacity(0.4), lineWidth: 1)
                    )
                    .pmGlow(PM.pink, radius: 8, opacity: 0.20)
                    .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 4)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            withAnimation { postResult = nil }
                        }
                    }
            }
        }
        .onAppear { store.refreshIGStatuses() }
    }

    // MARK: - Stats Bar

    private var igStatsBar: some View {
        let pending = store.pendingIGPosts.count
        let posted  = store.igQueue.filter { $0.status == .posted }.count
        let failed  = store.igQueue.filter { $0.status == .failed }.count
        let next    = store.pendingIGPosts.first

        return HStack(spacing: 12) {
            igStatPill("In Queue", "\(pending)", .orange)
            igStatPill("Posted",   "\(posted)",  .green)
            if failed > 0 { igStatPill("Failed", "\(failed)", .red) }
            Spacer()
            if let next {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(PM.pink)
                    Text("Next: \(next.sku) · \(next.scheduledDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.pmBody(size: 12))
                        .foregroundStyle(PM.textSecondary)
                }
            }
        }
    }

    private func igStatPill(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Text(value)
                .font(.pmDisplay(size: 15))
                .foregroundStyle(color)
                .monospacedDigit()
                .pmGlow(color, radius: 4, opacity: 0.35)
            Text(label)
                .font(.pmBody(size: 11, weight: .medium))
                .foregroundStyle(PM.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(PM.card, in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.20), lineWidth: 1))
    }

    private func markNextReady() {
        guard let next = store.pendingIGPosts.first else { return }
        var forced = next
        forced.scheduledDate = Date()
        store.updateIGQueueItem(forced)
        withAnimation {
            postResult = "\(next.sku) marked ready — open PM Automation → Instagram to post"
        }
    }
}

// MARK: - Schedule Tab
// Only shows items that have photos, haven't been posted, and aren't already pending in queue

struct IGScheduleTab: View {
    @Environment(InventoryStore.self) var store
    @State private var searchText = ""
    @State private var selectedIDs = Set<UUID>()
    @State private var scheduleDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var batchNote = ""
    @State private var isAdding = false
    @State private var addResult: String? = nil
    @FocusState private var searchFocused: Bool

    private var queuedSKUs: Set<String> {
        Set(store.igQueue.filter { $0.status == .pending }.map { $0.sku })
    }

    private var eligible: [InventoryItem] {
        // Prints already posted (any copy) — shared logic with the Duplicates
        // tab so the two views can never disagree about what's a duplicate.
        let posted = IGDuplicateKey.postedKeys(store: store)
        return store.items.filter {
            $0.status != .sold &&
            $0.status != .theVault &&
            !$0.images.isEmpty &&
            $0.igStatus != "Posted" &&        // never show already-posted items
            !queuedSKUs.contains($0.sku) &&   // never show already-queued items
            // never show another copy of a print already posted
            !posted.contains(IGDuplicateKey.make(artist: $0.artist, title: $0.title))
        }.sorted { ($0.artist + $0.title) < ($1.artist + $1.title) }
    }

    private var filtered: [InventoryItem] {
        guard !searchText.isEmpty else { return eligible }
        let q = searchText.lowercased()
        return eligible.filter {
            $0.sku.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q) ||
            $0.title.lowercased().contains(q)
        }
    }

    var body: some View {
        HSplitView {
            // Left: item list
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(PM.textTertiary)
                    TextField("Search items...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.pmBody(size: 13))
                        .focused($searchFocused)
                    if !selectedIDs.isEmpty {
                        Text("\(selectedIDs.count) selected")
                            .font(.pmBody(size: 12, weight: .semibold))
                            .foregroundStyle(PM.pink)
                            .pmGlow(PM.pink, radius: 4, opacity: 0.3)
                    }
                }
                .padding(10)
                .background(PM.surface)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(searchFocused ? PM.pink.opacity(0.7) : PM.borderSubtle)
                        .frame(height: 1)
                        .animation(PM.Anim.hover, value: searchFocused)
                }

                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No Items Available",
                        systemImage: "checkmark.circle",
                        description: Text("All items with photos have been posted or are already queued.")
                    )
                } else {
                    List(filtered, selection: $selectedIDs) { item in
                        IGItemRow(item: item)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(minWidth: 400)

            // Right: config
            Form {
                Section("Schedule") {
                    DatePicker("Date", selection: $scheduleDate, in: Date()..., displayedComponents: .date)
                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap").foregroundStyle(PM.textTertiary)
                        Text("Post manually via PM Automation → Instagram")
                            .font(.pmBody(size: 12)).foregroundStyle(PM.textTertiary)
                    }
                }

                Section("Caption Note (optional)") {
                    Text("Applied to all selected items. Injected before hashtags.")
                        .font(.pmBody(size: 12)).foregroundStyle(PM.textTertiary)
                    TextEditor(text: $batchNote)
                        .frame(height: 80)
                        .scrollContentBackground(.hidden)
                        .background(PM.base, in: RoundedRectangle(cornerRadius: PM.Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: PM.Radius.sm).strokeBorder(PM.borderStrong, lineWidth: 1))
                }

                Section {
                    Button {
                        addToQueue()
                    } label: {
                        HStack {
                            if isAdding { ProgressView().controlSize(.small) }
                            Text(isAdding ? "Adding..." :
                                 "Add \(selectedIDs.isEmpty ? "Selected" : "\(selectedIDs.count)") to Queue")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PMPrimaryButtonStyle())
                    .disabled(selectedIDs.isEmpty || isAdding)

                    if let result = addResult {
                        Text(result)
                            .font(.pmBody(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(minWidth: 280, maxWidth: 360)
        }
    }

    private func addToQueue() {
        isAdding = true
        var added = 0
        for id in selectedIDs {
            guard let item = store.items.first(where: { $0.id == id }) else { continue }
            var post = IGScheduledPost()
            post.sku           = item.sku
            post.artist        = item.artist
            post.title         = item.title
            post.size          = item.size
            post.scheduledDate = Calendar.current.startOfDay(for: scheduleDate)
            post.customNote    = batchNote
            post.images        = item.images
            post.igCaption     = item.igCaption
            store.addToIGQueue(post)
            added += 1
        }
        addResult    = "✓ Added \(added) item\(added == 1 ? "" : "s") for \(scheduleDate.formatted(date: .abbreviated, time: .omitted))"
        selectedIDs  = []
        batchNote    = ""
        scheduleDate = Calendar.current.date(byAdding: .day, value: 1, to: scheduleDate) ?? scheduleDate
        isAdding     = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { addResult = nil }
    }
}

// MARK: - Queue Tab
// Pending items waiting to post. Tap to edit, swipe left to mark posted, swipe right to delete.

struct IGQueueTab: View {
    @Environment(InventoryStore.self) var store
    @State private var editingPost: IGScheduledPost? = nil
    @State private var deletingID: UUID? = nil
    @State private var showDeleteConfirm = false

    private var pending: [IGScheduledPost] {
        store.igQueue
            .filter { $0.status == .pending || $0.status == .failed }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    var body: some View {
        Group {
            if pending.isEmpty {
                ContentUnavailableView(
                    "Queue is Empty",
                    systemImage: "camera",
                    description: Text("Add items via the Schedule Posts tab.")
                )
            } else {
                List {
                    ForEach(pending) { post in
                        IGQueueRow(post: post)
                            .contentShape(Rectangle())
                            .onTapGesture { editingPost = post }
                            .swipeActions(edge: .leading) {
                                Button {
                                    markAsPosted(post)
                                } label: {
                                    Label("Mark Posted", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deletingID = post.id
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(item: $editingPost) { post in
            IGEditSheet(post: post)
        }
        .confirmationDialog("Remove this item from the queue?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let id = deletingID { store.removeFromIGQueue(id: id) }
            }
        }
    }

    private func markAsPosted(_ post: IGScheduledPost) {
        var updated      = post
        updated.status   = .posted
        updated.postedAt = Date()
        updated.errorMessage = nil
        store.updateIGQueueItem(updated)
        if let idx = store.items.firstIndex(where: { $0.sku == post.sku }) {
            var item = store.items[idx]
            item.igStatus = "Posted"
            store.update(item)
        }
        store.addIGPaperTrailEntry(post: updated)
    }
}

// MARK: - Posted Tab
// Read-only log. Swipe to unmark if needed.

struct IGPostedTab: View {
    @Environment(InventoryStore.self) var store

    private var posted: [IGScheduledPost] {
        store.igQueue
            .filter { $0.status == .posted }
            .sorted { ($0.postedAt ?? $0.scheduledDate) > ($1.postedAt ?? $1.scheduledDate) }
    }

    var body: some View {
        Group {
            if posted.isEmpty {
                ContentUnavailableView(
                    "Nothing Posted Yet",
                    systemImage: "camera.circle",
                    description: Text("Items you post will appear here.")
                )
            } else {
                List {
                    ForEach(posted) { post in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .pmGlow(.green, radius: 4, opacity: 0.5)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(post.sku)
                                        .font(.pmBody(size: 11))
                                        .foregroundStyle(PM.textTertiary)
                                    Spacer()
                                    if let postedAt = post.postedAt {
                                        Text(postedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.pmBody(size: 11))
                                            .foregroundStyle(PM.textTertiary)
                                    }
                                }
                                Text(post.displayTitle)
                                    .font(.pmBody(size: 14, weight: .medium))
                                    .foregroundStyle(PM.textPrimary)
                                    .lineLimit(1)
                                if !post.size.isEmpty {
                                    Text(post.size)
                                        .font(.pmBody(size: 11))
                                        .foregroundStyle(PM.textTertiary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing) {
                            Button {
                                unmarkPosted(post)
                            } label: {
                                Label("Unmark", systemImage: "arrow.uturn.left")
                            }
                            .tint(.orange)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func unmarkPosted(_ post: IGScheduledPost) {
        var updated      = post
        updated.status   = .pending
        updated.postedAt = nil
        store.updateIGQueueItem(updated)
        if let idx = store.items.firstIndex(where: { $0.sku == post.sku }) {
            var item = store.items[idx]
            item.igStatus = ""
            store.update(item)
        }
    }
}

// MARK: - Item Row

struct IGItemRow: View {
    let item: InventoryItem

    var body: some View {
        HStack(spacing: 10) {
            if let url = item.images.first.flatMap({ raw -> URL? in
                let base = (raw.components(separatedBy: "#").first ?? raw)
                    .components(separatedBy: "=").first ?? raw
                return URL(string: "\(base)=s80")
            }) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(PM.borderStrong, lineWidth: 1))
                            .pmGlow(PM.cyan, radius: 3, opacity: 0.18)
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(PM.raised)
                            .frame(width: 40, height: 40)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.sku)
                    .font(.pmBody(size: 11))
                    .foregroundStyle(PM.textTertiary)
                Text([item.artist, item.title].filter { !$0.isEmpty }.joined(separator: " — "))
                    .font(.pmBody(size: 13, weight: .medium))
                    .foregroundStyle(PM.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !item.size.isEmpty {
                        Text(item.size)
                            .font(.pmBody(size: 11))
                            .foregroundStyle(PM.textTertiary)
                    }
                    if item.images.count > 1 {
                        Label("\(item.images.count)", systemImage: "photo.on.rectangle")
                            .font(.pmBody(size: 11))
                            .foregroundStyle(PM.textTertiary)
                    }
                    if item.igCaption.isEmpty {
                        Text("No caption")
                            .font(.pmBody(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Queue Row

struct IGQueueRow: View {
    let post: IGScheduledPost

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(post.status.color)
                .frame(width: 8, height: 8)
                .pmGlow(post.status.color, radius: 4, opacity: 0.5)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(post.sku)
                        .font(.pmBody(size: 11))
                        .foregroundStyle(PM.textTertiary)
                    Spacer()
                    Text(post.scheduledDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.pmBody(size: 11))
                        .foregroundStyle(post.status == .failed ? .red : PM.textTertiary)
                }
                Text(post.displayTitle)
                    .font(.pmBody(size: 14, weight: .medium))
                    .foregroundStyle(PM.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(post.status.rawValue, systemImage: statusIcon(post.status))
                        .font(.pmBody(size: 11, weight: .medium))
                        .foregroundStyle(post.status.color)
                    if !post.customNote.isEmpty {
                        Label("Has note", systemImage: "text.bubble")
                            .font(.pmBody(size: 11))
                            .foregroundStyle(PM.textTertiary)
                    }
                    if let err = post.errorMessage {
                        Text(err)
                            .font(.pmBody(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusIcon(_ s: IGQueueStatus) -> String {
        switch s {
        case .pending:  return "clock"
        case .posted:   return "checkmark.circle"
        case .failed:   return "xmark.circle"
        case .skipped:  return "minus.circle"
        }
    }
}

// MARK: - Edit Sheet

struct IGEditSheet: View {
    @Environment(InventoryStore.self) var store
    @Environment(\.dismiss) var dismiss
    var post: IGScheduledPost

    @State private var scheduledDate: Date
    @State private var customNote: String
    @State private var status: IGQueueStatus

    init(post: IGScheduledPost) {
        self.post      = post
        _scheduledDate = State(initialValue: post.scheduledDate)
        _customNote    = State(initialValue: post.customNote)
        _status        = State(initialValue: post.status)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    LabeledContent("SKU",    value: post.sku)
                    LabeledContent("Artist", value: post.artist)
                    LabeledContent("Title",  value: post.title)
                    if !post.size.isEmpty { LabeledContent("Size", value: post.size) }
                }

                Section("Schedule & Status") {
                    DatePicker("Date", selection: $scheduledDate, displayedComponents: .date)
                    Picker("Status", selection: $status) {
                        ForEach(IGQueueStatus.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    if status == .posted {
                        Text("Marking as Posted will remove this item from Schedule Posts permanently.")
                            .font(.pmBody(size: 12)).foregroundStyle(.orange)
                    }
                }

                Section("Note") {
                    Text("Injected before hashtags.")
                        .font(.pmBody(size: 12)).foregroundStyle(PM.textTertiary)
                    TextEditor(text: $customNote).frame(height: 100)
                }

                if !post.igCaption.isEmpty {
                    Section("Caption Preview") {
                        Text(post.igCaption)
                            .font(.pmBody(size: 12))
                            .foregroundStyle(PM.textSecondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Edit Post")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated           = post
                        updated.scheduledDate = scheduledDate
                        updated.customNote    = customNote
                        updated.status        = status
                        if status == .pending { updated.errorMessage = nil }
                        if status == .posted  { updated.postedAt = updated.postedAt ?? Date() }
                        store.updateIGQueueItem(updated)

                        // Sync igStatus on inventory item
                        if let idx = store.items.firstIndex(where: { $0.sku == post.sku }) {
                            var item = store.items[idx]
                            item.igStatus = (status == .posted) ? "Posted" : ""
                            store.update(item)
                        }
                        // Write paper trail if newly marking as posted
                        if status == .posted && post.status != .posted {
                            store.addIGPaperTrailEntry(post: updated)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .pmScreen()
        .frame(minWidth: 420, minHeight: 480)
    }
}

// MARK: - IG Content Calendar (#6)
// Month grid of scheduled + posted posts, so cadence can be planned rather
// than reacted to. Read-only overview: tap a day to see that day's posts.
// Posting itself still happens in the Queue tab via PM Automation.

struct IGCalendarTab: View {
    @Environment(InventoryStore.self) var store

    @State private var monthAnchor: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay: Date? = nil

    private var cal: Calendar { Calendar.current }

    // Posts grouped by start-of-day, for the visible month.
    private var postsByDay: [Date: [IGScheduledPost]] {
        let comps = cal.dateComponents([.year, .month], from: monthAnchor)
        guard let monthStart = cal.date(from: comps) else { return [:] }
        let range = cal.range(of: .day, in: .month, for: monthStart) ?? 1..<2
        let monthEnd = cal.date(byAdding: .day, value: range.count, to: monthStart) ?? monthStart

        var map: [Date: [IGScheduledPost]] = [:]
        for post in store.igQueue {
            let ref = post.postedAt ?? post.scheduledDate
            guard ref >= monthStart && ref < monthEnd else { continue }
            let day = cal.startOfDay(for: ref)
            map[day, default: []].append(post)
        }
        return map
    }

    // The 6×7 grid of days, padded with leading blanks for weekday alignment.
    private var gridDays: [Date?] {
        let comps = cal.dateComponents([.year, .month], from: monthAnchor)
        guard let monthStart = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: monthStart) else { return [] }
        let firstWeekday = cal.component(.weekday, from: monthStart) // 1 = Sun
        let leadingBlanks = firstWeekday - 1

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for d in range {
            if let day = cal.date(byAdding: .day, value: d - 1, to: monthStart) {
                cells.append(day)
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: monthAnchor)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Month nav
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(PM.textSecondary)

                Text(monthTitle)
                    .font(.pmDisplay(size: 18))
                    .foregroundStyle(PM.textPrimary)
                    .frame(minWidth: 180)

                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(PM.textSecondary)

                Spacer()

                Button("Today") {
                    withAnimation { monthAnchor = cal.startOfDay(for: Date()) }
                }
                .buttonStyle(PMGhostButtonStyle())

                // Month summary
                let monthPosts = postsByDay.values.flatMap { $0 }
                let scheduled = monthPosts.filter { $0.status == .pending }.count
                let posted = monthPosts.filter { $0.status == .posted }.count
                HStack(spacing: 10) {
                    legendDot(.orange, "\(scheduled) queued")
                    legendDot(.green, "\(posted) posted")
                }
                .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Weekday header
            HStack(spacing: 6) {
                ForEach(["SUN","MON","TUE","WED","THU","FRI","SAT"], id: \.self) { d in
                    Text(d)
                        .font(.pmBody(size: 10, weight: .semibold))
                        .foregroundStyle(PM.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            // Grid
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                        if let day {
                            IGCalendarCell(
                                day: day,
                                posts: postsByDay[day] ?? [],
                                isToday: cal.isDateInToday(day),
                                isSelected: selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
                            ) {
                                withAnimation { selectedDay = day }
                            }
                        } else {
                            Color.clear.frame(height: 64)
                        }
                    }
                }
                .padding(.horizontal, 16)

                // Selected-day detail
                if let selectedDay, let dayPosts = postsByDay[selectedDay], !dayPosts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedDay.formatted(date: .complete, time: .omitted).uppercased())
                            .font(.pmBody(size: 11, weight: .semibold))
                            .foregroundStyle(PM.textTertiary)
                            .tracking(1.0)
                        ForEach(dayPosts) { post in
                            HStack(spacing: 10) {
                                Circle().fill(post.status.color).frame(width: 8, height: 8)
                                ThumbnailView(url: post.images.first, flat: true)
                                    .frame(width: 32, height: 32)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(post.displayTitle)
                                        .font(.pmBody(size: 13, weight: .medium))
                                        .foregroundStyle(PM.textPrimary)
                                        .lineLimit(1)
                                    Text("\(post.sku) · \(post.status.rawValue)")
                                        .font(.pmBody(size: 11))
                                        .foregroundStyle(PM.textTertiary)
                                }
                                Spacer()
                                Text(post.scheduledDate.formatted(date: .omitted, time: .shortened))
                                    .font(.pmBody(size: 11))
                                    .foregroundStyle(PM.textTertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(PM.card, in: RoundedRectangle(cornerRadius: PM.Radius.sm))
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: monthAnchor) {
            withAnimation { monthAnchor = next; selectedDay = nil }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.pmBody(size: 11)).foregroundStyle(PM.textSecondary)
        }
    }
}

struct IGCalendarCell: View {
    let day: Date
    let posts: [IGScheduledPost]
    let isToday: Bool
    let isSelected: Bool
    let action: () -> Void

    private var dayNum: String {
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: day)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dayNum)
                    .font(.pmBody(size: 12, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? PM.pink : PM.textSecondary)
                Spacer(minLength: 0)
                // Status dots — up to a few, then a count
                if !posts.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(Array(posts.prefix(4).enumerated()), id: \.offset) { _, p in
                            Circle().fill(p.status.color).frame(width: 6, height: 6)
                        }
                        if posts.count > 4 {
                            Text("+\(posts.count - 4)")
                                .font(.pmBody(size: 9, weight: .semibold))
                                .foregroundStyle(PM.textTertiary)
                        }
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(
                isSelected ? PM.pink.opacity(0.12) : PM.card,
                in: RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous)
                    .strokeBorder(
                        isSelected ? PM.pink.opacity(0.5) : (isToday ? PM.pink.opacity(0.3) : PM.borderSubtle),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - IG Duplicate Detection
// Multiple copies of the same print are separate SKUs but ONE piece of IG
// content. Once any copy has been posted, the remaining copies are duplicates:
// they're hidden from Schedule Posts and listed here instead, so a repeat post
// can't happen by accident.
//
// Matching is EXACT on artist + title (case/whitespace-normalized only).
// "The Matrix", "The Matrix Digital Rain Variant" and "The Matrix GID Variant"
// are different prints and stay separate.

enum IGDuplicateKey {

    static func make(artist: String, title: String) -> String {
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(a)|\(t)"
    }

    /// Keys for prints already posted to Instagram.
    static func postedKeys(store: InventoryStore) -> Set<String> {
        var keys = Set<String>()
        for post in store.igQueue where post.status == .posted {
            if let item = store.items.first(where: { $0.sku == post.sku }) {
                keys.insert(make(artist: item.artist, title: item.title))
            }
        }
        for item in store.items where item.igStatus == "Posted" {
            keys.insert(make(artist: item.artist, title: item.title))
        }
        return keys
    }

    /// Sellable items that are another copy of an already-posted print.
    /// These are what Schedule Posts hides and the Duplicates tab shows.
    static func duplicateItems(store: InventoryStore) -> [InventoryItem] {
        let posted = postedKeys(store: store)
        let queued = Set(store.igQueue.filter { $0.status == .pending }.map { $0.sku })
        return store.items.filter {
            $0.status != .sold &&
            $0.status != .theVault &&
            !$0.images.isEmpty &&
            $0.igStatus != "Posted" &&            // not the posted copy itself
            !queued.contains($0.sku) &&
            posted.contains(make(artist: $0.artist, title: $0.title))
        }.sorted { ($0.artist + $0.title + $0.sku) < ($1.artist + $1.title + $1.sku) }
    }

    /// Groups duplicates by print, with the SKU that was actually posted.
    struct Group: Identifiable {
        let key: String
        let artist: String
        let title: String
        let postedSKU: String
        let copies: [InventoryItem]
        var id: String { key }
    }

    static func groups(store: InventoryStore) -> [Group] {
        let dupes = duplicateItems(store: store)
        var byKey: [String: [InventoryItem]] = [:]
        for item in dupes {
            byKey[make(artist: item.artist, title: item.title), default: []].append(item)
        }
        return byKey.compactMap { key, copies -> Group? in
            guard let first = copies.first else { return nil }
            // Find which SKU was posted for this print
            let postedSKU = store.items.first {
                make(artist: $0.artist, title: $0.title) == key && $0.igStatus == "Posted"
            }?.sku
                ?? store.igQueue.first { post in
                    post.status == .posted &&
                    store.items.contains { $0.sku == post.sku && make(artist: $0.artist, title: $0.title) == key }
                }?.sku
                ?? "—"
            return Group(key: key, artist: first.artist, title: first.title,
                         postedSKU: postedSKU, copies: copies)
        }
        .sorted { ($0.artist + $0.title) < ($1.artist + $1.title) }
    }
}

// MARK: - Duplicates Tab

struct IGDuplicatesTab: View {
    @Environment(InventoryStore.self) var store
    @State private var searchText = ""

    private var groups: [IGDuplicateKey.Group] {
        let all = IGDuplicateKey.groups(store: store)
        guard !searchText.isEmpty else { return all }
        let q = searchText.lowercased()
        return all.filter {
            $0.artist.lowercased().contains(q) ||
            $0.title.lowercased().contains(q) ||
            $0.copies.contains { $0.sku.lowercased().contains(q) }
        }
    }

    private var totalCopies: Int { groups.reduce(0) { $0 + $1.copies.count } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(groups.count) print\(groups.count == 1 ? "" : "s") already posted · \(totalCopies) extra cop\(totalCopies == 1 ? "y" : "ies") held back")
                        .font(.pmBody(size: 13, weight: .semibold))
                        .foregroundStyle(PM.textPrimary)
                    Text("These are hidden from Schedule Posts so you don't post the same print twice.")
                        .font(.pmBody(size: 11))
                        .foregroundStyle(PM.textTertiary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(PM.textTertiary)
                        .font(.system(size: 11))
                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.pmBody(size: 12))
                        .frame(width: 160)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(PM.base, in: RoundedRectangle(cornerRadius: PM.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: PM.Radius.sm).strokeBorder(PM.borderStrong, lineWidth: 1))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(PM.surface)

            Divider().overlay(PM.borderSubtle)

            if groups.isEmpty {
                ContentUnavailableView {
                    Label("No Duplicates", systemImage: "checkmark.circle")
                        .font(.pmDisplay(size: 20))
                        .foregroundStyle(PM.textSecondary)
                } description: {
                    Text("When you post a print that you own multiple copies of, the other copies appear here instead of Schedule Posts.")
                        .font(.pmBody(size: 13))
                        .foregroundStyle(PM.textTertiary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in
                            IGDuplicateGroupRow(group: group)
                            Rectangle().fill(PM.borderSubtle).frame(height: 1)
                        }
                    }
                }
            }
        }
    }
}

struct IGDuplicateGroupRow: View {
    let group: IGDuplicateKey.Group
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(PM.Anim.hover) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    ThumbnailView(url: group.copies.first?.images.first, flat: true)
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(group.artist) — \(group.title)")
                            .font(.pmBody(size: 14, weight: .medium))
                            .foregroundStyle(PM.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            PMGlowBadge(text: "Posted: \(group.postedSKU)", color: .green, flat: true)
                            Text("\(group.copies.count) other cop\(group.copies.count == 1 ? "y" : "ies") held back")
                                .font(.pmBody(size: 11))
                                .foregroundStyle(PM.textTertiary)
                        }
                    }

                    Spacer()

                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PM.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(group.copies) { copy in
                        HStack(spacing: 10) {
                            Text(copy.sku)
                                .font(.pmBody(size: 12, weight: .medium))
                                .foregroundStyle(PM.textSecondary)
                                .frame(width: 80, alignment: .leading)
                            Text(copy.size)
                                .font(.pmBody(size: 11))
                                .foregroundStyle(PM.textTertiary)
                            Spacer()
                            Text("\(copy.images.count) photo\(copy.images.count == 1 ? "" : "s")")
                                .font(.pmBody(size: 11))
                                .foregroundStyle(PM.textTertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .padding(.leading, 52)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }
}
