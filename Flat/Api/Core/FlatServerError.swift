//
//  FlatServerError.swift
//  Flat
//
//  Created by xuyunshi on 2021/12/22.
//  Copyright © 2021 agora.io. All rights reserved.
//

import Foundation

enum FlatApiError: Int, LocalizedError {
    case ParamsCheckFailed = 100_000
    case ServerFail
    case CurrentProcessFailed
    case NotPermission
    case NeedLoginAgain
    case UnsupportedPlatform
    case JWTSignFailed

    case SMSVerificationCodeInvalid = 110_000
    // Bind when binding already
    case SMSAlreadyExist = 110_001
    // Bind a phone has registered
    case PhoneRegistered = 110_002

    case RoomNotFound = 200_000
    case RoomIsEnded
    case RoomIsRunning
    case RoomNotIsRunning
    case RoomNotIsEnded
    case RoomNotIsIdle

    case PeriodicNotFound = 300_000
    case PeriodicIsEnded
    case PeriodicSubRoomHasRunning

    case UserNotFound = 400_000
    case UserAlreadyBinding = 400_002

    case RecordNotFound = 50000

    case UploadConcurrentLimit = 700_000
    case NotEnoughTotalUsage
    case FileSizeTooBig
    case FileNotFound
    case FileExists

    case FileIsConverted = 80000
    case FileConvertFailed
    case FileIsConverting
    case FileIsConvertWaiting

    case LoginGithubSuspended = 90000
    case LoginGithubURLMismatch
    case LoginGithubAccessDenied

    var errorDescription: String? {
        localizeStrings(String(describing: self))
    }
}
