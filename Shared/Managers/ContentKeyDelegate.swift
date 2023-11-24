/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 `ContentKeyDelegate` is a class that implements the `AVContentKeySessionDelegate` protocol to respond to content key
 requests using FairPlay Streaming.
 */

import AVFoundation

class ContentKeyDelegate: NSObject, AVContentKeySessionDelegate {
    
    // MARK: Types
    
    enum ProgramError: Error {
        case missingApplicationCertificate
        case noCKCReturnedByKSM
    }
    
    var applicationCertificate: Data? = nil
    
    var cslToken : String? = nil
    var renewalPeriod : Int? = nil
    
    // MARK: Properties
    
    /// The directory that is used to save persistable content keys.
    lazy var contentKeyDirectory: URL = {
        guard let documentPath =
            NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
                fatalError("Unable to determine library URL")
        }
        
        let documentURL = URL(fileURLWithPath: documentPath)
        
        let contentKeyDirectory = documentURL.appendingPathComponent(".keys", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: contentKeyDirectory.path, isDirectory: nil) {
            do {
                try FileManager.default.createDirectory(at: contentKeyDirectory,
                                                    withIntermediateDirectories: false,
                                                    attributes: nil)
            } catch {
                fatalError("Unable to create directory for content keys at path: \(contentKeyDirectory.path)")
            }
        }
        
