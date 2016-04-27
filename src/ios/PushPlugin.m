/*
 Copyright 2009-2011 Urban Airship Inc. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binaryform must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided withthe distribution.

 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "PushPlugin.h"

@implementation PushPlugin


/**
 * Unregister for notifications
 */
- (void)unregister:(CDVInvokedUrlCommand*)command;
{
	self.callbackId = command.callbackId;

    [[UIApplication sharedApplication] unregisterForRemoteNotifications];
    [self successWithMessage:@"Unregistered from notifications."];
}

/**
 * Register for notifications
 */
- (void)register:(CDVInvokedUrlCommand*)command;
{
	self.callbackId = command.callbackId;

#if TARGET_IPHONE_SIMULATOR
    return;
#endif

    self.isInForeground = NO;

    UIUserNotificationType userNotificationTypes = UIUserNotificationTypeNone;       // iOS >= 8
    UIRemoteNotificationType remoteNotificationTypes = UIRemoteNotificationTypeNone; // iOS < 8

    // process options
    NSMutableDictionary* options = [command.arguments objectAtIndex:0];
    if ([options respondsToSelector:@selector(objectForKey:)]) {
        id badgeArg = [options objectForKey:@"badge"];
        id soundArg = [options objectForKey:@"sound"];
        id alertArg = [options objectForKey:@"alert"];

        // badge
        if ([badgeArg isEqualToString:@"true"] || [badgeArg boolValue]) {
            remoteNotificationTypes |= UIRemoteNotificationTypeBadge;
            userNotificationTypes |= UIUserNotificationTypeBadge;
        }

        // sound
        if ([soundArg isEqualToString:@"true"] || [soundArg boolValue]) {
            remoteNotificationTypes |= UIRemoteNotificationTypeSound;
            userNotificationTypes |= UIUserNotificationTypeSound;
        }

        // alert
        if ([alertArg isEqualToString:@"true"] || [alertArg boolValue]) {
            remoteNotificationTypes |= UIRemoteNotificationTypeAlert;
            userNotificationTypes |= UIUserNotificationTypeAlert;
        }

        // additional notification types
        remoteNotificationTypes |= UIRemoteNotificationTypeNewsstandContentAvailability;
        userNotificationTypes |= UIUserNotificationActivationModeBackground;

        self.callback = [options objectForKey:@"ecb"];
    }

    if (remoteNotificationTypes == UIRemoteNotificationTypeNone)
        ALog(@"PushPlugin.register: Push notification type is set to none");

    // iOS >= 8
    if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:userNotificationTypes categories:nil];
        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    }
    // iOS < 8
    else {
        [[UIApplication sharedApplication] registerForRemoteNotificationTypes:remoteNotificationTypes];
    }

    // process notification (iOS < 8, >= 8 is processed in didRegisterForRemoteNotificationsWithDeviceToken)
	if (self.notificationMessage)
		[self notificationReceived];
}

/**
 * registerForRemoteNotifications callback
 */
- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    NSString *token = [[[[deviceToken description] stringByReplacingOccurrencesOfString:@"<"withString:@""]
                        stringByReplacingOccurrencesOfString:@">" withString:@""]
                       stringByReplacingOccurrencesOfString: @" " withString: @""];
    [results setValue:token forKey:@"deviceToken"];

    // Get Bundle Info for Remote Registration (handy if you have more than one app)
    [results setValue:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"] forKey:@"appName"];
    [results setValue:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] forKey:@"appVersion"];

    // Check what Notifications the user has turned on.  We registered for all three, but they may have manually disabled some or all of them.
    NSUInteger enabledTypes;
    if (!SYSTEM_VERSION_LESS_THAN(@"8.0")) {
        enabledTypes = [[[UIApplication sharedApplication] currentUserNotificationSettings] types];
    } else {
        enabledTypes = [[UIApplication sharedApplication] enabledRemoteNotificationTypes];
    }

    // Set the defaults to disabled unless we find otherwise...
    NSString *pushBadge = enabledTypes & UIRemoteNotificationTypeBadge ? @"enabled" : @"disabled";
    NSString *pushAlert = enabledTypes & UIRemoteNotificationTypeAlert ? @"enabled" : @"disabled";
    NSString *pushSound = enabledTypes & UIRemoteNotificationTypeSound ? @"enabled" : @"disabled";

    [results setValue:pushBadge forKey:@"pushBadge"];
    [results setValue:pushAlert forKey:@"pushAlert"];
    [results setValue:pushSound forKey:@"pushSound"];

    // Get the users Device Model, Display Name, Token & Version Number
    UIDevice *dev = [UIDevice currentDevice];
    [results setValue:dev.name forKey:@"deviceName"];
    [results setValue:dev.model forKey:@"deviceModel"];
    [results setValue:dev.systemVersion forKey:@"deviceSystemVersion"];


    // build success data
    NSError *error;
    NSMutableDictionary *successDictionary = [NSMutableDictionary dictionary];
    [successDictionary setObject:token forKey:@"token"];
