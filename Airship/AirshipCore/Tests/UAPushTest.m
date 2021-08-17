
/* Copyright Airship and Contributors */

#import "UAAirshipBaseTest.h"
#import "UAPush+Internal.h"
#import "UAirship+Internal.h"
#import "UAChannelRegistrationPayload+Internal.h"
#import "UAEvent.h"
#import "UARuntimeConfig.h"
#import "AirshipTests-Swift.h"

@import AirshipCore;

@interface UAPushTest : UAAirshipBaseTest
@property (nonatomic, strong) id mockApplication;
@property (nonatomic, strong) UATestChannel *testChannel;
@property (nonatomic, strong) id mockAppStateTracker;
@property (nonatomic, strong) id mockAirship;
@property (nonatomic, strong) id mockPushDelegate;
@property (nonatomic, strong) id mockRegistrationDelegate;
@property (nonatomic, strong) id mockUAUtils;
@property (nonatomic, strong) id mockDefaultNotificationCategories;
@property (nonatomic, strong) id mockUNNotification;
@property (nonatomic, strong) id mockPushRegistration;
@property (nonatomic, strong) id mockUserInfo;
@property (nonatomic, strong) id mockAnalytics;

@property (nonatomic, strong) UAPush *push;
@property (nonatomic, strong) UAPrivacyManager *privacyManager;
@property (nonatomic, strong) NSNotificationCenter *notificationCenter;
@property (nonatomic, copy) NSDictionary *notification;
@property (nonatomic, copy) NSData *validAPNSDeviceToken;
@property (nonatomic, assign) UAAuthorizationStatus authorizationStatus;
@property (nonatomic, assign) UAAuthorizedNotificationSettings authorizedNotificationSettings;
@property (nonatomic, copy) UAAnalyticsHeadersBlock analyticHeadersBlock;

@end

@implementation UAPushTest

NSString *validDeviceToken = @"0123456789abcdef0123456789abcdef";

- (void)setUp {
    [super setUp];
    
    self.validAPNSDeviceToken = [validDeviceToken dataUsingEncoding:NSASCIIStringEncoding];
    assert([self.validAPNSDeviceToken length] <= 32);

    self.authorizationStatus = UAAuthorizationStatusAuthorized;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsNone;

    self.mockPushRegistration = [self mockForClass:[UAAPNSRegistration class]];
    typedef void (^GetAuthorizedSettingsCompletionBlock)(UAAuthorizedNotificationSettings, UAAuthorizationStatus);
    [[[self.mockPushRegistration stub] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:2];
        GetAuthorizedSettingsCompletionBlock completionHandler = (__bridge GetAuthorizedSettingsCompletionBlock)arg;
        completionHandler(self.authorizedNotificationSettings, self.authorizationStatus);
    }] getAuthorizedSettingsWithCompletionHandler:OCMOCK_ANY];

    self.notificationCenter = [[NSNotificationCenter alloc] init];

    self.notification = @{
        @"aps": @{
                @"alert": @"sample alert!",
                @"badge": @2,
                @"sound": @"cat",
                @"category": @"notificationCategory"
        },
        @"com.urbanairship.interactive_actions": @{
                @"backgroundIdentifier": @{
                        @"backgroundAction": @"backgroundActionValue"
                },
                @"foregroundIdentifier": @{
                        @"foregroundAction": @"foregroundActionValue",
                        @"otherForegroundAction": @"otherForegroundActionValue"

                },
        },
        @"someActionKey": @"someActionValue",
    };

    // Mock the nested apple types with unavailable init methods
    self.mockUNNotification = [self mockForClass:[UNNotification class]];

    //Mock the notification request
    id mockUNNotificationRequest = [self mockForClass:[UNNotificationRequest class]];
    [[[self.mockUNNotification stub] andReturn:mockUNNotificationRequest] request];

    //Mock the notification content
    id mockUNNotificationContent = [self mockForClass:[UNNotificationContent class]];
    [[[mockUNNotificationRequest stub] andReturn:mockUNNotificationContent] content];

    //Mock the notification userInfo
    self.mockUserInfo = [self mockForClass:[NSDictionary class]];
    [[[mockUNNotificationContent stub] andReturn:self.mockUserInfo] userInfo];

    // Set up a mocked application
    self.mockApplication = [self mockForClass:[UIApplication class]];

    self.mockAirship = [self mockForClass:[UAirship class]];

    [UAirship setSharedAirship:self.mockAirship];

    self.mockPushDelegate = [self mockForProtocol:@protocol(UAPushNotificationDelegate)];
    self.mockRegistrationDelegate = [self mockForProtocol:@protocol(UARegistrationDelegate)];

    self.mockDefaultNotificationCategories = [self mockForClass:[UANotificationCategories class]];

    self.testChannel = [[UATestChannel alloc] init];
    self.mockAnalytics = [self mockForClass:[UAAnalytics class]];

    // Capture the analytics header extender
    [[[self.mockAnalytics stub] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:2];
        self.analyticHeadersBlock =  (__bridge UAAnalyticsHeadersBlock)arg;
    }] addAnalyticsHeadersBlock:OCMOCK_ANY];

    self.mockAppStateTracker = [self mockForClass:[UAAppStateTracker class]];

    self.privacyManager = [[UAPrivacyManager alloc] initWithDataStore:self.dataStore defaultEnabledFeatures:UAFeaturesAll];
    
    self.push = [UAPush pushWithConfig:self.config
                             dataStore:self.dataStore
                               channel:self.testChannel
                             analytics:self.mockAnalytics
                       appStateTracker:self.mockAppStateTracker
                    notificationCenter:self.notificationCenter
                      pushRegistration:self.mockPushRegistration
                           application:self.mockApplication
                            dispatcher:[[UATestDispatcher alloc] init]
                        privacyManager:self.privacyManager];

    self.push.registrationDelegate = self.mockRegistrationDelegate;
    self.push.pushRegistration = self.mockPushRegistration;
    self.push.pushNotificationDelegate = self.mockPushDelegate;
}

- (void)tearDown {
    self.push.pushNotificationDelegate = nil;
    self.push.registrationDelegate = nil;
    self.push = nil;

    [self.mockUserInfo stopMocking];
    [self.mockUNNotification stopMocking];
    [super tearDown];
}

- (void)testSetDeviceToken {
    self.push.deviceToken = nil;

    self.push.deviceToken = @"invalid characters";

    XCTAssertNil(self.push.deviceToken, @"setDeviceToken should ignore device tokens with invalid characters.");

    self.push.deviceToken = validDeviceToken;
    XCTAssertEqualObjects(validDeviceToken, self.push.deviceToken, @"setDeviceToken should set tokens with valid characters");

    self.push.deviceToken = nil;
    XCTAssertNil(self.push.deviceToken,
                 @"setDeviceToken should allow a nil device token.");

    self.push.deviceToken = @"";
    XCTAssertEqualObjects(@"", self.push.deviceToken,
                          @"setDeviceToken should do nothing to an empty string");
}

- (void)testAutoBadgeEnabled {
    self.push.autobadgeEnabled = true;
    XCTAssertTrue(self.push.autobadgeEnabled, @"autobadgeEnabled should be enabled when set to YES");
    XCTAssertTrue([self.dataStore boolForKey:UAPushBadgeSettingsKey],
                  @"autobadgeEnabled should be stored in standardUserDefaults");

    self.push.autobadgeEnabled = NO;
    XCTAssertFalse(self.push.autobadgeEnabled, @"autobadgeEnabled should be disabled when set to NO");
    XCTAssertFalse([self.dataStore boolForKey:UAPushBadgeSettingsKey],
                   @"autobadgeEnabled should be stored in standardUserDefaults");
}

/**
 * Test enabling userPushNotificationsEnabled saves its settings
 * to NSUserDefaults and updates apns registration.
 */
