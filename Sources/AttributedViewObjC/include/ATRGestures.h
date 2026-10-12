// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRTypes.h"

// Gesture recognition is split so that adding a gesture kind never touches
// hit views or the text view:
// - ATRGestureBinding adapts one platform recognizer to a trigger callback.
// - Factories make bindings for one gesture kind; a registry maps kinds to
//   factories.
// - A policy wires dependencies between the bindings that share a hit view.

typedef void (^ATRGestureHandler)(uint32_t interaction, CGPoint location);

// Owns a platform recognizer, is its target, and calls the handler with the
// interaction ID and the location in the recognizer's view when the
// recognizer reaches the gesture's trigger state.
@interface ATRGestureBinding : NSObject

@property (nonatomic, readonly) ATRGesture gesture;
@property (nonatomic, readonly) uint32_t interaction;
@property (nonatomic, readonly, nonnull) ATRPlatformGestureRecognizer *recognizer;

- (nonnull instancetype)initWithGesture:(ATRGesture)gesture
                            interaction:(uint32_t)interaction
                             recognizer:(nonnull ATRPlatformGestureRecognizer *)recognizer
                           triggerState:(NSInteger)triggerState
                                handler:(nonnull ATRGestureHandler)handler NS_DESIGNATED_INITIALIZER;

- (nonnull instancetype)init NS_UNAVAILABLE;
+ (nonnull instancetype)new NS_UNAVAILABLE;

// Recognition waits until `other` fails.
- (void)requireFailureOfBinding:(nonnull ATRGestureBinding *)other;

// Calls the handler as if the gesture had been recognized at `location`.
- (void)triggerAtLocation:(CGPoint)location;

@end

@protocol ATRGestureRecognizerFactory <NSObject>

- (nonnull ATRGestureBinding *)bindingForGesture:(ATRGesture)gesture
                                     interaction:(uint32_t)interaction
                                         handler:(nonnull ATRGestureHandler)handler;

@end

// Taps with the gesture's tap count; triggers when recognized.
@interface ATRTapGestureFactory : NSObject <ATRGestureRecognizerFactory>
@end

// Long presses with the gesture's minimum duration; triggers when the press
// begins, without waiting for release.
@interface ATRLongPressGestureFactory : NSObject <ATRGestureRecognizerFactory>
@end

@interface ATRGestureRecognizerRegistry : NSObject

// A new registry with the tap and long-press factories.
+ (nonnull instancetype)defaultRegistry;

- (void)registerFactory:(nonnull id<ATRGestureRecognizerFactory>)factory forKind:(ATRGestureKind)kind;
- (nullable id<ATRGestureRecognizerFactory>)factoryForKind:(ATRGestureKind)kind;

@end

@protocol ATRGesturePolicy <NSObject>

// Called once with all bindings of one hit view, before they are installed.
- (void)configureBindings:(nonnull NSArray<ATRGestureBinding *> *)bindings;

@end

// A tap waits for every tap with a higher count on the same hit view to
// fail, so a single tap does not fire on the first touch of a double tap.
@interface ATRDefaultGesturePolicy : NSObject <ATRGesturePolicy>
@end
