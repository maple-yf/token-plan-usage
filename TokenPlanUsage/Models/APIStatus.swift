import Foundation

enum APIStatus: Codable, Equatable {
    case normal
    case error(String)
}