- (void)testUserPushNotificationsEnabled {
    // SETUP
    self.push.userPushNotificationsEnabled = NO;

    // EXPECTATIONS
    UANotificationOptions expectedOptions = UANotificationOptionAlert | UANotificationOptionBadge | UANotificationOptionSound;
    [self expectUpdatePushRegistrationWithOptions:expectedOptions categories:self.push.combinedCategories];

    // TEST
    self.push.userPushNotificationsEnabled = YES;

    // VERIFY
    XCTAssertTrue(self.push.userPushNotificationsEnabled,
                  @"userPushNotificationsEnabled should be enabled when set to YES");

    XCTAssertTrue([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                  @"userPushNotificationsEnabled should be stored in standardUserDefaults");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should be called");
}

- (void)testUserPushNotificationsEnabledWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;
    self.push.userPushNotificationsEnabled = NO;

    // EXPECTATIONS
    [self rejectUpdatePushRegistrationWithOptions];

    // TEST
    self.push.userPushNotificationsEnabled = YES;

    // VERIFY
    XCTAssertTrue(self.push.userPushNotificationsEnabled,
                  @"userPushNotificationsEnabled should be enabled when set to YES");

    XCTAssertTrue([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                  @"userPushNotificationsEnabled should be stored in standardUserDefaults");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}

/**
 * Test disabling userPushNotificationsEnabled saves its settings
 * to NSUserDefaults and updates push registration.
 */
- (void)testUserPushNotificationsDisabled {
    // SETUP
    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = validDeviceToken;
    self.push.shouldUpdateAPNSRegistration = NO;

    // Make sure we have previously registered types
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsBadge;

    // Make sure push is set to YES
    XCTAssertTrue(self.push.userPushNotificationsEnabled,
                  @"userPushNotificationsEnabled should default to YES");

    [self expectUpdatePushRegistrationWithOptions:UANotificationOptionNone categories:nil];

    // TEST
    self.push.userPushNotificationsEnabled = NO;

    // VERIFY
    XCTAssertFalse(self.push.userPushNotificationsEnabled,
                   @"userPushNotificationsEnabled should be disabled when set to NO");
    XCTAssertFalse([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                   @"userPushNotificationsEnabled should be stored in standardUserDefaults");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should be called");
}

- (void)testUserPushNotificationsDisabledWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;

    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = validDeviceToken;
    self.push.shouldUpdateAPNSRegistration = NO;

    // Make sure we have previously registered types
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsBadge;

    // Make sure push is set to YES
    XCTAssertTrue(self.push.userPushNotificationsEnabled,
                  @"userPushNotificationsEnabled should default to YES");

    [self rejectUpdatePushRegistrationWithOptions];

    // TEST
    self.push.userPushNotificationsEnabled = NO;

    // VERIFY
    XCTAssertFalse(self.push.userPushNotificationsEnabled,
                   @"userPushNotificationsEnabled should be disabled when set to NO");
    XCTAssertFalse([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                   @"userPushNotificationsEnabled should be stored in standardUserDefaults");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}

/**
 * Test enabling or disabling backgroundPushNotificationsEnabled saves its settings
 * to NSUserDefaults and triggers a channel registration update.
 */
- (void)testBackgroundPushNotificationsEnabled {
    self.push.userPushNotificationsEnabled = YES;
    self.push.backgroundPushNotificationsEnabled = NO;

    // TEST
    self.push.backgroundPushNotificationsEnabled = YES;

    // VERIFY
    XCTAssertTrue([self.dataStore boolForKey:UABackgroundPushNotificationsEnabledKey],
                  @"backgroundPushNotificationsEnabled should be stored in standardUserDefaults");

    // TEST
    self.push.backgroundPushNotificationsEnabled = NO;

    // VERIFY
    XCTAssertFalse([self.dataStore boolForKey:UABackgroundPushNotificationsEnabledKey],
                   @"backgroundPushNotificationsEnabled should be stored in standardUserDefaults");

    XCTAssertTrue(self.testChannel.updateRegistrationCalled);
}

/**
 * Test enabling extended user notification permission saves its settings
 * to NSUserDefaults and updates apns registration.
 */
- (void)testExtendedPushNotificationPermissionEnabled {
    // SETUP
    self.push.userPushNotificationsEnabled = NO;

    // EXPECTATIONS
    UANotificationOptions expectedOptions = UANotificationOptionAlert | UANotificationOptionBadge | UANotificationOptionSound;
    [self expectUpdatePushRegistrationWithOptions:expectedOptions categories:self.push.combinedCategories];

    // TEST
    self.push.userPushNotificationsEnabled = YES;
    self.push.extendedPushNotificationPermissionEnabled = YES;

    // VERIFY
    XCTAssertTrue(self.push.extendedPushNotificationPermissionEnabled,
                  @"extendedPushNotificationPermissionEnabled should be enabled when set to YES");

    XCTAssertTrue([self.dataStore boolForKey:UAExtendedPushNotificationPermissionEnabledKey],
                  @"extendedPushNotificationPermissionEnabled should be stored in standardUserDefaults");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should be called");
}

- (void)testExtendedPushNotificationPermissionEnabledWithUserNotificationsDisabled {
    // SETUP
    self.push.userPushNotificationsEnabled = NO;

    // EXPECTATIONS
    [self rejectUpdatePushRegistrationWithOptions];

    // TEST
    self.push.extendedPushNotificationPermissionEnabled = YES;

    // VERIFY
    XCTAssertFalse(self.push.extendedPushNotificationPermissionEnabled,
                  @"extendedPushNotificationPermissionEnabled should not be enabled when userNotificationsEnabled is set to NO");

    XCTAssertFalse([self.dataStore boolForKey:UAExtendedPushNotificationPermissionEnabledKey],
                  @"extendedPushNotificationPermissionEnabled should not be stored in standardUserDefaults when userNotificationsEnabled is set to NO");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}

- (void)testExtendedPushNotificationPermissionDisabled {
    // SETUP
    self.push.userPushNotificationsEnabled = NO;

    // EXPECTATIONS
    [self rejectUpdatePushRegistrationWithOptions];

    // TEST
    self.authorizationStatus = UAAuthorizationStatusEphemeral;
    self.push.userPushNotificationsEnabled = YES;

    // VERIFY
    XCTAssertFalse(self.push.extendedPushNotificationPermissionEnabled,
                  @"extendedPushNotificationPermissionEnabled should not be enabled when userNotificationsEnabled is set to NO");

    XCTAssertFalse([self.dataStore boolForKey:UAExtendedPushNotificationPermissionEnabledKey],
                  @"extendedPushNotificationPermissionEnabled should not be stored in standardUserDefaults when userNotificationsEnabled is set to NO");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}

- (void)testSetQuietTime {
    [self.push setQuietTimeStartHour:12 startMinute:30 endHour:14 endMinute:58];

    NSDictionary *quietTime = self.push.quietTime;
    XCTAssertEqualObjects(@"12:30", [quietTime valueForKey:UAPushQuietTimeStartKey],
                          @"Quiet time start is not set correctly");

    XCTAssertEqualObjects(@"14:58", [quietTime valueForKey:UAPushQuietTimeEndKey],
                          @"Quiet time end is not set correctly");

    // Change the time zone
    self.push.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:-3600*3];

    // Make sure the hour and minutes are still the same
    quietTime = self.push.quietTime;
    XCTAssertEqualObjects(@"12:30", [quietTime valueForKey:UAPushQuietTimeStartKey],
                          @"Quiet time start is not set correctly");

    XCTAssertEqualObjects(@"14:58", [quietTime valueForKey:UAPushQuietTimeEndKey],
                          @"Quiet time end is not set correctly");


    // Try to set it to an invalid start hour
    [self.push setQuietTimeStartHour:24 startMinute:30 endHour:14 endMinute:58];

    // Make sure the hour and minutes are still the same
    quietTime = self.push.quietTime;
    XCTAssertEqualObjects(@"12:30", [quietTime valueForKey:UAPushQuietTimeStartKey],
                          @"Quiet time start is not set correctly");

    XCTAssertEqualObjects(@"14:58", [quietTime valueForKey:UAPushQuietTimeEndKey],
                          @"Quiet time end is not set correctly");

    // Try to set it to an invalid end minute
    [self.push setQuietTimeStartHour:12 startMinute:30 endHour:14 endMinute:60];

    // Make sure the hour and minutes are still the same
    quietTime = self.push.quietTime;
    XCTAssertEqualObjects(@"12:30", [quietTime valueForKey:UAPushQuietTimeStartKey],
                          @"Quiet time start is not set correctly");

    XCTAssertEqualObjects(@"14:58", [quietTime valueForKey:UAPushQuietTimeEndKey],
                          @"Quiet time end is not set correctly");
}


- (void)testTimeZone {
    self.push.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"EST"];

    XCTAssertEqualObjects([NSTimeZone timeZoneWithAbbreviation:@"EST"],
                          self.push.timeZone,
                          @"timezone is not being set correctly");

    XCTAssertEqualObjects([[NSTimeZone timeZoneWithAbbreviation:@"EST"] name],
                          [self.dataStore stringForKey:UAPushTimeZoneSettingsKey],
                          @"timezone should be stored in standardUserDefaults");

    // Clear the timezone from preferences
    [self.dataStore removeObjectForKey:UAPushTimeZoneSettingsKey];

    XCTAssertEqualObjects([self.push.defaultTimeZoneForQuietTime abbreviation],
                          [self.push.timeZone abbreviation],
                          @"Timezone should default to defaultTimeZoneForQuietTime");

    XCTAssertNil([self.dataStore stringForKey:UAPushTimeZoneSettingsKey],
                 @"timezone should be able to be cleared in standardUserDefaults");
}

