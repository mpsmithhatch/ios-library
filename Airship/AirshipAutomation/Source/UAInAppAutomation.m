/* Copyright Airship and Contributors */

#import "UAInAppAutomation+Internal.h"
#import "UAInAppMessageManager+Internal.h"
#import "UASchedule+Internal.h"
#import "UAScheduleTriggerContext+Internal.h"
#import "UAInAppMessage+Internal.h"
#import "UAInAppMessagingRemoteConfig+Internal.h"
#import "UATagGroupsLookupManager+Internal.h"
#import "UATagSelector+Internal.h"
#import "UARetriable+Internal.h"
#import "UARetriablePipeline+Internal.h"
#import "UAAirshipAutomationCoreImport.h"
#import "UAScheduleAudience.h"
#import "UAScheduleAudienceChecks+Internal.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const MaxSchedules = 200;

NSString *const UAInAppMessageManagerEnabledKey = @"UAInAppMessageManagerEnabled";
NSString *const UAInAppMessageManagerPausedKey = @"UAInAppMessageManagerPaused";

@interface UAInAppAutomation () <UAAutomationEngineDelegate, UATagGroupsLookupManagerDelegate, UAInAppRemoteDataClientDelegate, UAInAppMessagingExecutionDelegate>

@property(nonatomic, strong) UAAutomationEngine *automationEngine;
@property(nonatomic, strong) UAPreferenceDataStore *dataStore;
@property(nonatomic, strong) UATagGroupsLookupManager *tagGroupsLookupManager;
@property(nonatomic, strong) UAInAppRemoteDataClient *remoteDataClient;
@property(nonatomic, strong) UARetriablePipeline *prepareSchedulePipeline;
@property(nonatomic, strong) UAInAppMessageManager *inAppMessageManager;

@end

@implementation UAInAppAutomation

+ (instancetype)automationWithEngine:(UAAutomationEngine *)automationEngine
              tagGroupsLookupManager:(UATagGroupsLookupManager *)tagGroupsLookupManager
                    remoteDataClient:(UAInAppRemoteDataClient *)remoteDataClient
                           dataStore:(UAPreferenceDataStore *)dataStore
                inAppMesssageManager:(UAInAppMessageManager *)inAppMessageManager {

    return [[self alloc] initWithAutomationEngine:automationEngine
                           tagGroupsLookupManager:tagGroupsLookupManager
                                 remoteDataClient:remoteDataClient
                                        dataStore:dataStore
                              inAppMessageManager:inAppMessageManager];
}

+ (instancetype)automationWithConfig:(UARuntimeConfig *)config
                    tagGroupHistorian:(UATagGroupHistorian *)tagGroupHistorian
                  remoteDataProvider:(id<UARemoteDataProvider>)remoteDataProvider
                           dataStore:(UAPreferenceDataStore *)dataStore
                             channel:(UAChannel *)channel
                           analytics:(UAAnalytics *)analytics {


    UAAutomationStore *store = [UAAutomationStore automationStoreWithConfig:config
                                                              scheduleLimit:MaxSchedules];
    UAAutomationEngine *automationEngine = [UAAutomationEngine automationEngineWithAutomationStore:store];

    UATagGroupsLookupManager *lookupManager = [UATagGroupsLookupManager lookupManagerWithConfig:config
                                                                                      dataStore:dataStore
                                                                               tagGroupHistorian:tagGroupHistorian];

    UAInAppRemoteDataClient *dataClient = [UAInAppRemoteDataClient clientWithRemoteDataProvider:remoteDataProvider
                                                                                      dataStore:dataStore
                                                                                        channel:channel];

    UAInAppMessageManager *inAppMessageManager = [UAInAppMessageManager managerWithDataStore:dataStore
                                                                                   analytics:analytics];

    return [[UAInAppAutomation alloc] initWithAutomationEngine:automationEngine
                                        tagGroupsLookupManager:lookupManager
                                              remoteDataClient:dataClient
                                                     dataStore:dataStore
                                           inAppMessageManager:inAppMessageManager];
}

