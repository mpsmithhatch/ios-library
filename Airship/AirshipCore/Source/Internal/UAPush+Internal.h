/* Copyright Airship and Contributors */

#import "UAPush.h"
#import "UAirship.h"
#import "UAAPNSRegistrationProtocol+Internal.h"
#import "UAAPNSRegistration+Internal.h"
#import "UAComponent+Internal.h"
#import "UAChannel+Internal.h"
#import "UAPushProviderDelegate.h"
#import "UAAnalytics+Internal.h"

@class UAAppStateTracker;
@class UAPreferenceDataStore;
@class UARuntimeConfig;
@class UATagGroupsAPIClient;
@class UATagGroupsRegistrar;
@class UADispatcher;
@class UANotificationCategories;

NS_ASSUME_NONNULL_BEGIN

/**
 * User push notification enabled data store key.
 */
extern NSString *const UAUserPushNotificationsEnabledKey;

/**
 * Background push notification enabled data store key.
 */
extern NSString *const UABackgroundPushNotificationsEnabledKey;

/**
 * Extended push notification permission enabled data store key.
 */
extern NSString *const UAExtendedPushNotificationPermissionEnabledKey;

/**
 * Tags data store key.
 *
 * Note: This should only be used for migration purposes, as
 * tags are now handled directly by UAChannel.
 */
extern NSString *const UAPushLegacyTagsSettingsKey;

/**
 * Badge data store key.
 */
extern NSString *const UAPushBadgeSettingsKey;

/**
 * Quiet time settings data store key.
 */
extern NSString *const UAPushQuietTimeSettingsKey;

/**
 * Quiet enabled data store key.
 */
extern NSString *const UAPushQuietTimeEnabledSettingsKey;

/**
 * Quiet time time zone data store key.
 */
extern NSString *const UAPushTimeZoneSettingsKey;

/**
 * Quiet time settings start key.
 */
extern NSString *const UAPushQuietTimeStartKey;

/**
 * Quiet time settings end key.
 */
extern NSString *const UAPushQuietTimeEndKey;


/**
 * If push tags have been migrated to channel tags data store key.
 */
extern NSString *const UAPushTagsMigratedToChannelTagsKey;



@interface UAPush () <UAPushProviderDelegate>

///---------------------------------------------------------------------------------------
/// @name Push Internal Properties
///---------------------------------------------------------------------------------------

/**
 * Device token as a string.
 */
@property (nonatomic, copy, nullable) NSString *deviceToken;

#if !TARGET_OS_TV
/**
 * Notification that launched the application.
 */
@property (nullable, nonatomic, strong) UNNotificationResponse *launchNotificationResponse;
#endif

/**
 * Indicates whether APNS registration is out of date or not.
 */
@property (nonatomic, assign) BOOL shouldUpdateAPNSRegistration;

/**
 * The preference data store.
 */
@property (nonatomic, strong) UAPreferenceDataStore *dataStore;

/**
 * The current authorized notification settings.
 *
 * Note: this value reflects all the notification settings currently enabled in the
 * Settings app and does not take into account which options were originally requested.
 */
@property (nonatomic, assign) UAAuthorizedNotificationSettings authorizedNotificationSettings;

/**
 * The current authorization status.
 */
@property (nonatomic, assign) UAAuthorizationStatus authorizationStatus;

/**
 * Indicates whether the user has been prompted for notifications or not.
 */
@property (nonatomic, assign) BOOL userPromptedForNotifications;

/**
 * The push registration instance.
 */
@property (nonatomic, strong) id<UAAPNSRegistrationProtocol> pushRegistration;

///---------------------------------------------------------------------------------------
/// @name Push Internal Methods
///---------------------------------------------------------------------------------------

/**
 * Factory method to create a push instance.
 * @param config The Airship config
 * @param dataStore The preference data store.
 * @param channel The channel.
 * @param analytics The analytics instance.
 * @param privacyManager The privacy manager instance.
 * @return A new push instance.
 */