/**
 * Test update apns registration when user notifications are enabled.
 */
- (void)testUpdateAPNSRegistrationUserNotificationsEnabled {
    self.push.userPushNotificationsEnabled = YES;
    self.push.shouldUpdateAPNSRegistration = YES;
    self.push.customCategories = [NSSet set];
    self.push.notificationOptions = UANotificationOptionAlert;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // EXPECTATIONS
    [self expectUpdatePushRegistrationWithOptions:self.push.notificationOptions categories:self.push.combinedCategories];

    // TEST
    [self.push updateAPNSRegistration:^(BOOL success) {}];

    // VERIFY
    XCTAssertFalse(self.push.shouldUpdateAPNSRegistration, @"Updating APNS registration should set shouldUpdateAPNSRegistration to NO");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should be called");
}

- (void)testUpdateAPNSRegistrationUserNotificationsEnabledWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;

    self.push.userPushNotificationsEnabled = YES;
    self.push.shouldUpdateAPNSRegistration = YES;
    self.push.customCategories = [NSSet set];
    self.push.notificationOptions = UANotificationOptionAlert;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // EXPECTATIONS
    [self rejectUpdatePushRegistrationWithOptions];

    // TEST
    [self.push updateAPNSRegistration:^(BOOL success) {}];

    // VERIFY
    XCTAssertFalse(self.push.shouldUpdateAPNSRegistration, @"Updating APNS registration should set shouldUpdateAPNSRegistration to NO");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}

/**
 * Test enable push notifications updates APNS registration and receives a completion handler callback.
 */
- (void)testEnablePushNotificationsCompletionHandlerCalled {
    self.push.customCategories = [NSSet set];
    self.push.notificationOptions = UANotificationOptionAlert;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // EXPECTATIONS
    [self expectUpdatePushRegistrationWithOptions:self.push.notificationOptions categories:self.push.combinedCategories];

    XCTestExpectation *delegateCalled = [self expectationWithDescription:@"Delegate called"];
    XCTestExpectation *completionHandlerCalled = [self expectationWithDescription:@"Enable push completion handler called"];
    [[[self.mockRegistrationDelegate expect] andDo:^(NSInvocation *invocation) {
        [delegateCalled fulfill];
    }]  notificationRegistrationFinishedWithAuthorizedSettings:self.authorizedNotificationSettings categories:[OCMArg checkWithBlock:^BOOL(id obj) {
        NSSet *categories = (NSSet *)obj;
        return (categories.count == self.push.combinedCategories.count);
    }] status:UAAuthorizationStatusAuthorized];

    // TEST
    [self.push enableUserPushNotifications:^(BOOL success) {
        [completionHandlerCalled fulfill];
    }];

    // VERIFY
    [self waitForTestExpectations];
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should be called");
    XCTAssertNoThrow([self.mockRegistrationDelegate verify], @"Registration delegate should be called");
}

- (void)testEnablePushNotificationsCompletionHandlerCalledWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;

    self.push.customCategories = [NSSet set];
    self.push.notificationOptions = UANotificationOptionAlert;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // EXPECTATIONS
    [self rejectUpdatePushRegistrationWithOptions];

    XCTestExpectation *delegateCalled = [self expectationWithDescription:@"Delegate called"];
    XCTestExpectation *completionHandlerCalled = [self expectationWithDescription:@"Enable push completion handler called"];
    [[[self.mockRegistrationDelegate expect] andDo:^(NSInvocation *invocation) {
        [delegateCalled fulfill];
    }]  notificationRegistrationFinishedWithAuthorizedSettings:self.authorizedNotificationSettings categories:[OCMArg checkWithBlock:^BOOL(id obj) {
        NSSet *categories = (NSSet *)obj;
        return (categories.count == self.push.combinedCategories.count);
    }] status:UAAuthorizationStatusAuthorized];

    // TEST
    [self.push enableUserPushNotifications:^(BOOL success) {
        [completionHandlerCalled fulfill];
    }];

    // VERIFY
    [self waitForExpectationsWithTimeout:1 handler:nil];
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
    XCTAssertNoThrow([self.mockRegistrationDelegate verify], @"Registration delegate should be called");
}

/**
 * Test setting authorized types to a new type results in a call to the registration delegate
 */
-(void)testSetAuthorizedTypesCallsRegistrationDelegate {

    UAAuthorizedNotificationSettings expectedSettings = 2;

    XCTestExpectation *delegateCalled = [self expectationWithDescription:@"Delegate called"];

    [[[self.mockRegistrationDelegate expect] andDo:^(NSInvocation *invocation) {
        [delegateCalled fulfill];
    }]  notificationAuthorizedSettingsDidChange:expectedSettings];

    // set authorized types
    self.push.authorizedNotificationSettings = expectedSettings;

    [self waitForTestExpectations];

    XCTAssertNoThrow([self.mockRegistrationDelegate verify]);
}

/**
 * Test receiving a call to application:didRegisterForRemoteNotificationsWithDeviceToken: results in that call being forwarded to the registration delegate
 */
-(void)testPushForwardsDidRegisterForRemoteNotificationsWithDeviceTokenToRegistrationDelegateForeground {
    [(UAAppStateTracker *)[[self.mockAppStateTracker stub] andReturnValue:@(UAApplicationStateActive)] state];

    XCTestExpectation *delegateCalled = [self expectationWithDescription:@"Registration delegate called"];

    [[[self.mockRegistrationDelegate expect] andDo:^(NSInvocation *invocation) {
        [delegateCalled fulfill];
    }]  apnsRegistrationSucceededWithDeviceToken:self.validAPNSDeviceToken];

    // TEST
    [self.push application:self.mockApplication didRegisterForRemoteNotificationsWithDeviceToken:self.validAPNSDeviceToken];

    // VERIFY
    [self waitForTestExpectations];

    [self.mockRegistrationDelegate verify];

    // device token also should be set
    XCTAssertTrue([self.push.deviceToken isEqualToString:[UAUtils deviceTokenStringFromDeviceToken:self.validAPNSDeviceToken]]);

    XCTAssertTrue(self.testChannel.updateRegistrationCalled);
}

/**
 * Test receiving a call to application:didRegisterForRemoteNotificationsWithDeviceToken: results in that call being forwarded to the registration delegate
 */
-(void)testPushForwardsDidRegisterForRemoteNotificationsWithDeviceTokenToRegistrationDelegateBackground {
    [(UAAppStateTracker *)[[self.mockAppStateTracker stub] andReturnValue:@(UAApplicationStateBackground)] state];

    // EXPECTATIONS
    [[self.mockRegistrationDelegate expect] apnsRegistrationSucceededWithDeviceToken:self.validAPNSDeviceToken];

    // TEST
    [self.push application:self.mockApplication didRegisterForRemoteNotificationsWithDeviceToken:self.validAPNSDeviceToken];

    // VERIFY
    XCTAssertTrue([self.push.deviceToken isEqualToString:[UAUtils deviceTokenStringFromDeviceToken:self.validAPNSDeviceToken]]);

    [self.mockRegistrationDelegate verify];
    XCTAssertTrue(self.testChannel.updateRegistrationCalled);
}

/**
 * Test receiving a call to application:didFailToRegisterForRemoteNotificationsWithError: results in that call being forwarded to the registration delegate
 */