- (instancetype)initWithAutomationEngine:(UAAutomationEngine *)automationEngine
                  tagGroupsLookupManager:(UATagGroupsLookupManager *)tagGroupsLookupManager
                        remoteDataClient:(UAInAppRemoteDataClient *)remoteDataClient
                               dataStore:(UAPreferenceDataStore *)dataStore
                     inAppMessageManager:(UAInAppMessageManager *)inAppMessageManager {

    self = [super initWithDataStore:dataStore];

    if (self) {
        self.automationEngine = automationEngine;
        self.tagGroupsLookupManager = tagGroupsLookupManager;
        self.remoteDataClient = remoteDataClient;
        self.dataStore = dataStore;
        self.inAppMessageManager = inAppMessageManager;
        self.prepareSchedulePipeline = [UARetriablePipeline pipeline];

        self.automationEngine.delegate = self;
        self.tagGroupsLookupManager.delegate = self;
        self.remoteDataClient.delegate = self;
        self.inAppMessageManager.executionDelegate = self;

        [self.remoteDataClient subscribe];
    }

    return self;
}

-(void)airshipReady:(UAirship *)airship {
    [self.automationEngine start];
    [self updateEnginePauseState];
}

- (void)getScheduleWithID:(NSString *)identifier completionHandler:(void (^)(UASchedule * _Nullable))completionHandler {
    [self.automationEngine getScheduleWithID:identifier completionHandler:completionHandler];
}

- (void)getSchedulesWithMessageID:(NSString *)messageID completionHandler:(void (^)(NSArray<UASchedule *> *))completionHandler {
    [self.automationEngine getSchedulesWithGroup:messageID completionHandler:completionHandler];
}

- (void)getAllSchedules:(void (^)(NSArray<UASchedule *> *))completionHandler {
    [self.automationEngine getAllSchedules:completionHandler];
}

- (void)schedule:(UASchedule *)schedule completionHandler:(void (^)(BOOL))completionHandler {
    [self.automationEngine schedule:schedule completionHandler:completionHandler];
}

- (void)scheduleMultiple:(NSArray<UASchedule *> *)schedules completionHandler:(void (^)(BOOL))completionHandler {
    [self.automationEngine scheduleMultiple:schedules completionHandler:completionHandler];
}


- (void)cancelSchedulesWithGroup:(NSString *)group
               completionHandler:(nullable void (^)(NSArray<UASchedule *> * _Nonnull))completionHandler {
    [self.automationEngine cancelSchedulesWithGroup:group completionHandler:completionHandler];
}

- (void)cancelScheduleWithID:(NSString *)scheduleID
           completionHandler:(nullable void (^)(UASchedule * _Nullable))completionHandler {
    [self.automationEngine cancelScheduleWithID:scheduleID completionHandler:completionHandler];
}

- (void)cancelSchedulesWithType:(UAScheduleType)scheduleType
              completionHandler:(nullable void (^)(NSArray<UASchedule *> *))completionHandler {
    [self.automationEngine cancelSchedulesWithType:scheduleType completionHandler:completionHandler];
}


- (void)getSchedulesWithGroup:(NSString *)group
            completionHandler:(void (^)(NSArray<UASchedule *> *))completionHandler {
    [self.automationEngine getSchedulesWithGroup:group completionHandler:completionHandler];
}

- (void)editScheduleWithID:(NSString *)scheduleID
                     edits:(UAScheduleEdits *)edits
         completionHandler:(void (^)(UASchedule * _Nullable))completionHandler {

    [self.automationEngine editScheduleWithID:scheduleID edits:edits completionHandler:completionHandler];
}

