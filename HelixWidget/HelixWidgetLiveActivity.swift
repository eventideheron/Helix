//
//  HelixWidgetLiveActivity.swift
//  HelixWidget
//
//  Created by Josh Lang on 3/12/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct HelixWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct HelixWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HelixWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension HelixWidgetAttributes {
    fileprivate static var preview: HelixWidgetAttributes {
        HelixWidgetAttributes(name: "World")
    }
}

extension HelixWidgetAttributes.ContentState {
    fileprivate static var smiley: HelixWidgetAttributes.ContentState {
        HelixWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: HelixWidgetAttributes.ContentState {
         HelixWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: HelixWidgetAttributes.preview) {
   HelixWidgetLiveActivity()
} contentStates: {
    HelixWidgetAttributes.ContentState.smiley
    HelixWidgetAttributes.ContentState.starEyes
}
