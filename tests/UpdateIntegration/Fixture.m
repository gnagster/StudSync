#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>

@interface Fixture : NSObject <NSApplicationDelegate, SPUUserDriver>
@property SPUUpdater *updater;
@end
@implementation Fixture
- (void)finish:(NSString *)result {
    NSString *path = [NSBundle.mainBundle objectForInfoDictionaryKey:@"FixtureResult"];
    [result writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [NSApp terminate:nil];
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    NSString *pidPath = [NSBundle.mainBundle objectForInfoDictionaryKey:@"FixturePID"];
    [[NSString stringWithFormat:@"%d", getpid()] writeToFile:pidPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    if ([[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"2"]) { [self finish:@"installed"]; return; }
    self.updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:self delegate:nil];
    NSError *error = nil;
    if (![self.updater startUpdater:&error]) { [self finish:@"start-error"]; return; }
    [self.updater checkForUpdates];
}
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply {
    reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO]);
}
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply { reply(SPUUserUpdateChoiceInstall); }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))ack { ack(); [self finish:@"no-update"]; }
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))ack {
    fprintf(stderr,"Sparkle fixture error domain=%s code=%ld\n",error.domain.UTF8String,(long)error.code);
    ack(); [self finish:@"error"];
}
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation {}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate {}
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply { reply(SPUUserUpdateChoiceInstall); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))ack { ack(); [self finish:@"installed"]; }
- (void)dismissUpdateInstallation {}
@end
int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyProhibited];
        Fixture *delegate = [Fixture new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
