//
//  XIBLocalizeable.swift
//  flat
//
//  Created by xuyunshi on 2021/10/15.
//  Copyright © 2021 agora.io. All rights reserved.
//


import Foundation
import UIKit

protocol XIBLocalizable {
    var xibLocKey: String? { get set }
}

extension UILabel: XIBLocalizable {
    @IBInspectable var xibLocKey: String? {
        get { nil }
        set { text = NSLocalizedString(newValue ?? "", comment: "") }
    }
}

extension UIButton: XIBLocalizable {
    @IBInspectable var xibLocKey: String? {
        get { nil }
        set { setTitle(NSLocalizedString(newValue ?? "", comment: ""), for: .normal) }
    }
}
