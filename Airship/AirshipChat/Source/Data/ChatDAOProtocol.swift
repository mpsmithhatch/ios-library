/* Copyright Airship and Contributors */

import Foundation

#if canImport(AirshipCore)
import AirshipCore
#endif


protocol PendingChatMessageDataProtocol {
    var requestID: String {get}
    var text: String? {get}
    var attachment: URL? { get}
    var createdOn: Date {get}
    var direction: UInt {get}
}

protocol ChatMessageDataProtocol  {
    var messageID: Int {get}
    var requestID: String? {get}
    var text: String? {get}
    var createdOn: Date {get}
    var direction: UInt {get}
    var attachment: URL? {get}
}

/**
 * Chat data access protocol
 */
protocol ChatDAOProtocol {
    func upsertMessage(messageID: Int, requestID: String?, text: String?, createdOn: Date, direction: UInt, attachment: URL?)
    func upsertPending(requestID: String, text: String?, attachment: URL?, createdOn: Date, direction: UInt)
    func removePending(_ requestID: String)
    func fetchMessages(completionHandler: @escaping (Array<ChatMessageDataProtocol>, Array<PendingChatMessageDataProtocol>)->())
    func fetchPending(completionHandler: @escaping (Array<PendingChatMessageDataProtocol>)->())
    func hasPendingMessages(completionHandler: @escaping (Bool)->())
    func deleteAll()
}
