#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

static NSString *const kServer = @"https://announcement-olympic-doug-lecture.trycloudflare.com";

@interface AlphaBridge : NSObject <WKScriptMessageHandler> @end

@implementation AlphaBridge
- (void)userContentController:(WKUserContentController*)ucc
      didReceiveScriptMessage:(WKScriptMessage*)msg {
    NSLog(@"[ALPHA] bridge msg: %@", msg.body);
}
@end

static AlphaBridge *g_bridge;

%hook WKWebView
- (instancetype)initWithFrame:(CGRect)f configuration:(WKWebViewConfiguration*)c {
    if (!g_bridge) g_bridge = [AlphaBridge new];
    [c.userContentController addScriptMessageHandler:g_bridge name:@"alpha"];
    return %orig;
}
%end

%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication*)app {
    %orig;
    NSLog(@"[ALPHA] dylib loaded");
}
%end