- (void)prepareSchedule:(UASchedule *)schedule
         triggerContext:(nullable UAScheduleTriggerContext *)triggerContext
      completionHandler:(void (^)(UAAutomationSchedulePrepareResult))completionHandler {

    UA_LDEBUG(@"Trigger Context trigger: %@ event: %@", triggerContext.trigger, triggerContext.event);
    UA_LDEBUG(@"Preparing schedule: %@", schedule.identifier);

    if ([self isScheduleInvalid:schedule]) {
        [self.remoteDataClient notifyOnUpdate:^{
            completionHandler(UAAutomationSchedulePrepareResultInvalidate);
        }];
        return;
    }

    NSString *scheduleID = schedule.identifier;

    // Check audience conditions
    UARetriable *checkAudience = [UARetriable retriableWithRunBlock:^(UARetriableCompletionHandler _Nonnull retriableHandler) {
        UAScheduleAudience *audience = schedule.audience;
        [self checkAudience:audience completionHandler:^(BOOL success, NSError *error) {
            if (error) {
                retriableHandler(UARetriableResultRetry);
            } else if (success) {
                retriableHandler(UARetriableResultSuccess);
            } else {
                UA_LDEBUG(@"Message audience conditions not met, skipping display for schedule: %@, missBehavior: %ld", scheduleID, (long)audience.missBehavior);
                switch(audience.missBehavior) {
                    case UAScheduleAudienceMissBehaviorCancel:
                        completionHandler(UAAutomationSchedulePrepareResultCancel);
                        break;
                    case UAScheduleAudienceMissBehaviorSkip:
                        completionHandler(UAAutomationSchedulePrepareResultSkip);
                        break;
                    case UAScheduleAudienceMissBehaviorPenalize:
                        completionHandler(UAAutomationSchedulePrepareResultPenalize);
                        break;
                }
                retriableHandler(UARetriableResultCancel);
            }
        }];
    }];

    // Prepare
    UA_WEAKIFY(self)
    UARetriable *prepare = [UARetriable retriableWithRunBlock:^(UARetriableCompletionHandler _Nonnull retriableHandler) {
        UA_STRONGIFY(self)

        switch (schedule.type) {
            case UAScheduleTypeActions:
                completionHandler(UAAutomationSchedulePrepareResultContinue);
                break;

            case UAScheduleTypeInAppMessage:
                [self.inAppMessageManager prepareMessage:(UAInAppMessage *) schedule.data
                                              scheduleID:schedule.identifier
                                       completionHandler:completionHandler];
                break;
        }

        retriableHandler(UARetriableResultSuccess);
    }];

    [self.prepareSchedulePipeline addChainedRetriables:@[checkAudience, prepare]];
}

- (UAAutomationScheduleReadyResult)isScheduleReadyToExecute:(UASchedule *)schedule {
    UA_LTRACE(@"Checking if schedule %@ is ready to execute.", schedule.identifier);

    if (self.isPaused) {
        UA_LTRACE(@"InAppAutoamtion currently paused. Schedule: %@ not ready.", schedule.identifier);
        return UAAutomationScheduleReadyResultNotReady;
    }


    switch (schedule.type) {
        case UAScheduleTypeActions:
            if ([self isScheduleInvalid:schedule]) {
                return UAAutomationScheduleReadyResultInvalidate;
            }
            return UAAutomationScheduleReadyResultContinue;

        case UAScheduleTypeInAppMessage:
            if ([self isScheduleInvalid:schedule]) {
                [self.inAppMessageManager scheduleExecutionAborted:schedule.identifier];
                return UAAutomationScheduleReadyResultInvalidate;
            }

            return [self.inAppMessageManager isReadyToDisplay:schedule.identifier];
    }

    return UAAutomationScheduleReadyResultNotReady;
}

- (void)executeSchedule:(nonnull UASchedule *)schedule completionHandler:(void (^)(void))completionHandler {
    UA_LTRACE(@"Executing schedule: %@", schedule.identifier);

    switch (schedule.type) {
        case UAScheduleTypeActions: {
            // Run the actions
            [UAActionRunner runActionsWithActionValues:schedule.data
                                             situation:UASituationAutomation
                                              metadata:nil
                                     completionHandler:^(UAActionResult *result) {
                completionHandler();
            }];
            break;
        }

        case UAScheduleTypeInAppMessage: {
             [self.inAppMessageManager displayMessageWithScheduleID:schedule.identifier completionHandler:completionHandler];
            break;
        }
    }



}

/**
 * Checks to see if a schedule from remote-data is still valid.
 *
 * @param schedule The in-app schedule.
 * @return `YES` if the schedule is valid, otherwise `NO`.
 */
-(BOOL)isScheduleInvalid:(UASchedule *)schedule {
    return [self.remoteDataClient isRemoteSchedule:schedule] &&
    ![self.remoteDataClient isScheduleUpToDate:schedule];
}


- (void)onScheduleExpired:(UASchedule *)schedule {
    if (schedule.type == UAScheduleTypeInAppMessage) {
        [self.inAppMessageManager messageExpired:(UAInAppMessage *)schedule.data
                                      scheduleID:schedule.identifier
                                  expirationDate:schedule.end];
    }
}

- (void)onScheduleCancelled:(UASchedule *)schedule {
    if (schedule.type == UAScheduleTypeInAppMessage) {
        [self.inAppMessageManager messageCancelled:(UAInAppMessage *)schedule.data
                                        scheduleID:schedule.identifier];
    }
}

