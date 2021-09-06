/* Copyright Airship and Contributors */

import Foundation

class UAEventUtils {

    private static let push: () -> PushProtocol = { UAirship.push() }

    class func isValid(latitude: Double) -> Bool {
        guard latitude >= -90 && latitude <= 90 else {
            AirshipLogger.error("Invalid latitude \(latitude). Must be between -90 and 90")
            return false
        }
        return true
    }

    class func isValid(longitude: Double) -> Bool {
        guard longitude >= -180 && longitude <= 180 else {
            AirshipLogger.error("Invalid longitude \(longitude). Must be between -180 and 180")
            return false
        }
        return true
    }

    class func notificationTypes() -> [AnyHashable]? {
        var notificationTypes: [AnyHashable] = []

        let authorizedSettings = push().authorizedNotificationSettings

        if (UAAuthorizedNotificationSettings.badge.rawValue & authorizedSettings.rawValue) > 0 {
            notificationTypes.append("badge")
        }

        #if !os(tvOS)
            if (UAAuthorizedNotificationSettings.sound.rawValue & authorizedSettings.rawValue) > 0 {
                notificationTypes.append("sound")
            }

            if (UAAuthorizedNotificationSettings.alert.rawValue & authorizedSettings.rawValue) > 0 {
                notificationTypes.append("alert")
            }

            if (UAAuthorizedNotificationSettings.carPlay.rawValue & authorizedSettings.rawValue) > 0 {
                notificationTypes.append("car_play")
            }

            if (UAAuthorizedNotificationSettings.lockScreen.rawValue & authorizedSettings.rawValue) > 0 {
                notificationTypes.append("lock_screen")
            }

            if (UAAuthorizedNotificationSettings.notificationCenter.rawValue & authorizedSettings.rawValue) > 0 {
                notificationTypes.append("notification_center")
            }

            if (UAAuthorizedNotificationSettings.criticalAlert.rawValue & authorizedSettings.rawValue) > 0 {
                notificationTypes.append("critical_alert")
            }
        #endif

        return notificationTypes
    }

    class func notificationAuthorization() -> String? {
        let authorizationStatus = push().authorizationStatus

        switch authorizationStatus {
        case .notDetermined:
            return "not_determined"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .provisional:
            return "provisional"
        case .ephemeral:
            return "ephemeral"
        default:
            return "not_determined"
        }
    }

}