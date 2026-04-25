//
//  HelixWidgetBundle.swift
//  HelixWidget
//
//  Created by Josh Lang on 3/12/26.
//

import WidgetKit
import SwiftUI

@main
struct HelixWidgetBundle: WidgetBundle {
    var body: some Widget {
        HelixWidget()
        HelixWidgetControl()
        HelixWidgetLiveActivity()
    }
}
