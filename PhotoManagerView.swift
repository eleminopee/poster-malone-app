import SwiftUI
import UniformTypeIdentifiers

struct PhotoManagerView: View {
    let item: InventoryItem
    @Environment(InventoryStore.self) var store
    @Environment(CredentialsManager.self) var credentials
    @Environment(\.dismiss) var dismiss

    @State private var driveFiles: [GoogleDriveService.DriveFile] = []
    @State private var imageData: [String: Data] = [:]
    @State private var rotations: [String: Int] = [:]
    @State private var orderedIds: [String] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadError: String? = nil
    @State private var saveMessage: String? = nil
    @State private var selectedId: String? = nil

    // Drop state
    @State private var isDropTargeted = false
    @State private var isUploading = false
    @State private var uploadProgress: String? = nil

    // Folder state
    @State private var folderNotFound = false
    @State private var isCreatingFolder = false
    @State private var isSyncing = false
    @State private var hasSaved = false

    let drive = GoogleDriveService.shared

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading photos from Google Drive...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if folderNotFound {
                    VStack(spacing: 16) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No Drive folder for \(item.sku)")
                            .font(.headline)
                        Text("A folder named \"\(item.sku)\" doesn't exist yet in your Google Drive Inventory folder.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                        Button {
                            Task { await createFolderAndContinue() }
                        } label: {
                            if isCreatingFolder {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Creating folder…")
                                }
                            } else {
                                Label("Create Drive Folder", systemImage: "folder.badge.plus")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isCreatingFolder)
                    }
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Retry") { Task { await loadPhotos() } }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 0) {
                        // Left: grid + drop zone
                        VStack(spacing: 0) {
                            photoGrid
                            Divider()
                            dropZone
                        }
                        .frame(minWidth: 400)

                        Divider()

