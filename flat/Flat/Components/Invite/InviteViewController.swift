//
//  InviteViewController.swift
//  Flat
//
//  Created by xuyunshi on 2021/10/29.
//  Copyright © 2021 agora.io. All rights reserved.
//


import UIKit

class InviteViewController: PopOverDismissDetectableViewController {
    var roomInfo: RoomInfo
    let roomUUID: String
    let userName: String
    
    init(roomInfo: RoomInfo,
         roomUUID: String,
         userName: String) {
        self.roomInfo = roomInfo
        self.roomUUID = roomUUID
        self.userName = userName
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        invitorNameLabel.text = userName + " " + NSLocalizedString("inviteDescribe", comment: "")
        titleLabel.text = roomInfo.title
        numberLabel.text = roomInfo.inviteCode
        timeLabel.text = formatter.string(from: roomInfo.beginTime)
        preferredContentSize = .init(width: 360, height: 255)
    }
    
    @IBAction func onClickCopy(_ sender: Any) {
        let link = Env().baseURL + "/join/\(roomUUID)"
        let text = """
\(invitorNameLabel.text!)\n
\(NSLocalizedString("Room Subject", comment: "")): \(titleLabel.text!)\n
\(NSLocalizedString("Start Time", comment: "")): \(timeLabel.text!)\n
\(NSLocalizedString("Room Number", comment: "")): \(numberLabel.text!)\n
\(NSLocalizedString("Join Link", comment: "")): \(link)
"""
        UIPasteboard.general.string = text
        dismiss(animated: true) { [weak self] in
            self?.dismissHandler?()
        }
    }
    
    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var numberLabel: UILabel!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var invitorNameLabel: UILabel!
}