        return contentKeyDirectory
    }()
    
    /// A set containing the currently pending content key identifiers associated with persistable content key requests that have not been completed.
    var pendingPersistableContentKeyIdentifiers = Set<Int>()
    
    /// A dictionary mapping content key identifiers to their associated stream name.
    var contentKeyToStreamNameMap = [Int: String]()
    
    var assetsToken: String? = nil
    
    func requestApplicationCertificate(_ asset: Asset?) throws -> Data {
        
        guard let asset = asset else {
            return Data()
        }
        
        let token: String? = nil // "{authToken}"
        
        /// NOTE: code below is useful when you want to close DRMToday API in a framework
        let data = try JSONEncoder().encode(asset.stream)
        let stream = try JSONDecoder().decode(Stream.self, from: data)
        
        if (applicationCertificate == nil) {
            let group = DispatchGroup()
            group.enter()
            
            DRMtoday.getCertificate(stream: stream, token: token) { (certificate) in
                self.applicationCertificate = certificate
                group.leave()
            }
            group.wait()
        }
        
        guard applicationCertificate != nil else {
            throw ProgramError.missingApplicationCertificate
        }
        
        assetsToken = token
        return applicationCertificate!
    }
    
    func getDocumentsDirectory() -> URL {
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            return paths[0]
        
        }
    
    func requestContentKeyFromKeySecurityModule(_ asset: Asset?, spcData: Data, assetID: String, persistable: Bool) throws -> Data {
        
        // MARK: ADAPT - You must implement this method to request a CKC from your KSM.
        
        guard let asset = asset else {
                    return Data()
                }
        
        var ckcData: Data? = nil
                
        let data = try JSONEncoder().encode(asset.stream)
        let stream = try JSONDecoder().decode(Stream.self, from: data)
        let token : String? = nil // "{authToken}"
        
        let group = DispatchGroup()
        group.enter()

        DRMtoday.getLicense(stream: stream, spcData: spcData, token: token, offline: persistable, cslToken: self.cslToken) { (ckc, newCslToken, renewalPeriod ) in
            ckcData = ckc
            self.cslToken = newCslToken
            self.renewalPeriod = renewalPeriod
            
            let escapedName = asset.stream.name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            let filename = self.getDocumentsDirectory().appendingPathComponent("").appendingPathComponent(escapedName! + (persistable ? "offline" : "online") + ".dat")
            do {
                try ckcData?.write(to: filename, options: .atomicWrite)
            } catch {
                print("Unable to write a license file")
            }
            group.leave()
        }
        group.wait()
        
        guard ckcData != nil else {
            throw ProgramError.noCKCReturnedByKSM
        }
        
        return ckcData!
    }

    /// Preloads all the content keys associated with an Asset for persisting on disk.
    ///
    /// It is recommended you use AVContentKeySession to initiate the key loading process
    /// for online keys too. Key loading time can be a significant portion of your playback
    /// startup time because applications normally load keys when they receive an on-demand
    /// key request. You can improve the playback startup experience for your users if you
    /// load keys even before the user has picked something to play. AVContentKeySession allows
    /// you to initiate a key loading process and then use the key request you get to load the
    /// keys independent of the playback session. This is called key preloading. After loading
    /// the keys you can request playback, so during playback you don't have to load any keys,
    /// and the playback decryption can start immediately.
    ///
    /// In this sample use the Streams.plist to specify your own content key identifiers to use
    /// for loading content keys for your media. See the README document for more information.
    ///
    /// - Parameter asset: The `Asset` to preload keys for.
    func requestPersistableContentKeys(forAsset asset: Asset) {
        for identifier in asset.stream.contentKeyIDList ?? [] {
            
            guard let contentKeyIdentifierURL = URL(string: identifier) else { continue }
            let assetID = contentKeyIdentifierURL.absoluteString.hash
            
            pendingPersistableContentKeyIdentifiers.insert(assetID)
            contentKeyToStreamNameMap[assetID] = asset.stream.name
            
            ContentKeyManager.shared.contentKeySession.processContentKeyRequest(withIdentifier: identifier, initializationData: nil, options: nil)
        }
    }
    
    /// Returns whether or not a content key should be persistable on disk.
    ///
    /// - Parameter identifier: The asset ID associated with the content key request.
    /// - Returns: `true` if the content key request should be persistable, `false` otherwise.
    func shouldRequestPersistableContentKey(withIdentifier identifier: Int) -> Bool {
        return pendingPersistableContentKeyIdentifiers.contains(identifier)
    }
    
    // MARK: AVContentKeySessionDelegate Methods
    
    /*
     The following delegate callback gets called when the client initiates a key request or AVFoundation
     determines that the content is encrypted based on the playlist the client provided when it requests playback.
     */
    func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVContentKeyRequest) {
        handleStreamingContentKeyRequest(keyRequest: keyRequest, session: session)
    }
    
    /*
     Provides the receiver with a new content key request representing a renewal of an existing content key.
     Will be invoked by an AVContentKeySession as the result of a call to -renewExpiringResponseDataForContentKeyRequest:.
     */
    func contentKeySession(_ session: AVContentKeySession, didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest) {
        handleStreamingContentKeyRequest(keyRequest: keyRequest, session: session)
    }
    
    /*
     Provides the receiver a content key request that should be retried because a previous content key request failed.
     Will be invoked by an AVContentKeySession when a content key request should be retried. The reason for failure of
     previous content key request is specified. The receiver can decide if it wants to request AVContentKeySession to
     retry this key request based on the reason. If the receiver returns YES, AVContentKeySession would restart the
     key request process. If the receiver returns NO or if it does not implement this delegate method, the content key
     request would fail and AVContentKeySession would let the receiver know through
     -contentKeySession:contentKeyRequest:didFailWithError:.
     */
    func contentKeySession(_ session: AVContentKeySession, shouldRetry keyRequest: AVContentKeyRequest,
                           reason retryReason: AVContentKeyRequestRetryReason) -> Bool {
        var shouldRetry = false
        
        switch retryReason {
            /*
             Indicates that the content key request should be retried because the key response was not set soon enough either
             due the initial request/response was taking too long, or a lease was expiring in the meantime.
             */
        case AVContentKeyRequestRetryReason.timedOut:
            shouldRetry = true
            
            /*
             Indicates that the content key request should be retried because a key response with expired lease was set on the
             previous content key request.
             */
        case AVContentKeyRequestRetryReason.receivedResponseWithExpiredLease:
            shouldRetry = true
            
            /*
             Indicates that the content key request should be retried because an obsolete key response was set on the previous
             content key request.
             */
        case AVContentKeyRequestRetryReason.receivedObsoleteContentKey:
            shouldRetry = true
            
        default:
            break
        }
        
        return shouldRetry
    }
    
    // Informs the receiver a content key request has failed.
    func contentKeySession(_ session: AVContentKeySession, contentKeyRequest keyRequest: AVContentKeyRequest, didFailWithError err: Error) {
        // Add your code here to handle errors.
        print("Error: \(err)")
    }
    
    // MARK: API
    
    func handleStreamingContentKeyRequest(keyRequest: AVContentKeyRequest, session: AVContentKeySession) {
        guard let contentKeyIdentifierString = keyRequest.identifier as? String,
            let contentKeyIdentifierURL = URL(string: contentKeyIdentifierString),
            let assetIDString = contentKeyIdentifierURL.host,
              let assetIDData = contentKeyIdentifierString.data(using: .utf8)
            else {
                print("Failed to retrieve the assetID from the keyRequest!")
                return
        }
        
        let assetID = contentKeyIdentifierURL.absoluteString.hash
        var asset: Asset? = nil
        for index in 0..<AssetListManager.sharedManager.numberOfAssets() {
            let a = AssetListManager.sharedManager.asset(at: index)
            if a.stream.contentKeyIDList?.contains(contentKeyIdentifierString) == true {
                asset = a
                break
            }
        }

        let provideOnlinekey: () -> Void = { () -> Void in

            do {
                let applicationCertificate = try self.requestApplicationCertificate(asset)

                let completionHandler = { [weak self] (spcData: Data?, error: Error?) in
                    guard let strongSelf = self else { return }
                    if let error = error {
                        keyRequest.processContentKeyResponseError(error)
                        return
                    }

                    guard let spcData = spcData else { return }

                    do {
                        // Send SPC to Key Server and obtain CKC
                        let ckcData = try strongSelf.requestContentKeyFromKeySecurityModule(asset, spcData: spcData, assetID: assetIDString, persistable: false)

                        /*
                         AVContentKeyResponse is used to represent the data returned from the key server when requesting a key for
                         decrypting content.
                         */
                        let keyResponse = AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckcData)

                        /*
                         Provide the content key response to make protected content available for processing.
                         */
                        keyRequest.processContentKeyResponse(keyResponse)
                        
                        if self?.renewalPeriod != nil {
                            print("Key is due to expire. Setting timer for renewal in \(self?.renewalPeriod) secs.")
                            
                            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds((self!.renewalPeriod!))) { [weak self] in
                                guard let self = self else {
                                    print("ContentKeyDelegate instance destroyed before renewal timer fired")
                                    return
                                }
                                print(">>> renewing license")
                                session.renewExpiringResponseData(for: keyRequest)
                            }
                        }
                        
                    } catch {
                        keyRequest.processContentKeyResponseError(error)
                    }
                }

                keyRequest.makeStreamingContentKeyRequestData(forApp: applicationCertificate,
                                                              contentIdentifier: assetIDData,
                                                              options: [AVContentKeyRequestProtocolVersionsKey: [1]],
                                                              completionHandler: completionHandler)
            } catch {
                keyRequest.processContentKeyResponseError(error)
            }
        }

        #if os(iOS)
            /*
             When you receive an AVContentKeyRequest via -contentKeySession:didProvideContentKeyRequest:
             and you want the resulting key response to produce a key that can persist across multiple
             playback sessions, you must invoke -respondByRequestingPersistableContentKeyRequest on that
             AVContentKeyRequest in order to signal that you want to process an AVPersistableContentKeyRequest
             instead. If the underlying protocol supports persistable content keys, in response your
             delegate will receive an AVPersistableContentKeyRequest via -contentKeySession:didProvidePersistableContentKeyRequest:.
             */
            if shouldRequestPersistableContentKey(withIdentifier: assetID) ||
                persistableContentKeyExistsOnDisk(withContentKeyIdentifier: assetIDString) {
                
                // Request a Persistable Key Request.
                do {
                    try keyRequest.respondByRequestingPersistableContentKeyRequestAndReturnError()
                } catch {

                    /*
                    This case will occur when the client gets a key loading request from an AirPlay Session.
                    You should answer the key request using an online key from your key server.
                    */
                    provideOnlinekey()
                }
                
                return
            }
        #endif
        
        provideOnlinekey()
    }
}
