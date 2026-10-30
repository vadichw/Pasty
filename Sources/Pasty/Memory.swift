import Darwin

enum Memory {
    /// Returns freed malloc pages to the system so the footprint shrinks after large
    /// temporary allocations (images, the popup's view tree).
    static func relieve() {
        malloc_zone_pressure_relief(nil, 0)
    }
}