+ (instancetype)pushWithConfig:(UARuntimeConfig *)config
                     dataStore:(UAPreferenceDataStore *)dataStore
                       channel:(UAChannel<UAExtendableChannelRegistration> *)channel
                     analytics:(UAAnalytics<UAExtendableAnalyticsHeaders> *)analytics
                privacyManager:(UAPrivacyManager *)privacyManager;


/**
 * Factory method to create a push instance. For testing
 * @param config The Airship config
 * @param dataStore The preference data store.
 * @param channel The channel.
 * @param analytics The analytics instance.
 * @param appStateTracker The app state tracker
 * @param notificationCenter The notification center.
 * @param pushRegistration The push registration instance.
 * @param application The application.
 * @param dispatcher The dispatcher.
 * @param privacyManager The privacy manager instance.
 * @return A new push instance.
 */
+ (instancetype)pushWithConfig:(UARuntimeConfig *)config
                     dataStore:(UAPreferenceDataStore *)dataStore
                       channel:(UAChannel<UAExtendableChannelRegistration> *)channel
                     analytics:(UAAnalytics<UAExtendableAnalyticsHeaders> *)analytics
               appStateTracker:(UAAppStateTracker *)appStateTracker
            notificationCenter:(NSNotificationCenter *)notificationCenter
              pushRegistration:(id<UAAPNSRegistrationProtocol>)pushRegistration
                   application:(UIApplication *)application
                    dispatcher:(UADispatcher *)dispatcher
                privacyManager:(UAPrivacyManager *)privacyManager;

/**
 * Get the local time zone, considered the default.
 * @return The local time zone.
 */
- (NSTimeZone *)defaultTimeZoneForQuietTime;

/**
 * Used to update channel registration when the background refresh status changes.
 */
- (void)applicationBackgroundRefreshStatusChanged;

/**
 * Returns YES if background push is enabled and configured for the device. Used
 * as the channel's 'background' flag.
 */
- (BOOL)backgroundPushNotificationsAllowed;

/**
 * Returns YES if user notifications are configured and enabled for the device. Used
 * as the channel's 'opt_in' flag.
 */
- (BOOL)userPushNotificationsAllowed;


/**
 * Migrates push tags to channel tags.
 */
- (void)migratePushTagsToChannelTags;

/**
 * Updates the registration with APNS. Call after modifying notification types
 * and user notification categories.
 */
- (void)updateAPNSRegistration:(nonnull void(^)(BOOL success))completionHandler;

/**
 * Updates the authorized notification types.
 */
- (void)updateAuthorizedNotificationTypes;

/**
 * Called to return the presentation options for a notification.
 *
 * @param notification The notification.
 * @return Foreground presentation options.
 */
- (UNNotificationPresentationOptions)presentationOptionsForNotification:(UNNotification *)notification;

#if !TARGET_OS_TV
/**
 * Called when a notification response is received.
 * 
 * @param response The notification response.
 * @param handler The completion handler.
 */
- (void)handleNotificationResponse:(UNNotificationResponse *)response completionHandler:(void (^)(void))handler;
#endif

/**
 * Called when a remote notification is received.
 *
 * @param userInfo The notification info.
 * @param foreground If the notification was recieved in the foreground or not.
 * @param handler The completion handler.
 */
- (void)handleRemoteNotification:(NSDictionary *)userInfo foreground:(BOOL)foreground completionHandler:(void (^)(UIBackgroundFetchResult))handler;

/**
 * Called by the UIApplicationDelegate's application:didRegisterForRemoteNotificationsWithDeviceToken:
 * so UAPush can forward the delegate call to its registration delegate.
 *
 * @param application The application instance.
 * @param deviceToken The APNS device token.
 */
- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;

/**
 * Called by the UIApplicationDelegate's application:didFailToRegisterForRemoteNotificationsWithError:
 * so UAPush can forward the delegate call to its registration delegate.
 *
 * @param application The application instance.
 * @param error An NSError object that encapsulates information why registration did not succeed.
 */
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