-(void)testPushForwardsDidFailToRegisterForRemoteNotificationsWithDeviceTokenToRegistrationDelegate {
    NSError *error = [NSError errorWithDomain:@"domain" code:100 userInfo:nil];

    XCTestExpectation *delegateCalled = [self expectationWithDescription:@"Registration delegate called"];

    [[[self.mockRegistrationDelegate expect] andDo:^(NSInvocation *invocation) {
        [delegateCalled fulfill];
    }]  apnsRegistrationFailedWithError:error];

    [self.push application:self.mockApplication didFailToRegisterForRemoteNotificationsWithError:error];

    [self waitForTestExpectations];

    XCTAssertNoThrow([self.mockRegistrationDelegate verify]);
}

/**
 * Test setting requireAuthorizationForDefaultCategories requests the correct
 * defaults user notification categories.
 */
- (void)testRequireAuthorizationForDefaultCategories {
    // Clear the custom categories so we can check only Airship categories in comibinedCategories.
    self.push.customCategories = [NSSet set];

    XCTAssertTrue(self.push.combinedCategories.count);

    self.push.requireAuthorizationForDefaultCategories = YES;
    for (UNNotificationCategory *category in self.push.combinedCategories) {
        for (UNNotificationAction *action in category.actions) {
            // Only check background actions
            if ((action.options & UNNotificationActionOptionForeground) == UANotificationOptionNone) {
                XCTAssertTrue((action.options & UNNotificationActionOptionAuthenticationRequired) > 0, @"Invalid options for action: %@", action.identifier);

            }
        }
    }

    self.push.requireAuthorizationForDefaultCategories = NO;
    for (UNNotificationCategory *category in self.push.combinedCategories) {
        for (UNNotificationAction *action in category.actions) {
            // Only check background actions
            if ((action.options & UNNotificationActionOptionForeground) == UANotificationOptionNone) {
                XCTAssertFalse((action.options & UNNotificationActionOptionAuthenticationRequired) > 0, @"Invalid options for action: %@", action.identifier);

            }
        }
    }
}

/**
 * Test the user notification categories used to register is the union between
 * the default categories and the custom categories.
 */
- (void)testNotificationCategories {
    self.push.userPushNotificationsEnabled = YES;

    UNNotificationCategory *defaultCategory = [UNNotificationCategory categoryWithIdentifier:@"defaultCategory" actions:@[]  intentIdentifiers:@[] options:UNNotificationCategoryOptionNone];
    UNNotificationCategory *customCategory = [UNNotificationCategory categoryWithIdentifier:@"customCategory" actions:@[]  intentIdentifiers:@[] options:UNNotificationCategoryOptionNone];
    UNNotificationCategory *anotherCustomCategory = [UNNotificationCategory categoryWithIdentifier:@"anotherCustomCategory" actions:@[] intentIdentifiers:@[] options:UNNotificationCategoryOptionNone];

    NSSet *defaultSet = [NSSet setWithArray:@[defaultCategory]];
    [[[self.mockDefaultNotificationCategories stub] andReturn:defaultSet] defaultCategoriesWithRequireAuth:self.push.requireAuthorizationForDefaultCategories];

    NSSet *customSet = [NSSet setWithArray:@[customCategory, anotherCustomCategory]];
    self.push.customCategories = customSet;

    NSSet *expectedSet = [NSSet setWithArray:@[defaultCategory, customCategory, anotherCustomCategory]];
    XCTAssertEqualObjects(self.push.combinedCategories, expectedSet);
}


/**
 * Test update apns registration when user notifications are disabled.
 */
- (void)testUpdateAPNSRegistrationUserNotificationsDisabled {
    // Make sure we have previously registered types
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsBadge;

    self.push.userPushNotificationsEnabled = NO;

    // EXPECTATIONS
    [self expectUpdatePushRegistrationWithOptions:UANotificationOptionNone categories:nil];

    // TEST
    [self.push updateAPNSRegistration:^(BOOL success) {}];


    // VERIFY
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should be called");
}

- (void)testUpdateAPNSRegistrationUserNotificationsDisabledWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;

    // Make sure we have previously registered types
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsBadge;

    self.push.userPushNotificationsEnabled = NO;

    // EXPECTATIONS
    [self rejectUpdatePushRegistrationWithOptions];

    // TEST
    [self.push updateAPNSRegistration:^(BOOL success) {}];

    // VERIFY
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}


/**
 * Test update apns does not register for 0 types if already is registered for none.
 */
- (void)testUpdateAPNSRegistrationPushAlreadyDisabled {
    // SETUP
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsNone;
    self.push.userPushNotificationsEnabled = NO;
    [self.push updateAPNSRegistration:^(BOOL success) {}];

    // EXPECTATIONS
    // Make sure we do not register for none, if we are
    // already registered for none or it will prompt the user.
    [[[self.mockPushRegistration reject] ignoringNonObjectArgs] updateRegistrationWithOptions:0 categories:OCMOCK_ANY completionHandler:OCMOCK_ANY];

    // TEST
    [self.push updateAPNSRegistration:^(BOOL success) {}];

    // VERIFY
    [self.mockPushRegistration verify];
}

- (void)testSetBadgeNumberAutoBadgeEnabled {
    // Set the right values so we can check if a device api client call was made or not
    self.push.userPushNotificationsEnabled = YES;
    self.push.autobadgeEnabled = YES;
    self.push.deviceToken = validDeviceToken;

    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE((NSInteger)30)] applicationIconBadgeNumber];

    // EXPECTATIONS
    [[self.mockApplication expect] setApplicationIconBadgeNumber:15];

    // TEST
    [self.push setBadgeNumber:15];

    // VERIFY
    XCTAssertNoThrow([self.mockApplication verify],
                     @"should update application icon badge number when its different");

    XCTAssertTrue(self.testChannel.updateRegistrationCalled);
}

- (void)testSetBadgeNumberNoChange {
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE((NSInteger)30)] applicationIconBadgeNumber];
    [[self.mockApplication reject] setApplicationIconBadgeNumber:30];

    [self.push setBadgeNumber:30];
    XCTAssertNoThrow([self.mockApplication verify],
                     @"should not update application icon badge number if there is no change");
}

- (void)testSetBadgeNumberAutoBadgeDisabled {
    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = validDeviceToken;

    self.push.autobadgeEnabled = NO;

    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE((NSInteger)30)] applicationIconBadgeNumber];
    [[self.mockApplication expect] setApplicationIconBadgeNumber:15];

    self.testChannel.updateRegistrationCalled = NO;
    
    [self.push setBadgeNumber:15];
    XCTAssertNoThrow([self.mockApplication verify],
                     @"should update application icon badge number when its different");

    XCTAssertFalse(self.testChannel.updateRegistrationCalled);
}

- (void)testResetBadge {
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE((NSInteger)30)] applicationIconBadgeNumber];
    [[self.mockApplication expect] setApplicationIconBadgeNumber:0];

    [self.push resetBadge];
    XCTAssertNoThrow([self.mockApplication verify],
                     @"should set application icon badge number to 0");
}

- (void)testResetBadgeNumberNoChange {
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE((NSInteger)0)] applicationIconBadgeNumber];
    [[self.mockApplication reject] setApplicationIconBadgeNumber:0];

    [self.push resetBadge];
    XCTAssertNoThrow([self.mockApplication verify],
                     @"should not update application icon badge number if there is no change");
}

/**
 * Test quietTimeEnabled.
 */
- (void)testSetQuietTimeEnabled {
    [self.dataStore removeObjectForKey:UAPushQuietTimeEnabledSettingsKey];
    XCTAssertFalse(self.push.quietTimeEnabled, @"QuietTime should be disabled");

    self.push.quietTimeEnabled = YES;
    XCTAssertTrue(self.push.quietTimeEnabled, @"QuietTime should be enabled");

    self.push.quietTimeEnabled = NO;
    XCTAssertFalse(self.push.quietTimeEnabled, @"QuietTime should be disabled");
}


/**
 * Test setting the default backgroundPushNotificationEnabled value.
 */
- (void)testBackgroundPushNotificationsEnabledByDefault {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    self.push.backgroundPushNotificationsEnabledByDefault = YES;
    XCTAssertTrue(self.push.backgroundPushNotificationsEnabled, @"default background notification value not taking affect.");

    self.push.backgroundPushNotificationsEnabledByDefault = NO;
    XCTAssertFalse(self.push.backgroundPushNotificationsEnabled, @"default background notification value not taking affect.");
#pragma clang diagnostic pop

}

