/* Copyright Airship and Contributors */

/**
 * An action that adds a custom event.
 *
 * This action is registered under the name "add_custom_event_action".
 *
 * Expected argument values: A dictionary of keys for the custom event. When a
 * custom event action is triggered from a Message Center Rich Push Message,
 * the interaction type and ID will automatically be filled for the message if
 * they are left blank.
 *
 * Valid situations: UASituationForegroundPush, UASituationLaunchedFromPush,
 * UASituationWebViewInvocation, UASituationManualInvocation, UASituationBackgroundPush,
 * UASituationForegroundInteractiveButton, UASituationBackgroundInteractiveButton,
 * and UASituationAutomation
 *
 *
 * Result value: nil
 *
 * Fetch result: UAActionFetchResultNoData
 *
 * Default predicate: Only accepts UASituationWebViewInvocation and UASituationManualInvocation
 *
 */
@objc(UAAddCustomEventAction)
public class AddCustomEventAction : NSObject, UAAction {
    private var analytics: AnalyticsProtocol
    
    @objc
    public static let name = "add_custom_event_action"

    @objc
    public override init() {
        self.analytics = UAirship.analytics()
    }

    @objc
    public init(analytics: AnalyticsProtocol) {
        self.analytics = analytics
        super.init()
    }
    
    public func acceptsArguments(_ arguments: UAActionArguments) -> Bool {
        guard let dict = arguments.value as? [AnyHashable : Any] else {
            AirshipLogger.error("UAAddCustomEventAction requires a dictionary of event data.")
            return false
        }
        
        guard dict[UACustomEvent.eventNameKey] is String else {
            AirshipLogger.error("UAAddCustomEventAction requires an event name in the event data.")
            return false
        }
        
        return true
    }

    public func perform(with arguments: UAActionArguments, completionHandler: UAActionCompletionHandler) {
        let dict = arguments.value as? [AnyHashable : Any]
        let eventName = parseString(dict, key: UACustomEvent.eventNameKey) ?? ""
        let eventValue = parseString(dict, key: UACustomEvent.eventValueKey)
        let interactionID = parseString(dict, key: UACustomEvent.eventInteractionIDKey)
        let interactionType = parseString(dict, key: UACustomEvent.eventInteractionTypeKey)
        let transactionID = parseString(dict, key: UACustomEvent.eventTransactionIDKey)
        let properties = dict?[UACustomEvent.eventPropertiesKey] as? [String : Any]

        let event = UACustomEvent(name: eventName, stringValue: eventValue)
        
        event.analyticsSupplier = {
            return self.analytics
        }
        event.transactionID = transactionID
        event.properties = properties ?? [:]
        
        if (interactionID != nil || interactionType != nil) {
            event.interactionType = interactionType
            event.interactionID = interactionID
        } else if let messageID = arguments.metadata?[UAActionMetadataInboxMessageIDKey] as? String {
            event.setInteractionFromMessageCenterMessage(messageID)
        }
        
        if let pushPaylaod = arguments.metadata?[UAActionMetadataPushPayloadKey] as? [AnyHashable : Any] {
            event.conversionSendID = pushPaylaod["_"] as? String
            event.conversionPushMetadata = pushPaylaod["com.urbanairship.metadata"] as? String
        }
        
        if event.isValid() {
            event.track()
            completionHandler(UAActionResult.empty())
        } else {
            let error = AirshipErrors.error("Invalid custom event \(arguments.value ?? "")")
            completionHandler(UAActionResult(error: error))
        }
    }

    func parseString(_ dict: [AnyHashable : Any]?, key: String) -> String? {
        guard let value = dict?[key] else {
            return nil
        }
        
        if value is String {
            return value as? String
        } else {
            return "\(value)"
        }
    }
}