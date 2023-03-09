//
//  VideoLayoutStoreImp.swift
//  Flat
//
//  Created by xuyunshi on 2023/3/7.
//  Copyright © 2023 agora.io. All rights reserved.
//

import Foundation
import RxRelay
import RxSwift
import Whiteboard

private let storeName = "userWindows"
private let gridKey = "grid"
class VideoLayoutStoreImp: NSObject, VideoLayoutStore, SyncedStoreUpdateCallBackDelegate {
    fileprivate var syncStore: SyncedStore!


    let resultPublisher: BehaviorSubject<VideoLayoutState> = .init(value: .init(gridUsers: [], freeDraggingUsers: []))

    func setup(whiteboardDisplayer displayer: WhiteDisplayer) {
        syncStore = displayer.obtainSyncedStore()
        logger.info("setup video layout store")
        syncStore.connectStorage(storeName, defaultValue: [:]) { [weak self] _, error in
            guard let self else { return }
            if let error {
                logger.info("connect store \(storeName) fail, \(error.localizedDescription)")
                self.resultPublisher.onError(error)
            } else {
                logger.info("connect store \(storeName) success")
                self.getStorageValue()
            }
        }
    }

    func layoutState() -> Observable<VideoLayoutState> {
        resultPublisher.asObservable()
    }

    func updateExpandUsers(_ usersUUID: [String]) {
        syncStore.setStorageState(storeName, partialState: [gridKey: usersUUID])
    }
    
    func removeFreeDraggingUsers(_ users: [String]) {
        let pairs = users.map {
            ($0, NSNull())
        }
        let value = [String: Any].init(uniqueKeysWithValues: pairs)
        syncStore.setStorageState(storeName, partialState: value)
    }
    
    func updateFreeDraggingUsers(_ users: [DraggingUser]) {
        let pairs = users.map { user -> (String, Any) in
            return (user.uuid, user.valueDic())
        }
        let value = [String: Any].init(uniqueKeysWithValues: pairs)
        syncStore.setStorageState(storeName, partialState: value)
    }

    func syncedStoreDidUpdateStoreName(_ name: String, partialValue: [AnyHashable: Any]) {
        if name == storeName {
            getStorageValue()
        }
    }

    func getStorageValue() {
        syncStore.getStorageState(storeName) { [weak self] result in
            guard let self, let result else { return }
            let gridUsers = result[gridKey] as? [String]
            let freeUsers = result
                .compactMap { key, value -> DraggingUser? in
                    if ((key as? String) ?? "") == gridKey { return nil }
                    guard
                        let userUUID = key as? String,
                        let valueDictionary = value as? NSDictionary
                    else { return nil }
                    return .init(uuid: userUUID, dictionary: valueDictionary)
                }
            let state = VideoLayoutState(gridUsers: gridUsers ?? [], freeDraggingUsers: freeUsers)
            self.resultPublisher.onNext(state)
        }
    }
}