/**
 * Test update registration when shouldUpdateAPNSRegistration and channel registration.
 */
- (void)testUpdateRegistrationShouldUpdateAPNS {
    self.push.shouldUpdateAPNSRegistration = YES;

    [self.push updateRegistration];

    // Verify it reset the flag
    XCTAssertFalse(self.push.shouldUpdateAPNSRegistration, @"updateRegistration should handle APNS registration updates if shouldUpdateAPNSRegistration is YES.");
    
    XCTAssertTrue(self.testChannel.updateRegistrationCalled);
}

/**
 * Test when backgroundPushNotificationsAllowed is YES when
 * device token is available, remote-notification background mode is enabled,
 * backgroundRefreshStatus is allowed, backgroundPushNotificationsEnabled is
 * enabled and pushTokenRegistrationEnabled is YES.
 */
- (void)testBackgroundPushNotificationsAllowed {
    self.push.deviceToken = validDeviceToken;
    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];

    XCTAssertTrue(self.push.backgroundPushNotificationsAllowed,
                  @"BackgroundPushNotificationsAllowed should be YES");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when the device token is
 * missing.
 */
- (void)testBackgroundPushNotificationsDisallowedNoDeviceToken {
    self.push.userPushNotificationsEnabled = YES;
    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];

    self.push.deviceToken = nil;
    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when backgroundPushNotificationsAllowed
 * is disabled.
 */
- (void)testBackgroundPushNotificationsDisallowedDisabled {
    self.push.userPushNotificationsEnabled = YES;
    [[[self.mockAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    self.push.deviceToken = validDeviceToken;


    self.push.backgroundPushNotificationsEnabled = NO;
    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when the application is not
 * configured with remote-notification background mode.
 */
- (void)testBackgroundPushNotificationsDisallowedBackgroundNotificationDisabled {
    self.push.userPushNotificationsEnabled = YES;
    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    self.push.deviceToken = validDeviceToken;

    [[[self.mockAirship stub] andReturnValue:OCMOCK_VALUE(NO)] remoteNotificationBackgroundModeEnabled];
    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when backgroundRefreshStatus is invalid.
 */
- (void)testBackgroundPushNotificationsDisallowedInvalidBackgroundRefreshStatus {
    self.push.userPushNotificationsEnabled = YES;
    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];
    self.push.deviceToken = validDeviceToken;

    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusRestricted)] backgroundRefreshStatus];

    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test that backgroundPushNotificationsAllowed is NO when not registered for remote notifications.
 */
- (void)testBackgroundPushNotificationsDisallowedNotRegisteredForRemoteNotifications {
    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    [[[self.mockAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    self.push.deviceToken = validDeviceToken;

    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(NO)] isRegisteredForRemoteNotifications];
    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when
 * pushTokenRegistrationEnabled is NO.
 */
- (void)testBackgroundPushNotificationsPushDisabled {
    self.push.deviceToken = validDeviceToken;
    self.push.backgroundPushNotificationsEnabled = YES;
    [self.privacyManager disableFeatures:UAFeaturesPush];

    [[[self.mockAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];

    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test that UserPushNotificationAllowed is NO when there are no authorized notification types set
 */
-(void)testUserPushNotificationsAllowedNo {
    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = validDeviceToken;
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];

    XCTAssertFalse(self.push.userPushNotificationsAllowed,
                   @"UserPushNotificationsAllowed should be NO");
}

- (void)testApplicationDidTransitionToForegroundWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;
    self.push.userPushNotificationsEnabled = YES;
    self.push.notificationOptions = UANotificationOptionAlert;

    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;
    UAAuthorizedNotificationSettings expectedSettings = UAAuthorizedNotificationSettingsAlert;

    [self rejectUpdatePushRegistrationWithOptions];

    [(UAAppStateTracker *)[[self.mockAppStateTracker expect] andReturnValue:@(UAApplicationStateActive)] state];

    // TEST
    [self.notificationCenter postNotificationName:UAAppStateTracker.didTransitionToForeground object:nil];

    // VERIFY
    XCTAssertTrue(self.push.userPromptedForNotifications);
    XCTAssertEqual(self.push.authorizedNotificationSettings, expectedSettings);

    XCTAssertTrue(self.testChannel.updateRegistrationCalled);
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}

-(void)testApplicationBackgroundRefreshStatusChangedBackgroundAvailable {
    // SETUP
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];

    // EXPECTATIONS
    [[self.mockApplication expect] registerForRemoteNotifications];

    // TEST
    [self.push applicationBackgroundRefreshStatusChanged];

    // VERIFY
    XCTAssertNoThrow([self.mockApplication verify], @"[UIApplication registerForRemoteNotifications] should be called");
}

-(void)testApplicationBackgroundRefreshStatusChangedBackgroundDenied {
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusDenied)] backgroundRefreshStatus];

    [self.push applicationBackgroundRefreshStatusChanged];

    XCTAssertTrue(self.testChannel.updateRegistrationCalled);
}

-(void)testApplicationBackgroundRefreshStatusChangedBackgroundDeniedWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusDenied)] backgroundRefreshStatus];
    // set an option so channel registration happens
    self.push.notificationOptions = UANotificationOptionSound;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsSound;

    // EXPECTATIONS
    [self rejectUpdatePushRegistrationWithOptions];

    // TEST
    [self.push applicationBackgroundRefreshStatusChanged];

    // VERIFY
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}

/**
 * Test applicationDidEnterBackground clears the notification.
 */
- (void)testApplicationDidEnterBackground {
    self.push.launchNotificationResponse = [self mockForClass:[UNNotificationResponse class]];

    [self.notificationCenter postNotificationName:UAAppStateTracker.didEnterBackgroundNotification object:nil];

    XCTAssertNil(self.push.launchNotificationResponse, @"applicationDidEnterBackground should clear the launch notification");
}

- (void)testmigratePushTagsToChannelTags {
    [self.dataStore setObject:@[@"cool", @"rad"] forKey:UAPushLegacyTagsSettingsKey];

    NSArray *expectedTags = @[@"cool", @"rad"];

    // Force a migration
    [self.dataStore removeObjectForKey:UAPushTagsMigratedToChannelTagsKey];

    [self.push migratePushTagsToChannelTags];

    XCTAssertEqualObjects(self.testChannel.tags, expectedTags);
    XCTAssertTrue([self.dataStore boolForKey:UAPushTagsMigratedToChannelTagsKey]);
    XCTAssertNil([self.dataStore objectForKey:UAPushLegacyTagsSettingsKey]);
}

- (void)testMigratePushTagsToChannelTagsCombined {
    [self.dataStore setObject:@[@"cool", @"rad"] forKey:UAPushLegacyTagsSettingsKey];

    self.testChannel.tags = @[@"not cool", @"not rad"];

    // Force a migration
    [self.dataStore removeObjectForKey:UAPushTagsMigratedToChannelTagsKey];
    
    [self.push migratePushTagsToChannelTags];

    XCTAssertTrue([self.dataStore boolForKey:UAPushTagsMigratedToChannelTagsKey]);
    XCTAssertNil([self.dataStore objectForKey:UAPushLegacyTagsSettingsKey]);
    
    NSArray *expected = @[@"cool", @"rad", @"not cool", @"not rad"];
    XCTAssertEqualObjects([NSSet setWithArray:self.testChannel.tags], [NSSet setWithArray:expected]);
}

- (void)testMigratePushTagsToChannelTagsAlreadyMigrated {
    self.testChannel.tags = @[@"some-random-value"];
    [self.dataStore setBool:YES forKey:UAPushTagsMigratedToChannelTagsKey];
    [self.push migratePushTagsToChannelTags];

    XCTAssertEqualObjects(self.testChannel.tags, @[@"some-random-value"]);
}

/**
 * Test handleRemoteNotification when auto badge is disabled does
 * not set the badge on the application
 */
- (void)testHandleNotificationAutoBadgeDisabled {
    self.push.autobadgeEnabled = NO;
    [[self.mockApplication reject] setApplicationIconBadgeNumber:2];

    // TEST
    [self.push handleRemoteNotification:self.notification foreground:YES completionHandler:^(UIBackgroundFetchResult result) {}];
    [self.push handleRemoteNotification:self.notification foreground:NO completionHandler:^(UIBackgroundFetchResult result) {}];

    // VERIFY
    XCTAssertNoThrow([self.mockApplication verify]);
}

