//
//  ClassRoomRtm.swift
//  Flat
//
//  Created by xuyunshi on 2021/11/15.
//  Copyright © 2021 agora.io. All rights reserved.
//

import AgoraRtmKit
import Foundation
import RxRelay
import RxSwift

/// Rtm state control
class Rtm: NSObject {
    enum RtmError {
        case remoteLogin
        case reconnectingTimeout
    }

    enum State {
        case idle
        case connecting
        case reconnecting
        case connected
    }

    let p2pMessage: PublishRelay<(data: Data, sender: String)> = .init()
    let error: PublishRelay<RtmError> = .init()
    let state: BehaviorRelay<State> = .init(value: .idle)
    let reconnectTimeoutInterval: DispatchTimeInterval = .seconds(5)

    init(rtmToken: String,
         rtmUserUUID: String,
         agoraAppId: String)
    {
        super.init()
        agoraKit = AgoraRtmKit(appId: agoraAppId, delegate: self)!
        agoraGenerator.agoraToken = rtmToken
        agoraGenerator.agoraUserId = rtmUserUUID
        logger.trace("\(self)")
    }

    deinit { logger.trace("\(self) deinit") }

    func sendP2PMessageFromArray(_ array: [(data: Data, uuid: String)]) -> Single<Void> {
        array.reduce(Single<Void>.just(())) { [weak self] partial, part -> Single<Void> in
            guard let self else { return .error("self not exist") }
            return partial.flatMap { _ -> Single<Void> in
                return self.sendP2PMessage(data: part.data, toUUID: part.uuid)
            }
        }
    }
    
    func sendP2PMessage(data: Data, toUUID UUID: String) -> Single<Void> {
        logger.info("send p2p raw message data, to \(UUID)")
        switch state.value {
        case .connecting, .idle, .reconnecting: return .just(())
        case .connected:
            return .create { [weak self] observer in
                guard let self else {
                    observer(.failure("self not exist"))
                    return Disposables.create()
                }
                let msg = AgoraRtmRawMessage(rawData: data, description: "")
                self.agoraKit.send(msg, toPeer: UUID) { error in
                    if error == .ok {
                        observer(.success(()))
                    } else {
                        let errMsg = "send p2p msg error \(error)"
                        logger.error("\(errMsg)")
                        if error == .peerUnreachable {
                            observer(.failure(localizeStrings("UserNotInRoom")))
                        } else {
                            observer(.failure(errMsg))
                        }
                    }
                }
                return Disposables.create()
            }
        }
    }

    var loginCallbacks: [(AgoraRtmLoginErrorCode) -> Void] = []
    /// Can be called safely multi times
    func login() -> Single<Void> {
        func createLoginObserver() -> Single<Void> {
            .create { [weak self] observer in
                guard let self else {
                    observer(.failure("self not exist"))
                    return Disposables.create()
                }
                self.loginCallbacks.append { code in
                    if code == .ok || code == .alreadyLogin {
                        observer(.success(()))
                    } else {
                        observer(.failure("login error \(code)"))
                    }
                }
                return Disposables.create()
            }
        }
        switch state.value {
        case .connected, .reconnecting: return .just(())
        case .connecting: return createLoginObserver()
        case .idle:
            agoraKit.login(byToken: agoraGenerator.agoraToken,
                           user: agoraGenerator.agoraUserId) { [weak self] code in
                guard let self else { return }
                self.loginCallbacks.forEach { $0(code) }
                self.loginCallbacks = []
                self.state.accept(.connected)
            }
            return createLoginObserver()
        }
    }

    func leave() -> Single<Void> {
        switch state.value {
        case .idle, .connecting, .reconnecting: return .just(())
        case .connected:
            return Single<Void>.create { [weak self] observer in
                self?.agoraKit.logout(completion: { error in
                    if error == .ok {
                        observer(.success(()))
                    } else {
                        observer(.failure("rtm logout \(error)"))
                    }
                })
                return Disposables.create()
            }
        }
    }

    func joinChannelId(_ channelId: String) -> Single<RtmChannel> {
        .create { [weak self] observer in
            guard let self else {
                observer(.failure("self not exist"))
                return Disposables.create()
            }
            let handler = RtmChannel()
            handler.userUUID = agoraGenerator.agoraUserId
            handler.channelId = channelId
            let channel = self.agoraKit.createChannel(withId: channelId, delegate: handler)!
            handler.channel = channel
            logger.info("start join channel: \(channelId)")
            channel.join { error in
                if error == .channelErrorOk {
                    logger.info("start join channel: \(channelId) success")
                    observer(.success(handler))
                } else {
                    logger.error("join channel: \(channelId) fail, \(error)")
                    observer(.failure("join channel error \(error)"))
                }
            }
            return Disposables.create()
        }
    }

    fileprivate var agoraKit: AgoraRtmKit!
}

extension AgoraRtmConnectionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .reconnecting:
            return "reconnecting"
        case .aborted:
            return "aborted"
        @unknown default:
            return "unknown"
        }
    }
}

extension AgoraRtmConnectionChangeReason: CustomStringConvertible {
    public var description: String {
        switch self {
        case .login:
            return "login"
        case .loginSuccess:
            return "loginSuccess"
        case .loginFailure:
            return "loginFailure"
        case .loginTimeout:
            return "loginTimeout"
        case .interrupted:
            return "interrupted"
        case .logout:
            return "logout"
        case .bannedByServer:
            return "bannedByServer"
        case .remoteLogin:
            return "remoteLogin"
        @unknown default:
            return "unknown"
        }
    }
}

extension Rtm: AgoraRtmDelegate {
    func rtmKit(_: AgoraRtmKit, connectionStateChanged state: AgoraRtmConnectionState, reason: AgoraRtmConnectionChangeReason) {
        logger.info("state \(state), reason \(reason)")
        switch state {
        case .connected:
            self.state.accept(.connected)
        case .connecting:
            self.state.accept(.connecting)
        case .reconnecting:
            self.state.accept(.reconnecting)
            DispatchQueue.global().asyncAfter(deadline: .now() + reconnectTimeoutInterval) { [weak self] in
                guard let self else { return }
                if self.state.value == .reconnecting {
                    DispatchQueue.main.async {
                        self.error.accept(.reconnectingTimeout)
                    }
                }
            }
        case .aborted:
            logger.error("remote login")
            error.accept(.remoteLogin)
        default:
            return
        }
    }

    func rtmKit(_: AgoraRtmKit, messageReceived message: AgoraRtmMessage, fromPeer peerId: String) {
        logger.info("receive p2p message \(message.text)")
        if let rawMessage = message as? AgoraRtmRawMessage {
            p2pMessage.accept((rawMessage.rawData, peerId))
        }
    }
}
