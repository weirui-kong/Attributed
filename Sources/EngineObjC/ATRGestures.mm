// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

#import "ATRGestures.h"

#if !__has_feature(objc_arc)
#error "AttributedEngineObjC must be compiled with ARC."
#endif

@interface ATRGestureBinding ()
#if TARGET_OS_OSX
    <NSGestureRecognizerDelegate>
#endif
@end

@implementation ATRGestureBinding {
    NSInteger _triggerState;
    ATRGestureHandler _handler;
#if TARGET_OS_OSX
    // AppKit has no requireGestureRecognizerToFail:; the binding answers
    // the delegate question instead.
    NSHashTable<ATRPlatformGestureRecognizer *> *_requiredFailures;
#endif
}

- (instancetype)initWithGesture:(ATRGesture)gesture
                    interaction:(uint32_t)interaction
                     recognizer:(ATRPlatformGestureRecognizer *)recognizer
                   triggerState:(NSInteger)triggerState
                        handler:(ATRGestureHandler)handler {
    self = [super init];

    if (self) {
        _gesture = gesture;
        _interaction = interaction;
        _recognizer = recognizer;
        _triggerState = triggerState;
        _handler = [handler copy];
#if TARGET_OS_OSX
        recognizer.target = self;
        recognizer.action = @selector(recognizerDidChange:);
        _requiredFailures = [NSHashTable weakObjectsHashTable];
        recognizer.delegate = self;
#else
        [recognizer addTarget:self action:@selector(recognizerDidChange:)];
#endif
    }

    return self;
}

- (void)recognizerDidChange:(ATRPlatformGestureRecognizer *)recognizer {
    if (recognizer.state == _triggerState) {
        [self triggerAtLocation:[recognizer locationInView:recognizer.view]];
    }
}

- (void)triggerAtLocation:(CGPoint)location {
    _handler(_interaction, location);
}

- (void)requireFailureOfBinding:(ATRGestureBinding *)other {
#if TARGET_OS_OSX
    [_requiredFailures addObject:other.recognizer];
#else
    [_recognizer requireGestureRecognizerToFail:other.recognizer];
#endif
}

#if TARGET_OS_OSX
- (BOOL)gestureRecognizer:(NSGestureRecognizer *)gestureRecognizer
    shouldRequireFailureOfGestureRecognizer:(NSGestureRecognizer *)otherGestureRecognizer {
    return [_requiredFailures containsObject:otherGestureRecognizer];
}
#endif

@end

@implementation ATRTapGestureFactory

- (ATRGestureBinding *)bindingForGesture:(ATRGesture)gesture
                             interaction:(uint32_t)interaction
                                 handler:(ATRGestureHandler)handler {
#if TARGET_OS_OSX
    NSClickGestureRecognizer *recognizer = [[NSClickGestureRecognizer alloc] init];
    recognizer.numberOfClicksRequired = MAX(gesture.tapCount, 1u);
    NSInteger triggerState = NSGestureRecognizerStateEnded;
#else
    UITapGestureRecognizer *recognizer = [[UITapGestureRecognizer alloc] init];
    recognizer.numberOfTapsRequired = MAX(gesture.tapCount, 1u);
    NSInteger triggerState = UIGestureRecognizerStateEnded;
#endif
    return [[ATRGestureBinding alloc] initWithGesture:gesture
                                          interaction:interaction
                                           recognizer:recognizer
                                         triggerState:triggerState
                                              handler:handler];
}

@end

@implementation ATRLongPressGestureFactory

- (ATRGestureBinding *)bindingForGesture:(ATRGesture)gesture
                             interaction:(uint32_t)interaction
                                 handler:(ATRGestureHandler)handler {
#if TARGET_OS_OSX
    NSPressGestureRecognizer *recognizer = [[NSPressGestureRecognizer alloc] init];
    NSInteger triggerState = NSGestureRecognizerStateBegan;
#else
    UILongPressGestureRecognizer *recognizer = [[UILongPressGestureRecognizer alloc] init];
    NSInteger triggerState = UIGestureRecognizerStateBegan;
#endif
    recognizer.minimumPressDuration = gesture.minimumPressDuration;
    return [[ATRGestureBinding alloc] initWithGesture:gesture
                                          interaction:interaction
                                           recognizer:recognizer
                                         triggerState:triggerState
                                              handler:handler];
}

@end

@implementation ATRGestureRecognizerRegistry {
    NSMutableDictionary<NSNumber *, id<ATRGestureRecognizerFactory>> *_factories;
}

+ (instancetype)defaultRegistry {
    ATRGestureRecognizerRegistry *registry = [[self alloc] init];
    [registry registerFactory:[[ATRTapGestureFactory alloc] init] forKind:ATRGestureKindTap];
    [registry registerFactory:[[ATRLongPressGestureFactory alloc] init] forKind:ATRGestureKindLongPress];
    return registry;
}

- (instancetype)init {
    self = [super init];

    if (self) {
        _factories = [NSMutableDictionary dictionary];
    }

    return self;
}

- (void)registerFactory:(id<ATRGestureRecognizerFactory>)factory forKind:(ATRGestureKind)kind {
    _factories[@(kind)] = factory;
}

- (id<ATRGestureRecognizerFactory>)factoryForKind:(ATRGestureKind)kind {
    return _factories[@(kind)];
}

@end

@implementation ATRDefaultGesturePolicy

- (void)configureBindings:(NSArray<ATRGestureBinding *> *)bindings {
    for (ATRGestureBinding *binding in bindings) {
        if (binding.gesture.kind != ATRGestureKindTap) {
            continue;
        }

        for (ATRGestureBinding *other in bindings) {
            if (other.gesture.kind == ATRGestureKindTap && other.gesture.tapCount > binding.gesture.tapCount) {
                [binding requireFailureOfBinding:other];
            }
        }
    }
}

@end