- (void)onScheduleLimitReached:(UASchedule *)schedule {
    if (schedule.type == UAScheduleTypeInAppMessage) {
        [self.inAppMessageManager messageLimitReached:(UAInAppMessage *)schedule.data
                                           scheduleID:schedule.identifier];
    }
}

- (void)onNewSchedule:(nonnull UASchedule *)schedule {
    if (schedule.type == UAScheduleTypeInAppMessage) {
        [self.inAppMessageManager messageScheduled:(UAInAppMessage *)schedule.data
                                        scheduleID:schedule.identifier];
    }
}

- (void)onComponentEnableChange {
    [self updateEnginePauseState];
}

- (void)applyRemoteConfig:(nullable id)config {
    UAInAppMessagingRemoteConfig *inAppConfig = nil;
    if (config) {
        inAppConfig = [UAInAppMessagingRemoteConfig configWithJSON:config];
    }
    inAppConfig = inAppConfig ?: [UAInAppMessagingRemoteConfig defaultConfig];

    self.tagGroupsLookupManager.enabled = inAppConfig.tagGroupsConfig.enabled;
    self.tagGroupsLookupManager.cacheMaxAgeTime = inAppConfig.tagGroupsConfig.cacheMaxAgeTime;
    self.tagGroupsLookupManager.cacheStaleReadTime = inAppConfig.tagGroupsConfig.cacheStaleReadTime;
    self.tagGroupsLookupManager.preferLocalTagDataTime = inAppConfig.tagGroupsConfig.cachePreferLocalUntil;
}

- (void)setPaused:(BOOL)paused {
    // If we're unpausing, alert the automation engine
    if (self.isPaused == YES && self.isPaused != paused) {
        [self.automationEngine scheduleConditionsChanged];
    }

    [self.dataStore setBool:paused forKey:UAInAppMessageManagerPausedKey];
}

- (BOOL)isPaused{
    return [self.dataStore boolForKey:UAInAppMessageManagerPausedKey defaultValue:NO];
}

- (void)setEnabled:(BOOL)enabled {
    [self.dataStore setBool:enabled forKey:UAInAppMessageManagerEnabledKey];
    [self updateEnginePauseState];
}

- (BOOL)isEnabled {
    return [self.dataStore boolForKey:UAInAppMessageManagerEnabledKey defaultValue:YES];
}

- (void)updateEnginePauseState {
    if (self.componentEnabled && self.isEnabled) {
        [self.automationEngine resume];
    } else {
        [self.automationEngine pause];
    }
}

- (void)dealloc {
    [self.automationEngine stop];
    self.automationEngine.delegate = nil;
}

- (void)gatherTagGroupsWithCompletionHandler:(void(^)(UATagGroups *tagGroups))completionHandler {
    __block UATagGroups *tagGroups = [UATagGroups tagGroupsWithTags:@{}];

    [self.automationEngine getSchedules:^(NSArray<UASchedule *> *schedules) {
        for (UASchedule *schedule in schedules) {
            if ([schedule.audience.tagSelector containsTagGroups]) {
                tagGroups = [tagGroups merge:schedule.audience.tagSelector.tagGroups];
            }
        }

        completionHandler(tagGroups);
    }];
}

- (void)checkAudience:(UAScheduleAudience *)audience completionHandler:(void (^)(BOOL, NSError * _Nullable))completionHandler {
    void (^performAudienceCheck)(UATagGroups *) = ^(UATagGroups *tagGroups) {
        if ([UAScheduleAudienceChecks checkDisplayAudienceConditions:audience tagGroups:tagGroups]) {
            completionHandler(YES, nil);
        } else {
            completionHandler(NO, nil);
        }
    };

    UATagGroups *requestedTagGroups = audience.tagSelector.tagGroups;

    if (requestedTagGroups.tags.count) {
        [self.tagGroupsLookupManager getTagGroups:requestedTagGroups completionHandler:^(UATagGroups * _Nullable tagGroups, NSError * _Nonnull error) {
            if (error) {
                completionHandler(NO, error);
            } else {
                performAudienceCheck(tagGroups);
            }
        }];
    } else {
        performAudienceCheck(nil);
    }
}

- (void)executionReadinessChanged {
    [self.automationEngine scheduleConditionsChanged];
}

- (void)cancelScheduleWithID:(nonnull NSString *)scheduleID {
    [self.automationEngine cancelScheduleWithID:scheduleID completionHandler:nil];
}


@end

NS_ASSUME_NONNULL_END



