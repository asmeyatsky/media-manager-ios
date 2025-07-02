import SwiftUI
import Photos
import Vision
import CoreData
import AVFoundation
import Speech

// MARK: - Data Models
struct MediaItem: Identifiable, Hashable {
    let id = UUID()
    let asset: PHAsset
    var tags: [String] = []
    var detectedText: String = ""
    var faces: [String] = []
    var location: String = ""
    var isProcessed: Bool = false
    var isFavorite: Bool = false
    
    var creationDate: Date {
        asset.creationDate ?? Date()
    }
    
    var mediaType: PHAssetMediaType {
        asset.mediaType
    }
}

struct SmartCollection: Identifiable {
    let id = UUID()
    let title: String
    let items: [MediaItem]
    let icon: String
    let color: Color
}

// MARK: - Core Data Models (Simplified for prototype)
class MediaMetadata: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var smartCollections: [SmartCollection] = []
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0.0
    @Published var recentlyAdded: [MediaItem] = []
    
    func processLibrary() {
        isProcessing = true
        // Simulate processing with real Vision framework calls
        DispatchQueue.global(qos: .background).async {
            self.performAIAnalysis()
        }
    }
    
    private func performAIAnalysis() {
        // Simulate AI processing
        for (index, item) in items.enumerated() {
            DispatchQueue.main.async {
                self.processingProgress = Double(index) / Double(self.items.count)
            }
            
            // Simulate processing delay
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        DispatchQueue.main.async {
            self.isProcessing = false
            self.generateSmartCollections()
        }
    }
    
    private func generateSmartCollections() {
        // Generate smart collections based on AI analysis
        smartCollections = [
            SmartCollection(title: "Beach & Vacations", items: items.filter { $0.tags.contains("beach") || $0.tags.contains("vacation") }, icon: "sun.max.fill", color: .orange),
            SmartCollection(title: "Family & Friends", items: items.filter { !$0.faces.isEmpty }, icon: "person.2.fill", color: .blue),
            SmartCollection(title: "Nature & Landscapes", items: items.filter { $0.tags.contains("nature") || $0.tags.contains("landscape") }, icon: "leaf.fill", color: .green),
            SmartCollection(title: "Food & Dining", items: items.filter { $0.tags.contains("food") }, icon: "fork.knife", color: .red),
            SmartCollection(title: "Screenshots & Documents", items: items.filter { !$0.detectedText.isEmpty }, icon: "doc.text.fill", color: .gray),
            SmartCollection(title: "Favorites", items: items.filter { $0.isFavorite }, icon: "heart.fill", color: .pink)
        ]
    }
}

// MARK: - Permission Manager
class PermissionManager: ObservableObject {
    @Published var photoLibraryStatus: PHAuthorizationStatus = .notDetermined
    @Published var speechRecognitionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    
    func requestPermissions() {
        requestPhotoLibraryPermission()
        requestSpeechRecognitionPermission()
    }
    
    private func requestPhotoLibraryPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                self.photoLibraryStatus = status
            }
        }
    }
    
    private func requestSpeechRecognitionPermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                self.speechRecognitionStatus = status
            }
        }
    }
}

// MARK: - Search Manager
class SearchManager: ObservableObject {
    @Published var searchText = ""
    @Published var isVoiceSearchActive = false
    @Published var searchResults: [MediaItem] = []
    @Published var searchFilters = SearchFilters()
    
    private let speechRecognizer = SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    func performSearch(in items: [MediaItem]) {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if query.isEmpty {
            searchResults = []
            return
        }
        
        searchResults = items.filter { item in
            // Search in tags
            let tagMatch = item.tags.contains { $0.lowercased().contains(query) }
            
            // Search in detected text (OCR)
            let textMatch = item.detectedText.lowercased().contains(query)
            
            // Search in location
            let locationMatch = item.location.lowercased().contains(query)
            
            // Apply filters
            let dateMatch = searchFilters.dateRange == nil || searchFilters.dateRange!.contains(item.creationDate)
            let typeMatch = searchFilters.mediaType == .unknown || item.mediaType == searchFilters.mediaType
            
            return (tagMatch || textMatch || locationMatch) && dateMatch && typeMatch
        }
    }
    
