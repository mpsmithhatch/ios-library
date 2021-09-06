/* Copyright Airship and Contributors */

/**
 * @note For Interrnal use only :nodoc:
 */
@objc
public class UAPushReceivedEvent : NSObject, UAEvent {

    @objc
    public var priority: UAEventPriority {
        get {
            return .normal
        }
    }

    @objc
    public var eventType : String {
        get {
            return "push_received"
        }
    }

    private let _data : [AnyHashable : Any]

    @objc
    public var data: [AnyHashable : Any] {
        get {
            return self._data
        }
    }

    @objc
    public init(notification: [AnyHashable : Any]) {
        var data: [AnyHashable : Any] = [:]
        data["metadata"] = notification["com.urbanairship.metadata"]
        data["push_id"] = notification["_"] ?? "MISSING_SEND_ID"

        self._data = data

        super.init()
    }
}