/**
 * Test handleRemoteNotification when auto badge is enabled sets the badge
 * only when a notification comes in while the app is in the foreground
 */
- (void)testHandleNotificationAutoBadgeEnabled {
    self.push.autobadgeEnabled = YES;

    [[self.mockApplication expect] setApplicationIconBadgeNumber:2];
    [self.push handleRemoteNotification:self.notification foreground:YES completionHandler:^(UIBackgroundFetchResult result) {}];
    XCTAssertNoThrow([self.mockApplication verify], @"[UIApplication setApplicationIconBadgeNumber] should be called");

    [[self.mockApplication reject] setApplicationIconBadgeNumber:2];
    [self.push handleRemoteNotification:self.notification foreground:NO completionHandler:^(UIBackgroundFetchResult result) {}];
    XCTAssertNoThrow([self.mockApplication verify], @"[UIApplication setApplicationIconBadgeNumber] should not be called");
}

/**
 * Test handleNotificationResponse sets the launched notificaitno response if
 * its the default identifier.
 */
- (void)testHandleNotificationLaunchNotification {
    self.push.launchNotificationResponse = nil;

    id response = [self mockForClass:[UNNotificationResponse class]];
    [[[response stub] andReturn:self.mockUNNotification] notification];
    [[[response stub] andReturn:UNNotificationDefaultActionIdentifier] actionIdentifier];

    [self.push handleNotificationResponse:response completionHandler:^{}];

    XCTAssertEqual(self.push.launchNotificationResponse, response);
}

/**
 * Test handleRemoteNotification when foreground and autobadge is enabled.
 */
- (void)testHandleRemoteNotificationForegroundAutobadgeEnabled {
    self.push.autobadgeEnabled = YES;

    // Application should set icon badge number when autobadge is enabled
    [[self.mockApplication expect] setApplicationIconBadgeNumber:2];

    __block NSNotification *notification;

    XCTestExpectation *notificationFired = [self expectationWithDescription:@"Notification event fired"];
    [self.notificationCenter addObserverForName:UAReceivedForegroundNotificationEvent object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        notification = note;
        [notificationFired fulfill];
    }];

    [[self.mockPushDelegate expect] receivedForegroundNotification:self.notification completionHandler:[OCMArg checkWithBlock:^BOOL(id obj) {
        void (^handler)(void) = obj;
        handler();
        return YES;
    }]];

    [[self.mockPushDelegate reject] receivedBackgroundNotification:self.notification completionHandler:OCMOCK_ANY];

    XCTestExpectation *completionHandlerCalledExpectation = [self expectationWithDescription:@"handleRemoteNotification completionHandler should be called"];

    // TEST
    [self.push handleRemoteNotification:self.notification foreground:YES completionHandler:^(UIBackgroundFetchResult result) {
        [completionHandlerCalledExpectation fulfill];
    }];

    // VERIFY
    [self waitForTestExpectations];

    XCTAssertEqualObjects(self.notification, notification.userInfo);

    [self.mockApplication verify];
    [self.mockPushDelegate verify];
}

/**
 * Test handleRemoteNotification when foreground and autobadge is disabled.
 */
- (void)testHandleRemoteNotificationForegroundAutobadgeDisabled {
    self.push.autobadgeEnabled = NO;

    // Application should set icon badge number when autobadge is enabled
    [[self.mockApplication reject] setApplicationIconBadgeNumber:2];

    __block NSNotification *notification;

    XCTestExpectation *notificationFired = [self expectationWithDescription:@"Notification event fired"];
    [self.notificationCenter addObserverForName:UAReceivedForegroundNotificationEvent object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        notification = note;
        [notificationFired fulfill];
    }];

    [[self.mockPushDelegate expect] receivedForegroundNotification:self.notification completionHandler:[OCMArg checkWithBlock:^BOOL(id obj) {
        void (^handler)(void) = obj;
        handler();
        return YES;
    }]];

    [[self.mockPushDelegate reject] receivedBackgroundNotification:self.notification completionHandler:OCMOCK_ANY];

    XCTestExpectation *completionHandlerCalledExpectation = [self expectationWithDescription:@"handleRemoteNotification completionHandler should be called"];

    // TEST
    [self.push handleRemoteNotification:self.notification foreground:YES completionHandler:^(UIBackgroundFetchResult result) {
        [completionHandlerCalledExpectation fulfill];
    }];

    // VERIFY
    [self waitForTestExpectations];

    XCTAssertEqualObjects(self.notification, notification.userInfo);

    [self.mockApplication verify];
    XCTAssertNoThrow([self.mockPushDelegate verify], @"push delegate should be called");
}

/**
 * Test handleRemoteNotification when background push.
 */
- (void)testHandleRemoteNotificationBackground {
    __block NSNotification *notification;

    XCTestExpectation *notificationFired = [self expectationWithDescription:@"Notification event fired"];
    [self.notificationCenter addObserverForName:UAReceivedBackgroundNotificationEvent object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        notification = note;
        [notificationFired fulfill];
    }];

    [[self.mockPushDelegate reject] receivedForegroundNotification:self.notification completionHandler:OCMOCK_ANY];

    [[self.mockPushDelegate expect] receivedBackgroundNotification:self.notification completionHandler:[OCMArg checkWithBlock:^BOOL(id obj) {
        void (^handler)(void) = obj;
        handler();
        return YES;
    }]];

    XCTestExpectation *completionHandlerCalledExpectation = [self expectationWithDescription:@"handleRemoteNotification completionHandler should be called"];

    // TEST
    [self.push handleRemoteNotification:self.notification foreground:NO completionHandler:^(UIBackgroundFetchResult result) {
        [completionHandlerCalledExpectation fulfill];
    }];

    // VERIFY
    [self waitForTestExpectations];

    XCTAssertEqualObjects(self.notification, notification.userInfo);
    XCTAssertNoThrow([self.mockPushDelegate verify], @"push delegate should be called");
}

/**
 * Test handleRemoteNotification when no delegate is set.
 */
- (void)testHandleRemoteNotificationNoDelegate {
    self.push.pushNotificationDelegate = nil;

    XCTestExpectation *completionHandlerCalledExpectation = [self expectationWithDescription:@"handleRemoteNotification completionHandler should be called"];

    __block NSNotification *notification;

    XCTestExpectation *notificationFired = [self expectationWithDescription:@"Notification event fired"];
    [self.notificationCenter addObserverForName:UAReceivedForegroundNotificationEvent object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        notification = note;
        [notificationFired fulfill];
    }];

    // TEST
    [self.push handleRemoteNotification:self.notification foreground:YES completionHandler:^(UIBackgroundFetchResult result) {
        [completionHandlerCalledExpectation fulfill];
        XCTAssertEqual(result, UIBackgroundFetchResultNoData);
    }];

    // VERIFY
    [self waitForTestExpectations];
    XCTAssertEqualObjects(self.notification, notification.userInfo);
}

/**
 * Test handleNotificationResponse when launched from push.
 */
- (void)testHandleNotificationResponseLaunchedFromPush {
    id response = [self mockForClass:[UNTextInputNotificationResponse class]];
    [[[response stub] andReturn:self.mockUNNotification] notification];
    [[[response stub] andReturn:UNNotificationDefaultActionIdentifier] actionIdentifier];
    [[[response stub] andReturn:@"test_response_text"] userText];

    // delegate needs to be unresponsive to receivedNotificationResponse callback
    self.push.pushNotificationDelegate = nil;

    __block NSNotification *notification;

    XCTestExpectation *notificationFired = [self expectationWithDescription:@"Notification event fired"];
    [self.notificationCenter addObserverForName:UAReceivedNotificationResponseEvent object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        notification = note;
        [notificationFired fulfill];
    }];

    // Call handleNotificationResponse
    [self.push handleNotificationResponse:response completionHandler:^{
    }];

    [self waitForTestExpectations];

    // Check that the launchNotificationReponse is set to expected response
    XCTAssertEqualObjects(self.push.launchNotificationResponse, response);
}

/**
 * Test handleNotificationResponse when not launched from push.
 */