    func startVoiceSearch() {
        guard speechRecognizer?.isAvailable == true else { return }
        
        isVoiceSearchActive = true
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            DispatchQueue.main.async {
                if let result = result {
                    self.searchText = result.bestTranscription.formattedString
                }
                
                if error != nil || result?.isFinal == true {
                    self.stopVoiceSearch()
                }
            }
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
    }
    
    func stopVoiceSearch() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isVoiceSearchActive = false
    }
}

struct SearchFilters {
    var dateRange: ClosedRange<Date>?
    var mediaType: PHAssetMediaType = .unknown
    var location: String = ""
    var tags: [String] = []
}

// MARK: - Main App
@main
struct MediaManagerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Content View
struct ContentView: View {
    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var mediaMetadata = MediaMetadata()
    @StateObject private var searchManager = SearchManager()
    @State private var selectedTab = 0
    @State private var showingOnboarding = true
    
    var body: some View {
        if showingOnboarding {
            OnboardingView(permissionManager: permissionManager) {
                showingOnboarding = false
                loadPhotoLibrary()
            }
        } else {
            TabView(selection: $selectedTab) {
                MainBrowserView(mediaMetadata: mediaMetadata, searchManager: searchManager)
                    .tabItem {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Browse")
                    }
                    .tag(0)
                
                SearchView(mediaMetadata: mediaMetadata, searchManager: searchManager)
                    .tabItem {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
                    }
                    .tag(1)
                
                SmartCollectionsView(mediaMetadata: mediaMetadata)
                    .tabItem {
                        Image(systemName: "square.grid.2x2")
                        Text("Collections")
                    }
                    .tag(2)
                
                SettingsView(mediaMetadata: mediaMetadata)
                    .tabItem {
                        Image(systemName: "gear")
                        Text("Settings")
                    }
                    .tag(3)
            }
            .accentColor(.blue)
        }
    }
    
    private func loadPhotoLibrary() {
        // Simulate loading photo library
        let sampleItems = (1...50).map { index in
            MediaItem(
                asset: PHAsset(), // This would be actual PHAssets in a real implementation
                tags: generateRandomTags(),
                detectedText: index % 10 == 0 ? "Sample detected text \(index)" : "",
                faces: index % 5 == 0 ? ["Person \(index % 3 + 1)"] : [],
                location: index % 8 == 0 ? "Sample Location \(index)" : "",
                isProcessed: false,
                isFavorite: index % 15 == 0
            )
        }
        
        mediaMetadata.items = sampleItems
        mediaMetadata.recentlyAdded = Array(sampleItems.prefix(5))
        mediaMetadata.processLibrary()
    }
    
    private func generateRandomTags() -> [String] {
        let allTags = ["beach", "vacation", "nature", "landscape", "food", "family", "friends", "sunset", "city", "mountains"]
        return Array(allTags.shuffled().prefix(Int.random(in: 1...3)))
    }
}

// MARK: - Onboarding View
struct OnboardingView: View {
    let permissionManager: PermissionManager
    let onComplete: () -> Void
    
    @State private var currentStep = 0
    @State private var storagePreference = StoragePreference.both
    
