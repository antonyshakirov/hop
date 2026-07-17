public enum DiskSpace {
    public static func fits(requiredBytes: Int64, availableBytes: Int64) -> Bool { availableBytes >= requiredBytes }
    public static func required(for files: [TorrentFile]) -> Int64 {
        files.filter { $0.selected }.reduce(0) { $0 + $1.lengthBytes }
    }
}