- (void)testHandleNotificationResponseNotLaunchedFromPush {
    id response = [self mockForClass:[UNTextInputNotificationResponse class]];
    [[[response stub] andReturn:self.mockUNNotification] notification];
    [[[response stub] andReturn:@"test_action_identifier"] actionIdentifier];
    [[[response stub] andReturn:@"test_response_text"] userText];

    [[self.mockPushDelegate expect] receivedNotificationResponse:OCMOCK_ANY completionHandler:[OCMArg checkWithBlock:^BOOL(id obj) {
        void (^handler)(void) = obj;
        handler();
        return YES;
    }]];

    XCTestExpectation *completionHandlerCalledExpectation = [self expectationWithDescription:@"handleRemoteNotification completionHandler should be called"];

    __block NSNotification *notification;

    XCTestExpectation *notificationFired = [self expectationWithDescription:@"Notification event fired"];
    [self.notificationCenter addObserverForName:UAReceivedNotificationResponseEvent object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        notification = note;
        [notificationFired fulfill];
    }];

    // TEST
    [self.push handleNotificationResponse:response completionHandler:^{
        [completionHandlerCalledExpectation fulfill];
    }];

    // VERIFY
    [self waitForTestExpectations];
    XCTAssertNil(self.push.launchNotificationResponse);
    XCTAssertNoThrow([self.mockPushDelegate verify], @"push delegate should be called");
    XCTAssertEqualObjects(response, notification.userInfo[UAReceivedNotificationResponseEventResponseKey]);
}

/**
 * Test handleNotificationResponse no delegate set.
 */
- (void)testHandleNotificationResponse {
    self.push.pushNotificationDelegate = nil;

    id response = [self mockForClass:[UNTextInputNotificationResponse class]];
    [[[response stub] andReturn:self.mockUNNotification] notification];
    [[[response stub] andReturn:@"test_action_identifier"] actionIdentifier];
    [[[response stub] andReturn:@"test_response_text"] userText];

    XCTestExpectation *completionHandlerCalledExpectation = [self expectationWithDescription:@"handleRemoteNotification completionHandler should be called"];

    // TEST
    [self.push handleNotificationResponse:response completionHandler:^{
        [completionHandlerCalledExpectation fulfill];
    }];

    // VERIFY
    [self waitForTestExpectations];
    XCTAssertNil(self.push.launchNotificationResponse);
}

/**
 * Test presentationOptionsForNotification when delegate method is unimplemented.
 */
- (void)testPresentationOptionsForNotificationNoDelegate {

    self.push.defaultPresentationOptions = UNNotificationPresentationOptionAlert;
    
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        self.push.defaultPresentationOptions = UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner;
    }
    
    self.push.pushNotificationDelegate = nil;

    [[[self.mockAirship stub] andReturn:self.push] push];

    UNNotificationPresentationOptions presentationOptions = [self.push presentationOptionsForNotification:self.mockUNNotification];

    XCTAssertEqual(presentationOptions, self.push.defaultPresentationOptions);
}

/**
 * Test presentationOptionsForNotification when delegate method is implemented.
 */
- (void)testPresentationOptionsForNotification {
    [[[self.mockAirship stub] andReturn:self.push] push];

    
    if (@available(iOS 14.0, *)) {
        [[[self.mockPushDelegate stub] andReturnValue:OCMOCK_VALUE(UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner)] extendPresentationOptions:UNNotificationPresentationOptionNone notification:self.mockUNNotification];
    } else {
        [[[self.mockPushDelegate stub] andReturnValue:OCMOCK_VALUE(UNNotificationPresentationOptionAlert)] extendPresentationOptions:UNNotificationPresentationOptionNone notification:self.mockUNNotification];
    }

    UNNotificationPresentationOptions result = [self.push presentationOptionsForNotification:self.mockUNNotification];
    
    if (@available(iOS 14.0, *)) {
        XCTAssertEqual(result, UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner);
    } else {
        XCTAssertEqual(result, UNNotificationPresentationOptionAlert);
    }
}

/**
 * Test presentationOptionsForNotification when notification contains foreground options and delegate method is unimplemented.
 */
- (void)testPresentationOptionsForNotificationWithForegroundOptionsWithoutDelegate {
    // SETUP
    NSArray *array = @[@"alert", @"sound", @"badge"];
    
    if (@available(iOS 14.0, *)) {
        array = @[@"list", @"banner", @"sound", @"badge"];
    }
    
    [[[self.mockUserInfo stub] andReturnValue:OCMOCK_VALUE(array)] objectForKey:@"com.urbanairship.foreground_presentation"];
    self.push.pushNotificationDelegate = nil;
    
        
    // EXPECTATIONS
    UNNotificationPresentationOptions options = UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionBadge;
    
    if (@available(iOS 14.0, *)) {
        options = UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionBadge;
    }
    
    // TEST
    UNNotificationPresentationOptions result = [self.push presentationOptionsForNotification:self.mockUNNotification];
    
    // VERIFY
    XCTAssertEqual(result, options);
}

/**
 * Test presentationOptionsForNotification when notification foreground options array is empty and delegate method is unimplemented.
 */
- (void)testPresentationOptionsForNotificationWithoutForegroundOptionsWithoutDelegate {
    // SETUP
    NSArray *array = @[];
    [[[self.mockUserInfo stub] andReturnValue:OCMOCK_VALUE(array)] objectForKey:@"com.urbanairship.foreground_presentation"];
    
    self.push.defaultPresentationOptions = UNNotificationPresentationOptionAlert;
    
    if (@available(iOS 14.0, *)) {
        self.push.defaultPresentationOptions = UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner;
    }
    
    self.push.pushNotificationDelegate = nil;

    // EXPECTATIONS
    UNNotificationPresentationOptions options = UNNotificationPresentationOptionAlert;
    
    if (@available(iOS 14.0, *)) {
        options = UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner;
    }

    // TEST
    UNNotificationPresentationOptions result = [self.push presentationOptionsForNotification:self.mockUNNotification];

    // VERIFY
    XCTAssertEqual(result, options);
}


/**
 * Test on first launch when user has not been prompted for notification.
 */
- (void)testNotificationNotPrompted {
    self.push.authorizedNotificationSettings = UAAuthorizedNotificationSettingsNone;
    XCTAssertFalse(self.push.userPromptedForNotifications);
}

/**
 * Test types are not set a second time when they are the same.
 */
- (void)testNotificationOptionsAuthorizedTwice {
    // SETUP
    self.push.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // EXPECTATIONS
    [[self.mockRegistrationDelegate reject] notificationAuthorizedSettingsDidChange:UAAuthorizedNotificationSettingsAlert];

    // TEST
    self.push.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // VERIFY
    XCTAssertNoThrow([self.mockRegistrationDelegate verify]);
    XCTAssertFalse(self.push.userPromptedForNotifications);
}

/**
 * Test registering a device token.
 */
- (void)testRegisteredDeviceToken {
    // SETUP
    [(UAAppStateTracker *)[[self.mockAppStateTracker stub] andReturnValue:@(UAApplicationStateBackground)] state];

    NSData *token = [@"some-token" dataUsingEncoding:NSASCIIStringEncoding];

    // TEST
    [self.push application:self.mockApplication didRegisterForRemoteNotificationsWithDeviceToken:token];

    // VERIFY
    // Expect UAPush to receive the device token string
    // 736f6d652d746f6b656e = "some-token" in hex
    XCTAssertTrue([@"736f6d652d746f6b656e" isEqualToString:self.push.deviceToken]);

    XCTAssertTrue(self.testChannel.updateRegistrationCalled);
}

-(void)testDidRegisterForRemoteNotificationsWithDeviceTokenDoesntRegisterChannelWhenInBackground {
    self.testChannel.identifier = @"some-channel";
    // SETUP
    [(UAAppStateTracker *)[[self.mockAppStateTracker stub] andReturnValue:@(UAApplicationStateBackground)] state];

    self.testChannel.updateRegistrationCalled = NO;
    
    // TEST
    NSData *token = [@"some-token" dataUsingEncoding:NSASCIIStringEncoding];
    [self.push application:self.mockApplication didRegisterForRemoteNotificationsWithDeviceToken:token];

    // VERIFY
    // Expect UAPush to receive the device token string
    // 736f6d652d746f6b656e = "some-token" in hex
    XCTAssertTrue([@"736f6d652d746f6b656e" isEqualToString:self.push.deviceToken]);

    XCTAssertFalse(self.testChannel.updateRegistrationCalled);
}