    enum StoragePreference: String, CaseIterable {
        case iCloud = "iCloud Photos"
        case local = "Local Storage"
        case both = "Both iCloud & Local"
    }
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Welcome to Media Manager")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("AI-powered photo and video management made simple")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            if currentStep == 0 {
                permissionStep
            } else if currentStep == 1 {
                storageStep
            } else {
                processingStep
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var permissionStep: some View {
        VStack(spacing: 20) {
            Text("Grant Permissions")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("We need access to your photos and microphone for voice search to provide the best experience.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Grant Permissions") {
                permissionManager.requestPermissions()
                currentStep = 1
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    private var storageStep: some View {
        VStack(spacing: 20) {
            Text("Choose Storage")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Select which photos you'd like to manage:")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                ForEach(StoragePreference.allCases, id: \.self) { preference in
                    Button(action: {
                        storagePreference = preference
                    }) {
                        HStack {
                            Image(systemName: storagePreference == preference ? "checkmark.circle.fill" : "circle")
                            Text(preference.rawValue)
                            Spacer()
                        }
                        .foregroundColor(storagePreference == preference ? .blue : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            Button("Continue") {
                currentStep = 2
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    private var processingStep: some View {
        VStack(spacing: 20) {
            Text("Setup Complete!")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Your photos will be analyzed in the background using AI to enable smart search and collections.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Get Started") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

// MARK: - Main Browser View
struct MainBrowserView: View {
    @ObservedObject var mediaMetadata: MediaMetadata
    @ObservedObject var searchManager: SearchManager
    @State private var viewMode: ViewMode = .timeline
    
    enum ViewMode: String, CaseIterable {
        case timeline = "Timeline"
        case grid = "Grid"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Quick Search Bar
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        
                        TextField("Search photos...", text: $searchManager.searchText)
                            .textFieldStyle(.plain)
                        
                        if !searchManager.searchText.isEmpty {
                            Button("Clear") {
                                searchManager.searchText = ""
                                searchManager.searchResults = []
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    
                    Button(action: {
                        if searchManager.isVoiceSearchActive {
                            searchManager.stopVoiceSearch()
                        } else {
                            searchManager.startVoiceSearch()
                        }
                    }) {
                        Image(systemName: searchManager.isVoiceSearchActive ? "mic.fill" : "mic")
                            .foregroundColor(searchManager.isVoiceSearchActive ? .red : .blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                
                // Processing Status
                if mediaMetadata.isProcessing {
                    ProcessingStatusView(progress: mediaMetadata.processingProgress)
                }
                
                // Recently Added Section
                if !mediaMetadata.recentlyAdded.isEmpty {
                    RecentlyAddedView(items: mediaMetadata.recentlyAdded)
                }
                
                // View Mode Picker
                Picker("View Mode", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Main Content
                if !searchManager.searchText.isEmpty {
                    SearchResultsCarousel(results: searchManager.searchResults)
                } else {
                    switch viewMode {
                    case .timeline:
                        TimelineView(items: mediaMetadata.items)
                    case .grid:
                        GridView(items: mediaMetadata.items)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("My Photos")
            .navigationBarTitleDisplayMode(.large)
            .onChange(of: searchManager.searchText) { _ in
                searchManager.performSearch(in: mediaMetadata.items)
            }
        }
    }
}

// MARK: - Processing Status View
struct ProcessingStatusView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.blue)
                Text("AI Analysis in Progress...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: progress)
                .progressViewStyle(.linear)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

// MARK: - Recently Added View
struct RecentlyAddedView: View {
    let items: [MediaItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recently Added")
                    .font(.headline)
                    .padding(.horizontal)
                Spacer()
                Text("View All")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        MediaThumbnailView(item: item, size: 80)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom)
    }
}

// MARK: - Timeline View
struct TimelineView: View {
    let items: [MediaItem]
    
    private var groupedItems: [(String, [MediaItem])] {
        let grouped = Dictionary(grouping: items) { item in
            DateFormatter.monthYear.string(from: item.creationDate)
        }
        return grouped.sorted { $0.key > $1.key }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(groupedItems, id: \.0) { month, monthItems in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(month)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            ForEach(monthItems) { item in
                                MediaThumbnailView(item: item, size: 120)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Grid View
struct GridView: View {
    let items: [MediaItem]
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { item in
                    MediaThumbnailView(item: item, size: 120)
                }
            }
            .padding()
        }
    }
}

// MARK: - Search Results Carousel
struct SearchResultsCarousel: View {
    let results: [MediaItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Search Results")
                    .font(.headline)
                    .padding(.horizontal)
                Spacer()
                Text("\(results.count) found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            
            if results.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    
                    Text("No results found")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text("Try adjusting your search terms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(results) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                MediaThumbnailView(item: item, size: 150)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(DateFormatter.shortDate.string(from: item.creationDate))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if !item.location.isEmpty {
                                        Text(item.location)
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                    
                                    if !item.tags.isEmpty {
                                        HStack {
                                            ForEach(item.tags.prefix(2), id: \.self) { tag in
                                                Text(tag)
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.blue.opacity(0.1))
                                                    .foregroundColor(.blue)
                                                    .cornerRadius(4)
                                            }
                                        }
                                    }
                                }
                                .frame(width: 150, alignment: .leading)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

// MARK: - Media Thumbnail View
struct MediaThumbnailView: View {
    let item: MediaItem
    let size: CGFloat
    @State private var showingDetail = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(width: size, height: size)
            
            // Placeholder for actual image
            VStack {
                Image(systemName: item.mediaType == .video ? "video.fill" : "photo.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
                
                if !item.isProcessed {
                    Image(systemName: "brain.head.profile")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            
            // Favorite indicator
            if item.isFavorite {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    Spacer()
                }
                .padding(4)
            }
            
            // Video duration indicator
            if item.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("0:30") // Placeholder duration
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                    }
                }
                .padding(4)
            }
        }
        .onTapGesture {
            showingDetail = true
        }
        .sheet(isPresented: $showingDetail) {
            MediaDetailView(item: item)
        }
    }
}

// MARK: - Media Detail View
struct MediaDetailView: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                // Placeholder for full-size image/video
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(height: 400)
                    .overlay(
                        VStack {
                            Image(systemName: item.mediaType == .video ? "video.fill" : "photo.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            
                            Text("Full Size Media")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
                
                // Metadata
                VStack(alignment: .leading, spacing: 16) {
                    if !item.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI Tags")
                                .font(.headline)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                                ForEach(item.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                    
                    if !item.detectedText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Detected Text")
                                .font(.headline)
                            
                            Text(item.detectedText)
                                .font(.body)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                    
                    if !item.location.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location")
                                .font(.headline)
                            
                            Text(item.location)
                                .font(.body)
                        }
                    }
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("Photo Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Toggle favorite
                    }) {
                        Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                            .foregroundColor(item.isFavorite ? .red : .blue)
                    }
                }
            }
        }
    }
}

// MARK: - Search View
struct SearchView: View {
    @ObservedObject var mediaMetadata: MediaMetadata
    @ObservedObject var searchManager: SearchManager
    @State private var showingFilters = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Advanced Search Bar
                VStack(spacing: 12) {
                    HStack {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            
                            TextField("Search with AI...", text: $searchManager.searchText)
                                .textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        
                        Menu {
                            Button("Recent Photos") {
                                searchManager.searchText = "recent"
                            }
                            Button("Beach Vacation") {
                                searchManager.searchText = "beach vacation"
                            }
                            Button("Screenshots") {
                                searchManager.searchText = "screenshot"
                            }
                            Button("Family Photos") {
                                searchManager.searchText = "family"
                            }
                        } label: {
                            Image(systemName: "sparkles")
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: {
                            if searchManager.isVoiceSearchActive {
                                searchManager.stopVoiceSearch()
                            } else {
                                searchManager.startVoiceSearch()
                            }
                        }) {
                            Image(systemName: searchManager.isVoiceSearchActive ? "mic.fill" : "mic")
                                .foregroundColor(searchManager.isVoiceSearchActive ? .red : .blue)
                        }
                        
                        Button("Filters") {
                            showingFilters = true
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    
                    // Quick Filter Tags
                    if !searchManager.searchText.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterChip(title: "This Week", isSelected: false) {
                                    // Apply date filter
                                }
                                FilterChip(title: "Videos Only", isSelected: false) {
                                    // Apply media type filter
                                }
                                FilterChip(title: "With Text", isSelected: false) {
                                    // Apply OCR filter
                                }
                                FilterChip(title: "With People", isSelected: false) {
                                    // Apply face detection filter
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding()
                
                // Search Results or Suggestions
                if searchManager.searchText.isEmpty {
                    SearchSuggestionsView(searchManager: searchManager)
                } else {
                    SearchResultsCarousel(results: searchManager.searchResults)
                }
                
                Spacer()
            }
            .navigationTitle("AI Search")
            .navigationBarTitleDisplayMode(.large)
            .onChange(of: searchManager.searchText) { _ in
                searchManager.performSearch(in: mediaMetadata.items)
            }
            .sheet(isPresented: $showingFilters) {
                SearchFiltersView(searchManager: searchManager)
            }
        }
    }
}

// MARK: - Search Suggestions View
struct SearchSuggestionsView: View {
    @ObservedObject var searchManager: SearchManager
    
    private let suggestions = [
        ("Recent Photos", "clock.fill", "photos from this week"),
        ("Beach & Vacation", "sun.max.fill", "beach vacation summer"),
        ("Screenshots", "camera.viewfinder", "screenshot text document"),
        ("Family & Friends", "person.2.fill", "family friends people"),
        ("Food Photos", "fork.knife", "food restaurant meal"),
        ("Nature & Landscapes", "leaf.fill", "nature landscape sunset"),
        ("Documents", "doc.text.fill", "document text receipt"),
        ("Selfies", "camera.fill", "selfie portrait face")
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Try Natural Language Search")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    Text("\"Show me beach photos from last summer\"\n\"Find screenshots with text\"\n\"Photos of my family\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Searches")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(suggestions, id: \.0) { title, icon, searchTerm in
                            Button(action: {
                                searchManager.searchText = searchTerm
                            }) {
                                HStack {
                                    Image(systemName: icon)
                                        .foregroundColor(.blue)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        
                                        Text(searchTerm)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Filters View
struct SearchFiltersView: View {
    @ObservedObject var searchManager: SearchManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDateRange = DateRange.allTime
    @State private var selectedMediaType = MediaTypeFilter.all
    @State private var selectedLocation = ""
    
    enum DateRange: String, CaseIterable {
        case allTime = "All Time"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case thisYear = "This Year"
        case lastYear = "Last Year"
    }
    
    enum MediaTypeFilter: String, CaseIterable {
        case all = "All Media"
        case photos = "Photos Only"
        case videos = "Videos Only"
        case screenshots = "Screenshots"
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Date Range")
                        .font(.headline)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(DateRange.allCases, id: \.self) { range in
                            FilterOptionButton(
                                title: range.rawValue,
                                isSelected: selectedDateRange == range
                            ) {
                                selectedDateRange = range
                            }
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Media Type")
                        .font(.headline)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(MediaTypeFilter.allCases, id: \.self) { type in
                            FilterOptionButton(
                                title: type.rawValue,
                                isSelected: selectedMediaType == type
                            ) {
                                selectedMediaType = type
                            }
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Location")
                        .font(.headline)
                    
                    TextField("Enter location...", text: $selectedLocation)
                        .textFieldStyle(.roundedBorder)
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button("Apply Filters") {
                        applyFilters()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    
                    Button("Clear All") {
                        clearFilters()
                    }
                    .foregroundColor(.red)
                }
            }
            .padding()
            .navigationTitle("Search Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func applyFilters() {
        // Apply the selected filters to searchManager.searchFilters
        // This would update the actual search filters in a real implementation
    }
    
    private func clearFilters() {
        selectedDateRange = .allTime
        selectedMediaType = .all
        selectedLocation = ""
    }
}

// MARK: - Filter Option Button
struct FilterOptionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.blue : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Smart Collections View
struct SmartCollectionsView: View {
    @ObservedObject var mediaMetadata: MediaMetadata
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(mediaMetadata.smartCollections) { collection in
                        SmartCollectionCard(collection: collection)
                    }
                }
                .padding()
            }
            .navigationTitle("Smart Collections")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                mediaMetadata.generateSmartCollections()
            }
        }
    }
}

// MARK: - Smart Collection Card
struct SmartCollectionCard: View {
    let collection: SmartCollection
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: {
            showingDetail = true
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: collection.icon)
                        .font(.title2)
                        .foregroundColor(collection.color)
                    
                    Spacer()
                    
                    Text("\(collection.items.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(collection.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                // Preview thumbnails
                if !collection.items.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(collection.items.prefix(3)) { item in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 40)
                                .overlay(
                                    Image(systemName: item.mediaType == .video ? "video.fill" : "photo.fill")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                )
                        }
                        
                        if collection.items.count > 3 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray4))
                                .frame(height: 40)
                                .overlay(
                                    Text("+\(collection.items.count - 3)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                )
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .frame(height: 160)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            CollectionDetailView(collection: collection)
        }
    }
}

// MARK: - Collection Detail View
struct CollectionDetailView: View {
    let collection: SmartCollection
    @Environment(\.dismiss) private var dismiss
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(collection.items) { item in
                        MediaThumbnailView(item: item, size: 120)
                    }
                }
                .padding()
            }
            .navigationTitle(collection.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var mediaMetadata: MediaMetadata
    @State private var autoAnalysis = true
    @State private var cloudSync = true
    @State private var faceRecognition = true
    @State private var showingStorageInfo = false
    
    var body: some View {
        NavigationView {
            List {
                Section("AI & Analysis") {
                    Toggle("Auto Analysis", isOn: $autoAnalysis)
                    Toggle("Face Recognition", isOn: $faceRecognition)
                    
                    Button("Re-analyze Library") {
                        mediaMetadata.processLibrary()
                    }
                    .foregroundColor(.blue)
                }
                
                Section("Storage & Sync") {
                    Toggle("iCloud Sync", isOn: $cloudSync)
                    
                    Button("Storage Usage") {
                        showingStorageInfo = true
                    }
                    .foregroundColor(.blue)
                }
                
                Section("Privacy") {
                    NavigationLink("Data & Privacy") {
                        PrivacySettingsView()
                    }
                    
                    Button("Export Data") {
                        // Export functionality
                    }
                    .foregroundColor(.blue)
                }
                
                Section("Processing") {
                    HStack {
                        Text("Analysis Progress")
                        Spacer()
                        if mediaMetadata.isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Complete")
                                .foregroundColor(.green)
                        }
                    }
                    
                    if mediaMetadata.isProcessing {
                        HStack {
                            Text("Progress")
                            Spacer()
                            Text("\(Int(mediaMetadata.processingProgress * 100))%")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink("Help & Support") {
                        HelpView()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingStorageInfo) {
                StorageInfoView()
            }
        }
    }
}

// MARK: - Privacy Settings View
struct PrivacySettingsView: View {
    @State private var localProcessingOnly = true
    @State private var anonymousAnalytics = false
    
    var body: some View {
        List {
            Section(header: Text("Processing"), footer: Text("All AI analysis is performed locally on your device to protect your privacy.")) {
                Toggle("Local Processing Only", isOn: $localProcessingOnly)
            }
            
            Section(header: Text("Analytics"), footer: Text("Help improve the app by sharing anonymous usage statistics.")) {
                Toggle("Anonymous Analytics", isOn: $anonymousAnalytics)
            }
            
            Section("Data Management") {
                Button("Clear Analysis Cache") {
                    // Clear cache functionality
                }
                .foregroundColor(.orange)
                
                Button("Delete All App Data") {
                    // Delete data functionality
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Storage Info View
struct StorageInfoView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Storage Usage") {
                    HStack {
                        Text("Photos")
                        Spacer()
                        Text("2.3 GB")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Videos")
                        Spacer()
                        Text("4.7 GB")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Analysis Data")
                        Spacer()
                        Text("45 MB")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Total")
                        Spacer()
                        Text("7.0 GB")
                            .fontWeight(.semibold)
                    }
                }
                
                Section("Cleanup Options") {
                    Button("Remove Duplicates") {
                        // Duplicate removal functionality
                    }
                    .foregroundColor(.blue)
                    
                    Button("Compress Large Videos") {
                        // Video compression functionality
                    }
                    .foregroundColor(.blue)
                    
                    Button("Clear Cache") {
                        // Cache clearing functionality
                    }
                    .foregroundColor(.orange)
                }
            }
            .navigationTitle("Storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Help View
struct HelpView: View {
    var body: some View {
        List {
            Section("Getting Started") {
                NavigationLink("How to Search") {
                    HelpDetailView(title: "How to Search", content: "Use natural language like 'beach photos from summer' or tap the microphone for voice search.")
                }
                
                NavigationLink("Understanding Smart Collections") {
                    HelpDetailView(title: "Smart Collections", content: "AI automatically groups your photos into meaningful collections based on content, people, and locations.")
                }
            }
            
            Section("Features") {
                NavigationLink("Voice Search") {
                    HelpDetailView(title: "Voice Search", content: "Tap the microphone icon and speak naturally. Say things like 'Show me photos of my dog' or 'Find screenshots from last week'.")
                }
                
                NavigationLink("Text Recognition") {
                    HelpDetailView(title: "Text Recognition", content: "The app can find text within your photos. Search for receipts, documents, or any text you remember seeing in a photo.")
                }
            }
            
            Section("Support") {
                Button("Contact Support") {
                    // Contact support functionality
                }
                .foregroundColor(.blue)
                
                Button("Report a Bug") {
                    // Bug report functionality
                }
                .foregroundColor(.blue)
            }
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Help Detail View
struct HelpDetailView: View {
    let title: String
    let content: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(content)
                    .font(.body)
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Extensions
extension DateFormatter {
    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
}
                