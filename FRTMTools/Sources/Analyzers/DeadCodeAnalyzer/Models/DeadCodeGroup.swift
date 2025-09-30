import Foundation

struct DeadCodeGroup: Identifiable {
    let id: String
    let kind: String
    let results: [SerializableDeadCodeResult]
    
    init(kind: String, results: [SerializableDeadCodeResult]) {
        self.id = kind
        self.kind = kind
        self.results = results
    }
}