-(void)testAuthorizedNotificationSettingsWhenPushNotificationsDisabled {
    // SETUP
    self.push.userPushNotificationsEnabled = NO;
    self.push.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // TEST & VERIFY
    XCTAssert(self.push.authorizedNotificationSettings == UAAuthorizedNotificationSettingsAlert);
}

- (void)testEnablingDisabledPushUpdatesRegistration {
    // Setup
    self.testChannel.identifier = @"someChannelID";
    self.push.componentEnabled = NO;
    self.push.userPushNotificationsEnabled = YES;

    // EXPECTATIONS
    [self expectUpdatePushRegistrationWithOptions:self.push.notificationOptions categories:self.push.combinedCategories];

    // Test
    self.push.componentEnabled = YES;

    [self.mockPushRegistration verify];
}

- (void)testEnablingDisabledPushDoesNotUpdateRegistrationWhenAppIsHandlingAuthorization {
    // Setup
    self.config.requestAuthorizationToUseNotifications = NO;
    self.push.userPushNotificationsEnabled = YES;
    self.testChannel.identifier = @"someChannelID";
    self.push.componentEnabled = NO;

    // EXPECTATIONS
    [self rejectUpdatePushRegistrationWithOptions];

    // Test
    self.push.componentEnabled = YES;

    // verify
    [self.mockPushRegistration verify];
}

- (void)testUpdateAuthorizedNotificationTypesUpdatesChannelRegistrationWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert | UAAuthorizedNotificationSettingsBadge;
    self.authorizationStatus = UAAuthorizationStatusAuthorized;


    // TEST
    [self.push updateAuthorizedNotificationTypes];

    // VERIFY
    XCTAssertTrue(self.testChannel.updateRegistrationCalled);
}

/**
 * Test registration payload.
 */
- (void)testRegistrationPayload {
    NSData *token = [@"some-token" dataUsingEncoding:NSASCIIStringEncoding];
    [self.push application:self.mockApplication didRegisterForRemoteNotificationsWithDeviceToken:token];

    self.push.quietTimeEnabled = YES;
    self.push.timeZone = [NSTimeZone timeZoneWithName:@"Pacific/Auckland"];
    [self.push setQuietTimeStartHour:12 startMinute:30 endHour:14 endMinute:58];

    UAChannelRegistrationPayload *payload = [[UAChannelRegistrationPayload alloc] init];
    XCTestExpectation *extendedPayload = [self expectationWithDescription:@"extended payload"];
    [self.testChannel extendPayload:payload completionHandler:^(UAChannelRegistrationPayload * payload) {
        XCTAssertEqualObjects(@"736f6d652d746f6b656e", payload.pushAddress);
        XCTAssertEqualObjects(self.push.quietTime, payload.quietTime);
        XCTAssertEqualObjects(@"Pacific/Auckland", payload.quietTimeTimeZone);
        [extendedPayload fulfill];
    }];

    [self waitForTestExpectations];
}


- (void)testRegistrationPayloadQuietTimeDisabled {
    self.push.quietTimeEnabled = NO;
    self.push.timeZone = [NSTimeZone timeZoneWithName:@"Pacific/Auckland"];
    [self.push setQuietTimeStartHour:12 startMinute:30 endHour:14 endMinute:58];

    UAChannelRegistrationPayload *payload = [[UAChannelRegistrationPayload alloc] init];
    XCTestExpectation *extendedPayload = [self expectationWithDescription:@"extended payload"];
    [self.testChannel extendPayload:payload completionHandler:^(UAChannelRegistrationPayload * payload) {
        XCTAssertNil(payload.quietTime);
        XCTAssertNil(payload.quietTimeTimeZone);
        [extendedPayload fulfill];
    }];

    [self waitForTestExpectations];
}

/**
 * Test disable token registration in the CRA payload.
 */
- (void)testRegistrationPayloadDisabledTokenRegistration {
    NSData *token = [@"some-token" dataUsingEncoding:NSASCIIStringEncoding];
    [self.push application:self.mockApplication didRegisterForRemoteNotificationsWithDeviceToken:token];

    [self.privacyManager disableFeatures:UAFeaturesPush];

    UAChannelRegistrationPayload *payload = [[UAChannelRegistrationPayload alloc] init];
    XCTestExpectation *extendedPayload = [self expectationWithDescription:@"extended payload"];
    [self.testChannel extendPayload:payload completionHandler:^(UAChannelRegistrationPayload * payload) {
            XCTAssertNil(payload.pushAddress);
            [extendedPayload fulfill];
    }];

    [self waitForTestExpectations];
}

/**
 * Test auto badge is added to the CRA payload.
 */
- (void)testRegistrationPayloadAutoBadgeEnabled {
    self.push.autobadgeEnabled = YES;
    [[[self.mockApplication stub] andReturnValue:@(30)] applicationIconBadgeNumber];

    UAChannelRegistrationPayload *payload = [[UAChannelRegistrationPayload alloc] init];
    XCTestExpectation *extendedPayload = [self expectationWithDescription:@"extended payload"];
    [self.testChannel extendPayload:payload completionHandler:^(UAChannelRegistrationPayload *payload) {
        XCTAssertEqualObjects(payload.badge, @(30));
            [extendedPayload fulfill];
    }];

    [self waitForTestExpectations];
}

- (void)testAnalyticsHeaders {
    self.push.deviceToken = validDeviceToken;

    NSDictionary *headers = self.analyticHeadersBlock();
    id expected = @{
        @"X-UA-Push-Address": validDeviceToken,
        @"X-UA-Channel-Opted-In": @"false",
        @"X-UA-Channel-Background-Enabled": @"false",
        @"X-UA-Notification-Prompted":@"false"
    };

    XCTAssertEqualObjects(expected, headers);
}

- (void)testAnalyticsHeadersPushDisabled {
    self.push.deviceToken = validDeviceToken;
    [self.privacyManager disableFeatures:UAFeaturesPush];

    NSDictionary *headers = self.analyticHeadersBlock();
    id expected = @{
        @"X-UA-Channel-Opted-In": @"false",
        @"X-UA-Channel-Background-Enabled": @"false"
    };

    XCTAssertEqualObjects(expected, headers);
}

- (void)testChannelExtensionWaitsForDeviceToken {
    self.push.deviceToken = nil;
    [[[self.mockApplication stub] andReturnValue:@(YES)] isRegisteredForRemoteNotifications];

    UAChannelRegistrationPayload *payload = [[UAChannelRegistrationPayload alloc] init];
    XCTestExpectation *extendedPayload = [self expectationWithDescription:@"extended payload"];
    [self.testChannel extendPayload:payload completionHandler:^(UAChannelRegistrationPayload *payload) {
        [extendedPayload fulfill];
    }];

    [UADispatcher.main dispatchAsync:^{
        self.push.deviceToken = validDeviceToken;
    }];

    [self waitForTestExpectations];

    XCTAssertEqual(validDeviceToken, payload.pushAddress);
}

- (void)expectUpdatePushRegistrationWithOptions:(UANotificationOptions)expectedOptions categories:(NSSet<UNNotificationCategory *> *)expectedCategories {
    [[[[self.mockPushRegistration expect] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:2];
        UANotificationOptions options = (UANotificationOptions)arg;
        XCTAssertTrue(expectedOptions == options);

        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(BOOL) = (__bridge void(^)(BOOL))arg;

        if (completionHandler) {
            completionHandler(YES);
        }

        [self.mockRegistrationDelegate notificationRegistrationFinishedWithAuthorizedSettings:self.authorizedNotificationSettings categories:expectedCategories status:UAAuthorizationStatusAuthorized];
    }] ignoringNonObjectArgs] updateRegistrationWithOptions:0 categories:[OCMArg checkWithBlock:^BOOL(NSSet<UNNotificationCategory *> *categories) {
        return (expectedCategories.count == categories.count);
    }] completionHandler:OCMOCK_ANY];
}

- (void)rejectUpdatePushRegistrationWithOptions {
    [[[self.mockPushRegistration reject] ignoringNonObjectArgs] updateRegistrationWithOptions:0 categories:OCMOCK_ANY completionHandler:OCMOCK_ANY];
}

@end


