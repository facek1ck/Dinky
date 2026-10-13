#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Only the mimi augmented swipe is left; RESULTS.md records the paths the spike tried.
// Swipes from fromIndex to toIndex (1-based) on the display with displayUUID and returns whether
// posting succeeded. Refuses an unknown display. Does not wait for the switch, but warps the cursor to
// that display for the swipe when it is elsewhere and waits about 60 ms to put it back.
// With preserveMouseMovement, restore only if the user has not moved during the swipe.
// Swift mouse-follow-focus waits until this restoration and the Space flight have finished.
bool dinky_switch_to_space_index(int fromIndex, int toIndex, CFStringRef displayUUID, bool preserveMouseMovement);

// Warp in global CG coordinates and immediately resume physical mouse movement.
bool dinky_warp_mouse(CGPoint point);
