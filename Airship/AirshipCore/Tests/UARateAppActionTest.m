/* Copyright Airship and Contributors */

#import "UABaseTest.h"
#import <StoreKit/StoreKit.h>
#import "UARateAppAction.h"
#import "AirshipTests-Swift.h"

@import AirshipCore;

@interface UARateAppActionTest : UABaseTest

@property (nonatomic, strong) id mockApplication;
@property (nonatomic, strong) id mockConfig;
@property (nonatomic, strong) UATestAirshipInstance *airship;
@property (nonatomic, retain) UARateAppAction *action;
@end

@implementation UARateAppActionTest

- (void)setUp {
    [super setUp];

    self.mockConfig = [self mockForClass:[UARuntimeConfig class]];
    [[[self.mockConfig stub] andReturn:[NSUUID UUID].UUIDString] appKey];

    
    self.mockApplication = [self mockForClass:[UIApplication class]];
    [[[self.mockApplication stub] andReturn:self.mockApplication] sharedApplication];

    self.action = [[UARateAppAction alloc] init];
    
    self.airship = [[UATestAirshipInstance alloc] init];
    self.airship.config = self.mockConfig;
    [self.airship makeShared];
}

-(void)testDirectAppStoreLink {
    [[[self.mockConfig stub] andReturn:@"1195168544"] itunesID];

    [[self.mockApplication expect] openURL:[NSURL URLWithString:@"itms-apps://itunes.apple.com/app/id1195168544?action=write-review"] options:@{} completionHandler:nil];
    [[[self.mockApplication stub] andReturnValue:@YES] canOpenURL:OCMOCK_ANY];

    [self.action performWithArguments:[UAActionArguments argumentsWithValue:@{ UARateAppShowLinkPromptKey: @NO} withSituation:UASituationManualInvocation] completionHandler:^(UAActionResult * result) {
    }];

    [self.mockApplication verify];
}

@end
