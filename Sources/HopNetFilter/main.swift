import Foundation
import NetworkExtension

autoreleasepool {
    NEProvider.startSystemExtensionMode()
    FilterService.shared.start()
}
dispatchMain()
