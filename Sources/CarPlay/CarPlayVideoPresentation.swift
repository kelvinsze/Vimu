import Foundation
import CarPlay
/// Reads the official CarPlay Video in Car session capability.
public enum CarPlayVideoPresentation {

    /// Checks if the connected CarPlay session allows video playback in the car.
    public static func isVideoPlaybackSupported(sessionConfiguration: CPSessionConfiguration?) -> Bool {
        guard let sessionConfiguration else { return false }
        if #available(iOS 26.4, *) {
            return sessionConfiguration.supportsVideoPlayback
        }
        return false
    }

}
