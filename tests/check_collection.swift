import Foundation

@main struct CollectionCheck {
    static func main() throws {
        func track(_ id: String, _ title: String, _ artist: String, _ bpm: Double?, _ added: Double,
                   _ folder: String = "organized/House/Groove", _ imports: [String] = []) -> LibraryTrack {
            LibraryTrack(id: id, artist: artist, title: title, genre: "House", vibe: "Groove", bpm: bpm,
                         path: "/fixture/\(id).flac", download_folder: folder, imports: imports, added_at: added)
        }
        let rows = [track("b", "Track 10", "Alpha", 130, 20, "Downloads root", ["Set A", "Set B"]),
                    track("a", "Track 2", "Beta", 120, 10, "organized/House/Groove", ["Set A"]),
                    track("c", "Unknown", "", nil, 30)]
        var browser = CollectionBrowser(tracks: rows)
        precondition(browser.collectionView == "All tracks" && browser.visibleTracks.map(\.id) == ["a", "b", "c"])
        browser.collectionSort = "Artist"
        precondition(browser.visibleTracks.map(\.id) == ["c", "b", "a"])
        browser.collectionSort = "BPM"
        precondition(browser.visibleTracks.map(\.id) == ["a", "b", "c"], "Unknown BPM must sort last")
        browser.collectionSort = "Most recently added"
        precondition(browser.visibleTracks.map(\.id) == ["c", "b", "a"])
        for (view, group, ids) in [("Download folder", "Downloads root", ["b"]),
                                   ("Import / tracklist", "Set A", ["b", "a"]),
                                   ("Artist", "Beta", ["a"]), ("Genre", "House", ["c", "b", "a"])] {
            browser.collectionView = view; browser.collectionGroup = group
            precondition(browser.visibleTracks.map(\.id) == ids)
        }
        browser.collectionView = "Import / tracklist"; browser.collectionGroup = "Set B"; browser.search = "Beta"
        precondition(browser.visibleTracks.isEmpty, "Search escaped the selected group")
        browser.search = "Alpha"
        precondition(browser.visibleTracks.map(\.id) == ["b"])
        browser.collectionView = "Artist"
        precondition(browser.groups(for: rows[2]) == ["Unknown artist"])
        browser.collectionView = "Import / tracklist"
        precondition(browser.groups(for: rows[2]) == ["No import record"])
        let old = try JSONDecoder().decode(LibraryTrack.self, from: Data("""
        {"id":"old","artist":"","title":"Old","genre":"","vibe":"Needs Review","path":"/old.flac"}
        """.utf8))
        precondition(old.added_at == nil && old.download_folder == nil && old.imports == nil)
        print("Collection checks passed: default, natural title/artist/BPM/date order, folder/import/genre/artist groups, scoped search, missing metadata and legacy decoding.")
    }
}
