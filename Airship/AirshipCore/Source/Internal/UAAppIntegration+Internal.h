/* Copyright Airship and Contributors */

#import "UAAppIntegration.h"

NS_ASSUME_NONNULL_BEGIN


@interface UAAppIntegration()

///---------------------------------------------------------------------------------------
/// @name App Integration Internal Methods
///---------------------------------------------------------------------------------------

/**
 * Handles an incoming foreground UNNotification after all presentation options have been merged.
 *
 * @param notification The foreground notification.
 * @param options The merged notification presentation options.
 * @param completionHandler The completion handler.
 */
+ (void)handleForegroundNotification:(UNNotification *)notification mergedOptions:(UNNotificationPresentationOptions)options withCompletionHandler:(void(^)(void))completionHandler;

/**
 * Creates an actions payload
 *
 * @param notification The notification info.
 * @param actionIdentifier The associated action identifier.
 *
 * @return NSDictionary of the action payload.
 */
+ (NSDictionary *)actionsPayloadForNotification:(NSDictionary *)notification actionIdentifier:(nullable NSString *)actionIdentifier;

@end

NS_ASSUME_NONNULL_END
