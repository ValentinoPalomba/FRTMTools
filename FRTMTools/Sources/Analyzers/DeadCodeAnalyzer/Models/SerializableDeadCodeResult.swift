import Foundation

struct SerializableDeadCodeResult: Identifiable, Codable {
    let id: UUID
    
    // Declaration Data
    let kind: String
    let accessibility: String
    let name: String?
    let location: String
    let filePath: String
    let icon: String
    
    // Annotation Data
    let annotationDescription: String
}
