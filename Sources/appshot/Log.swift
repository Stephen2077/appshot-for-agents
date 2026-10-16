import Foundation

func log(_ message: String) {
    FileHandle.standardError.write(Data("[appshot] \(message)\n".utf8))
}
