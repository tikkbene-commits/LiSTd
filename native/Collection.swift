import Foundation

struct LibraryTrack: Decodable, Identifiable, Equatable {
    let id: String
    let artist: String
    let title: String
    let genre: String
    let vibe: String
    let bpm: Double?
    let path: String
    let download_folder: String?
    let imports: [String]?
    let added_at: Double?
}

struct CollectionBrowser {
    var tracks: [LibraryTrack]
    var collectionView = "All tracks"
    var collectionGroup = ""
    var collectionSort = "Track title"
    var search = ""

    func groups(for track: LibraryTrack) -> [String] {
        switch collectionView {
        case "Download folder": return [track.download_folder ?? "Unknown folder"]
        case "Import / tracklist": return track.imports?.isEmpty == false ? track.imports! : ["No import record"]
        case "Genre": return [track.genre.isEmpty ? "Unsorted" : track.genre]
        case "Artist": return [track.artist.isEmpty ? "Unknown artist" : track.artist]
        default: return []
        }
    }

    var visibleTracks: [LibraryTrack] {
        let filtered = tracks.filter { track in
            (collectionView == "All tracks" || collectionGroup.isEmpty || groups(for: track).contains(collectionGroup)) &&
            (search.isEmpty || "\(track.title) \(track.artist) \(track.genre) \(track.vibe)".localizedCaseInsensitiveContains(search))
        }
        return filtered.sorted { a, b in
            switch collectionSort {
            case "Artist":
                if a.artist != b.artist { return a.artist.localizedStandardCompare(b.artist) == .orderedAscending }
            case "BPM":
                if a.bpm != b.bpm { return (a.bpm ?? .infinity) < (b.bpm ?? .infinity) }
            case "Most recently added":
                if a.added_at != b.added_at { return (a.added_at ?? 0) > (b.added_at ?? 0) }
            default: break
            }
            if a.title != b.title { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
            return a.id < b.id
        }
    }

}
