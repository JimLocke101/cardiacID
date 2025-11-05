import Foundation
import CoreData

@objc(HeartReading)
public class HeartReading: NSManagedObject {
    @NSManaged public var heartRate: Int16
    @NSManaged public var timestamp: Date?
    @NSManaged public var notes: String?
}
