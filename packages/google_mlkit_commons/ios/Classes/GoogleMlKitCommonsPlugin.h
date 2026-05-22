#import <Flutter/Flutter.h>

// MLKitVision is only available when building with CocoaPods or when a
// vision-based ML Kit product is linked.  NLP-only consumers
// (language_id, translation) do not need it.
#if __has_include(<MLKitVision/MLKitVision.h>)
#import <MLKitVision/MLKitVision.h>
#endif

#if __has_include("GenericModelManager.h")
#import "GenericModelManager.h"
#endif

@interface GoogleMlKitCommonsPlugin : NSObject<FlutterPlugin>
@end

#if __has_include(<MLKitVision/MLKitVision.h>)
@interface MLKVisionImage(FlutterPlugin)
+ (MLKVisionImage *)visionImageFromData:(NSDictionary *)imageData;
@end
#endif

static FlutterError *getFlutterError(NSError *error) {
    return [FlutterError errorWithCode:[NSString stringWithFormat:@"Error %d", (int)error.code]
                               message:error.domain
                               details:error.localizedDescription];
}