//    [successDictionary setObject:results forKey:@"deviceData"];
    [successDictionary setObject:self.notificationMessage ?: @"" forKey:@"notification"];
    NSData *successData = [NSJSONSerialization dataWithJSONObject:successDictionary options:NSJSONWritingPrettyPrinted error:&error];

    // report success
    [self successWithMessage:[[NSString alloc] initWithData:successData encoding:NSUTF8StringEncoding]];

    // process notification
    if (self.notificationMessage)
        [self notificationReceived];
}

/**
 * Device registration failed
 */
- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
	[self failWithMessage:@"Device registration failed" withError:error];
}

/**
 * Process incomming notification and nofify javascript
 */
- (void)notificationReceived {
    @synchronized(self) {
        if (!self.notificationMessage || !self.callback) {
            return;
        }

        // flatten notification structure
        NSMutableDictionary *notification = [self flattenDictionary:self.notificationMessage];

        // reset notification
        self.notificationMessage = nil;

        // set foreground status
        [notification setObject:[NSNumber numberWithInteger:self.isInForeground ? 1 : 0] forKey:@"foreground"];

        // compile JSON
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:notification options:NSJSONWritingPrettyPrinted error:&error];
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

        ALog(@"Notification: %@", jsonString);

        // notify javascript about notification
        NSString * jsCallback = [NSString stringWithFormat:@"%@(%@);", self.callback, jsonString];
        [self.webView stringByEvaluatingJavaScriptFromString:jsCallback];
    }
}

/**
 * Flatten NSDictionary structure
 */
- (NSMutableDictionary *)flattenDictionary:(NSDictionary *)dictionary
{
    NSMutableDictionary *flatDictionary = [NSMutableDictionary dictionary];

    [dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if ([value isKindOfClass:[NSDictionary class]])
            [flatDictionary addEntriesFromDictionary:[self flattenDictionary:value]];
        else
            [flatDictionary setObject:value forKey:key];
    }];

    return flatDictionary;
}

/**
 * Check if notification type is enabled
 */
- (BOOL)checkNotificationType:(UIUserNotificationType)type
{
  UIUserNotificationSettings *currentSettings = [[UIApplication sharedApplication] currentUserNotificationSettings];
  
  return (currentSettings.types & type);
}

/**
 * Set badge number
 */
- (void)setApplicationIconBadgeNumber:(CDVInvokedUrlCommand *)command
{
    self.callbackId = command.callbackId;

    NSMutableDictionary* options = [command.arguments objectAtIndex:0];
    int badge = [[options objectForKey:@"badge"] intValue] ?: 0;
    UIApplication *application = [UIApplication sharedApplication];

    // set app badge (iOS < 8)
    if(SYSTEM_VERSION_LESS_THAN(@"8.0")) {
       application.applicationIconBadgeNumber = badge;
    }
    // set app badge (iOS >= 8)
    else {
        if ([self checkNotificationType:UIUserNotificationTypeBadge])
            application.applicationIconBadgeNumber = badge;
        else
            ALog(@"setApplicationIconBadgeNumber access denied for UIUserNotificationTypeBadge");
    }

    [self successWithMessage:[NSString stringWithFormat:@"App badge count set to %d", badge]];
}

/**
 * Report success for current command
 */
-(void)successWithMessage:(NSString *)message
{
    if (self.callbackId != nil) {
        CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:message];
        [self.commandDelegate sendPluginResult:commandResult callbackId:self.callbackId];
    }
}

/**
 * Report fail for current command
 */
-(void)failWithMessage:(NSString *)message withError:(NSError *)error
{
    NSString        *errorMessage = (error) ? [NSString stringWithFormat:@"%@ - %@", message, [error localizedDescription]] : message;
    CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];

    [self.commandDelegate sendPluginResult:commandResult callbackId:self.callbackId];
}

@end
