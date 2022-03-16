/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 A simple class that represents an entry from the `Streams.plist` file in the main application bundle.
 */

import Foundation

public class Stream: Codable {
    
    // MARK: Types
    
    enum CodingKeys: String, CodingKey {
        case name = "name"
        case playlistURL = "playlist_url"
        case isProtected = "is_protected"
        case contentKeyIDList = "content_key_id_list"
        case variantId = "variant_id"
        case assetId = "asset_id"
        case userId = "user_id"
        case sessionId = "session_id"
        case merchant = "merchant"
        case environment = "environment"
        case minimumDownloadBitrate = "minimum_download_bitrate"
    }
    
    // MARK: Properties

    /// DRMToday variantId
    let variantId: String?

    /// DRMToday assetId
    let assetId: String?

    /// DRMToday variables
    let userId: String?
    let sessionId: String?
    let merchant: String?
    let environment: String?

    /// The name of the stream.
    let name: String
    
    /// The URL pointing to the HLS stream.
    let playlistURL: String
    
    /// A Boolen value representing if the stream uses FPS.
    let isProtected: Bool

    /// An array of content IDs to use for loading content keys with FPS.
    let contentKeyIDList: [String]?

    /// AVAssetDownloadTaskMinimumRequiredMediaBitrateKey
    /// https://developer.apple.com/documentation/avfoundation/avassetdownloadtaskminimumrequiredmediabitratekey?language=objc
    let minimumDownloadBitrate: UInt
}

extension Stream: Equatable {
    public static func ==(lhs: Stream, rhs: Stream) -> Bool {
        var isEqual = (lhs.name == rhs.name) && (lhs.playlistURL == rhs.playlistURL) && (lhs.isProtected == rhs.isProtected)
        
        let lhsAssetId = lhs.assetId ?? ""
        let rhsAssetId = rhs.assetId ?? ""
        isEqual = isEqual && (lhsAssetId == rhsAssetId)

        let lhsVariantId = lhs.variantId ?? ""
        let rhsVariantId = rhs.variantId ?? ""
        isEqual = isEqual && (lhsVariantId == rhsVariantId)

        let lhsContentKeyIDList = lhs.contentKeyIDList ?? []
        let rhsContentKeyIDList = rhs.contentKeyIDList ?? []

        isEqual = isEqual && lhsContentKeyIDList.elementsEqual(rhsContentKeyIDList)

        return isEqual
    }
}