                        // Right: selected photo controls
                        if let selId = selectedId,
                           let file = driveFiles.first(where: { $0.id == selId }) {
                            photoControls(file: file)
                                .frame(width: 260)
                        } else {
                            VStack {
                                Spacer()
                                Image(systemName: "photo.on.rectangle")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                                Text("Select a photo to edit")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                Spacer()
                            }
                            .frame(width: 260)
                        }
                    }
                }
            }
            .navigationTitle("Manage Photos — \(item.sku)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await syncFromDrive() }
                    } label: {
                        if isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Sync from Drive", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSyncing || isUploading)
                    .help("Re-fetch photo URLs from Google Drive — use this if photos exist in Drive but aren't showing in the app")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openFilePickerForAdd()
                    } label: {
                        Label("Add Photos", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if hasSaved {
                            dismiss()
                        } else {
                            Task { await saveToDriver() }
                        }
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else if hasSaved {
                            Text("Done")
                        } else {
                            Text("Save to Drive")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(hasSaved ? .green : .accentColor)
                    .disabled(isSaving || (!hasSaved && driveFiles.isEmpty))
                }
            }
            .task { await loadPhotos() }
        }
        .pmScreen()
        .tint(PM.pink)
        .frame(minWidth: 720, minHeight: 560)
        .overlay(alignment: .bottom) {
            if let msg = saveMessage {
                Text(msg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let prog = uploadProgress {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(prog)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(), value: saveMessage)
        .animation(.spring(), value: uploadProgress)
    }

    // MARK: - Photo Grid

    var photoGrid: some View {
        ScrollView {
            if orderedIds.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No photos yet")
                        .foregroundStyle(.secondary)
                    Text("Drag photos from the Finder or Photos app below")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(orderedIds, id: \.self) { fileId in
                        if let file = driveFiles.first(where: { $0.id == fileId }) {
                            PhotoGridCell(
                                file: file,
                                imageData: imageData[fileId],
                                rotation: rotations[fileId] ?? 0,
                                isSelected: selectedId == fileId,
                                isCover: orderedIds.first == fileId,
                                index: (orderedIds.firstIndex(of: fileId) ?? 0) + 1
                            )
                            .onTapGesture { selectedId = fileId }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Drop Zone

    var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isDropTargeted
                              ? Color.accentColor.opacity(0.08)
                              : Color(NSColor.controlBackgroundColor))
                )

            if isUploading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Uploading to Drive…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "photo.badge.plus")
                        .font(.title2)
                        .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isDropTargeted ? "Drop to add photos" : "Drag photos here")
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(isDropTargeted ? Color.accentColor : .primary)
                        Text("From Photos app, Finder, or any image source")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 72)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onDrop(of: [.image, .jpeg, .png, .tiff, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Drop Handler

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        // Priority order for loading — fileURL preserves the original file,
        // then try image types directly (covers Photos app which doesn't expose fileURL)
        let imageUTTypes: [UTType] = [.jpeg, .png, .tiff, .heic, .image]

        var pendingImages: [(Data, String)] = []
        let group = DispatchGroup()

        for provider in providers {
            var loaded = false

            // 1) Try file URL — Finder drags, some apps
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                loaded = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    defer { group.leave() }
                    if let urlData = item as? Data,
                       let url = URL(dataRepresentation: urlData, relativeTo: nil),
                       let imgData = try? Data(contentsOf: url) {
                        let ext = url.pathExtension.lowercased()
                        DispatchQueue.main.async {
                            pendingImages.append((imgData, ext.isEmpty ? "jpeg" : ext))
                        }
                    }
                }
            }

            // 2) Try image data types directly — Photos app, screenshot drags, etc.
            if !loaded {
                for utType in imageUTTypes {
                    if provider.hasItemConformingToTypeIdentifier(utType.identifier) {
                        group.enter()
                        loaded = true
                        provider.loadDataRepresentation(forTypeIdentifier: utType.identifier) { data, _ in
                            defer { group.leave() }
                            guard let data, !data.isEmpty else { return }
                            // Determine extension from the matched UTType
                            let ext: String
                            switch utType {
                            case .png:  ext = "png"
                            case .tiff: ext = "tiff"
                            case .heic: ext = "heic"
                            default:    ext = "jpeg"
                            }
                            DispatchQueue.main.async {
                                pendingImages.append((data, ext))
                            }
                        }
                        break
                    }
                }
            }

            // 3) Fallback: ask for any image representation
            if !loaded && provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    defer { group.leave() }
                    guard let data, !data.isEmpty else { return }
                    DispatchQueue.main.async {
                        pendingImages.append((data, "jpeg"))
                    }
                }
            }
        }

        group.notify(queue: .main) {
            guard !pendingImages.isEmpty else {
                self.saveMessage = "Could not read image data. Try the Add Photos button instead."
                return
            }
            Task { await self.uploadDroppedImages(pendingImages) }
        }

        return true
    }

    // MARK: - Upload Dropped Images

    private func uploadDroppedImages(_ images: [(Data, String)]) async {
        isUploading = true
        uploadProgress = "Uploading \(images.count) photo\(images.count == 1 ? "" : "s")…"

        do {
            // Find or create the SKU folder
            let folderId: String
            if let existing = try await drive.findFolder(named: item.sku, inParent: drive.inventoryFolderId) {
                folderId = existing
            } else {
                folderId = try await drive.createFolder(named: item.sku, inParent: drive.inventoryFolderId, credentials: credentials)
            }

            var uploaded = 0
            for (data, ext) in images {
                // Temporary filename — SaveToDriver will rename to final position-based name
                let tempName = "\(item.sku)_import_\(UUID().uuidString.prefix(8)).\(ext)"
                let mimeType = mimeTypeForExtension(ext)

                uploadProgress = "Uploading photo \(uploaded + 1) of \(images.count)…"

                let newFileId = try await drive.uploadFile(
                    data: data,
                    name: tempName,
                    mimeType: mimeType,
                    parentId: folderId,
                    credentials: credentials
                )

                // Make public so lh3.googleusercontent.com thumbnails work
                try? await drive.makeFilePublic(fileId: newFileId, credentials: credentials)

                // Add to local state immediately so it shows in the grid
                let newFile = GoogleDriveService.DriveFile(id: newFileId, name: tempName, mimeType: mimeType)
                await MainActor.run {
                    driveFiles.append(newFile)
                    orderedIds.append(newFileId)
                    imageData[newFileId] = data
                }
                uploaded += 1
            }

            // Immediately update item's image URLs so thumbnails show in inventory
            let currentFiles = try await drive.listFiles(inFolder: folderId)
            let currentURLs = currentFiles.map { "https://lh3.googleusercontent.com/d/\($0.id)=w2000#.jpg" }
            var updatedItem = item
            updatedItem.images = currentURLs

            await MainActor.run {
                store.update(updatedItem)
                isUploading = false
                uploadProgress = nil
                saveMessage = "✓ \(uploaded) photo\(uploaded == 1 ? "" : "s") added. Tap \"Save to Drive\" to rename & finalize."
            }
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run { saveMessage = nil }

        } catch {
            await MainActor.run {
                isUploading = false
                uploadProgress = nil
                saveMessage = "Upload failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - File Picker (toolbar "Add Photos" button)

    private func openFilePickerForAdd() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic, .image]
        panel.message = "Select photos to add to \(item.sku)"
        panel.prompt = "Add Photos"

        panel.begin { response in
            guard response == .OK else { return }
            let images: [(Data, String)] = panel.urls.compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                let ext = url.pathExtension.lowercased().isEmpty ? "jpeg" : url.pathExtension.lowercased()
                return (data, ext)
            }
            guard !images.isEmpty else { return }
            Task { await uploadDroppedImages(images) }
        }
    }

    // MARK: - Photo Controls Panel

    func photoControls(file: GoogleDriveService.DriveFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Preview
            Group {
                if let data = imageData[file.id],
                   let img = rotatedImage(data: data, degrees: rotations[file.id] ?? 0) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .background(.black)
                } else {
                    Rectangle()
                        .fill(PM.raised)
                        .frame(height: 200)
                        .overlay { ProgressView() }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // File name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Filename")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(file.name)
                        .font(.caption)
                        .fontWeight(.medium)
                }

                // Rotate
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rotate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button {
                            rotate(fileId: file.id, by: -90)
                        } label: {
                            Label("Left", systemImage: "rotate.left")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            rotate(fileId: file.id, by: 90)
                        } label: {
                            Label("Right", systemImage: "rotate.right")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                // Reorder
                VStack(alignment: .leading, spacing: 8) {
                    Text("Position")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button {
                            movePhoto(fileId: file.id, direction: -1)
                        } label: {
                            Image(systemName: "arrow.left")
                        }
                        .buttonStyle(.bordered)
                        .disabled(orderedIds.first == file.id)

                        Text("\((orderedIds.firstIndex(of: file.id) ?? 0) + 1) of \(orderedIds.count)")
                            .font(.caption)
                            .frame(maxWidth: .infinity)

                        Button {
                            movePhoto(fileId: file.id, direction: 1)
                        } label: {
                            Image(systemName: "arrow.right")
                        }
                        .buttonStyle(.bordered)
                        .disabled(orderedIds.last == file.id)
                    }
                }

                // Set as cover
                if orderedIds.first != file.id {
                    Button {
                        setAsCover(fileId: file.id)
                    } label: {
                        Label("Set as Cover Photo", systemImage: "star.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    Label("Cover Photo", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Divider()

                // Delete
                Button(role: .destructive) {
                    removePhoto(fileId: file.id)
                } label: {
                    Label("Remove from Grid", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding()

            Spacer()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Actions

    private func rotate(fileId: String, by degrees: Int) {
        let current = rotations[fileId] ?? 0
        rotations[fileId] = (current + degrees + 360) % 360
    }

    private func movePhoto(fileId: String, direction: Int) {
        guard let idx = orderedIds.firstIndex(of: fileId) else { return }
        let newIdx = idx + direction
        guard newIdx >= 0 && newIdx < orderedIds.count else { return }
        orderedIds.swapAt(idx, newIdx)
    }

    private func setAsCover(fileId: String) {
        orderedIds.removeAll { $0 == fileId }
        orderedIds.insert(fileId, at: 0)
    }

    private func removePhoto(fileId: String) {
        orderedIds.removeAll { $0 == fileId }
        driveFiles.removeAll { $0.id == fileId }
        imageData.removeValue(forKey: fileId)
        rotations.removeValue(forKey: fileId)
        if selectedId == fileId { selectedId = nil }
    }

    // MARK: - Load Photos

    private func loadPhotos() async {
        isLoading = true
        loadError = nil
        folderNotFound = false

        do {
            guard let folderId = try await drive.findFolder(
                named: item.sku,
                inParent: drive.inventoryFolderId
            ) else {
                await MainActor.run {
                    folderNotFound = true
                    isLoading = false
                }
                return
            }

            let files = try await drive.listFiles(inFolder: folderId)

            // Ensure all files are publicly readable so lh3 thumbnails work
            for file in files {
                try? await drive.makeFilePublic(fileId: file.id, credentials: credentials)
            }

            await MainActor.run {
                driveFiles = files
                orderedIds = files.map { $0.id }
                rotations = [:]
                isLoading = false
            }

            await withTaskGroup(of: (String, Data?).self) { group in
                for file in files {
                    group.addTask {
                        let data = try? await self.drive.downloadFile(fileId: file.id)
                        return (file.id, data)
                    }
                }
                for await (fileId, data) in group {
                    if let data {
                        await MainActor.run { imageData[fileId] = data }
                    }
                }
            }

        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Sync from Drive
    // Re-fetches all photo file IDs from the SKU's Drive folder and updates item.images.
    // Use when photos exist in Drive but the app doesn't have the URLs
    // (e.g. after re-importing inventory from CSV).

    private func syncFromDrive() async {
        isSyncing = true
        do {
            // Find the folder
            guard let folderId = try await drive.findFolder(
                named: item.sku,
                inParent: drive.inventoryFolderId
            ) else {
                await MainActor.run {
                    isSyncing = false
                    folderNotFound = true
                }
                return
            }

            // Fetch files and make them public
            let files = try await drive.listFiles(inFolder: folderId)
            for file in files {
                try? await drive.makeFilePublic(fileId: file.id, credentials: credentials)
            }

            // Build URLs and update item
            let urls = files.map { "https://lh3.googleusercontent.com/d/\($0.id)=w2000#.jpg" }
            var updatedItem = item
            updatedItem.images = urls

            await MainActor.run {
                store.update(updatedItem)
                driveFiles = files
                orderedIds = files.map { $0.id }
                rotations = [:]
                isSyncing = false
                saveMessage = urls.isEmpty
                    ? "No photos found in Drive folder for \(item.sku)"
                    : "✓ Synced \(urls.count) photo\(urls.count == 1 ? "" : "s") from Drive"
            }

            // Load thumbnails
            await withTaskGroup(of: (String, Data?).self) { group in
                for file in files {
                    group.addTask {
                        let data = try? await self.drive.downloadFile(fileId: file.id)
                        return (file.id, data)
                    }
                }
                for await (fileId, data) in group {
                    if let data { await MainActor.run { imageData[fileId] = data } }
                }
            }

            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { saveMessage = nil }

        } catch {
            await MainActor.run {
                isSyncing = false
                saveMessage = "Sync failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Create Folder

    private func createFolderAndContinue() async {
        isCreatingFolder = true
        do {
            _ = try await drive.createFolder(named: item.sku, inParent: drive.inventoryFolderId, credentials: credentials)
            await MainActor.run {
                isCreatingFolder = false
                folderNotFound = false
                // Folder is empty — go straight to the normal empty photo grid
                driveFiles = []
                orderedIds = []
                imageData = [:]
                rotations = [:]
            }
        } catch {
            await MainActor.run {
                isCreatingFolder = false
                loadError = "Failed to create folder: \(error.localizedDescription)"
                folderNotFound = false
            }
        }
    }

    // MARK: - Save to Drive

    private func saveToDriver() async {
        isSaving = true

        do {
            guard let folderId = try await drive.findFolder(
                named: item.sku,
                inParent: drive.inventoryFolderId
            ) else {
                throw GoogleDriveService.DriveError.folderNotFound(item.sku)
            }

            var renamedCount = 0
            var errorCount = 0

            for (index, fileId) in orderedIds.enumerated() {
                guard let file = driveFiles.first(where: { $0.id == fileId }),
                      var data = imageData[fileId] else { continue }

                // Cover photo = 00, rest = 01, 02, 03...
                let position = String(format: "%02d", index)
                let ext = (file.name as NSString).pathExtension.lowercased()
                let safeExt = ext.isEmpty ? "jpeg" : ext
                let newName = "\(item.sku) \(position).\(safeExt)"

                do {
                    // Apply rotation if needed — upload new content first
                    let degrees = rotations[fileId] ?? 0
                    if degrees != 0, let rotated = applyRotation(data: data, degrees: degrees) {
                        data = rotated
                        _ = try await drive.uploadFile(
                            data: data,
                            name: newName,
                            mimeType: file.mimeType,
                            parentId: folderId,
                            existingFileId: fileId,
                            credentials: credentials
                        )
                    }

                    // Always rename to correct position
                    if file.name != newName {
                        try await drive.renameFile(fileId: fileId, newName: newName, credentials: credentials)
                        renamedCount += 1
                    }
                    // Ensure public so thumbnails work
                    try? await drive.makeFilePublic(fileId: fileId, credentials: credentials)
                } catch {
                    errorCount += 1
                    print("Error saving \(file.name): \(error)")
                }
            }

            // Re-fetch updated file list and update image URLs in app
            let newFiles = try await drive.listFiles(inFolder: folderId)
            let newURLs = newFiles.map { "https://lh3.googleusercontent.com/d/\($0.id)=w2000#.jpg" }

            var updatedItem = item
            updatedItem.images = newURLs
            // Auto-advance status to Processed once photos are saved to Drive
            if updatedItem.status == .ordered || updatedItem.status == .active {
                updatedItem.status = .processed
            }

            await MainActor.run {
                store.update(updatedItem)
                isSaving = false
                hasSaved = true
                if errorCount > 0 {
                    saveMessage = "⚠️ Saved with \(errorCount) error(s). \(renamedCount) files renamed."
                } else {
                    saveMessage = "✓ \(orderedIds.count) photos saved — status set to Processed."
                }
                rotations = [:]
            }

            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { saveMessage = nil }

        } catch {
            await MainActor.run {
                isSaving = false
                saveMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Image Helpers

    private func rotatedImage(data: Data, degrees: Int) -> NSImage? {
        guard degrees != 0 else { return NSImage(data: data) }
        guard let img = NSImage(data: data) else { return nil }
        return rotateNSImage(img, degrees: degrees)
    }

    private func applyRotation(data: Data, degrees: Int) -> Data? {
        guard let img = NSImage(data: data) else { return nil }
        let rotated = rotateNSImage(img, degrees: degrees)
        return rotated?.tiffRepresentation.flatMap {
            NSBitmapImageRep(data: $0)?.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.92]
            )
        }
    }

    private func rotateNSImage(_ image: NSImage, degrees: Int) -> NSImage? {
        let size = image.size
        let (newW, newH): (CGFloat, CGFloat) = (degrees == 90 || degrees == 270)
            ? (size.height, size.width)
            : (size.width, size.height)

        let newImage = NSImage(size: NSSize(width: newW, height: newH))
        newImage.lockFocus()

        let transform = NSAffineTransform()
        transform.translateX(by: newW / 2, yBy: newH / 2)
        transform.rotate(byDegrees: CGFloat(-degrees))
        transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
        transform.concat()

        image.draw(
            at: .zero,
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )

        newImage.unlockFocus()
        return newImage
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "png":  return "image/png"
        case "tiff", "tif": return "image/tiff"
        case "heic": return "image/heic"
        case "webp": return "image/webp"
        default:     return "image/jpeg"
        }
    }
}

// MARK: - Grid Cell

struct PhotoGridCell: View {
    let file: GoogleDriveService.DriveFile
    let imageData: Data?
    let rotation: Int
    let isSelected: Bool
    let isCover: Bool
    let index: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let data = imageData, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .rotationEffect(.degrees(Double(rotation)))
                } else {
                    Rectangle()
                        .fill(PM.raised)
                        .overlay { ProgressView().controlSize(.small) }
                }
            }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )

            Text("\(index)")
                .font(.caption2)
                .fontWeight(.bold)
                .padding(4)
                .background(.black.opacity(0.6))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(4)

            if isCover {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                    Text("Cover")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.orange)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(4)
            }

            if rotation != 0 {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                    .padding(4)
                    .background(.blue.opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(4)
            }
        }
        .frame(width: 140, height: 140)
    }
}
