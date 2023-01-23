//
//  DRMtoday.swift
//  HLSCatalog
//
//  Created by Tomica Gril on 15.03.2022..
//  Copyright © 2022 Apple Inc. All rights reserved.
//

import Foundation

public struct DRMtoday {

    static let session = URLSession.shared
    static var tasks = [URLSessionDataTask]()

    static func getDrmTodayFairplayCertificateUrl(_ environment: String) -> String {
        switch environment {
        case "testing":
            return "https://lic.test.drmtoday.com/license-server-fairplay/cert/"
        case "staging":
            return "https://lic.staging.drmtoday.com/license-server-fairplay/cert/"
        case "production":
            return "https://lic.drmtoday.com/license-server-fairplay/cert/"
        default:
            return ""
        }
    }

    public static func getCertificate(stream: Stream, token: String?, completion: ((_ certificate: Data?) -> Void)?) {
        let urlComponents = URLComponents(string: getDrmTodayFairplayCertificateUrl(stream.environment!))
        guard let url = urlComponents?.url else { return }

        var request = URLRequest(url: url)
        if (token != nil) {
            request.setValue(token, forHTTPHeaderField: "x-dt-auth-token")
        }
        else {
            let dict = ["merchant": stream.merchant,
                        "userId": stream.userId,
                        "sessionId": stream.sessionId]
            do {
                let customData = try JSONSerialization.data(withJSONObject: dict, options: [])
                request.setValue(customData.base64EncodedString(), forHTTPHeaderField: "x-dt-custom-data")
            } catch {
            }
        }

        for t in tasks {
            if t.taskDescription == stream.playlistURL {
                completion?(nil)
                return
            }
        }
        print("Calling: \(url.absoluteString)")
//        let requestBody = request.httpBody?.base64EncodedString()
//        print("Certificate request body: ", requestBody!)
        print("Certificate request headers: ", request.allHTTPHeaderFields!)

        let task = session.dataTask(with: request, completionHandler: { (data: Data?, response: URLResponse?, error: Error?) -> Void in
            if let httpResponse = response as? HTTPURLResponse {
                let responseBody = data?.base64EncodedString()
                print("Certificate response body: ", responseBody!)
                print("Certificate response headers: ", httpResponse.allHeaderFields)
            }

            if let error = error {
                print("URL Session Task Failed: %@", error.localizedDescription)
                return
            }
            completion?(data)

            var i = 0
            for t in tasks {
                if t.taskDescription == stream.playlistURL {
                    tasks.remove(at: i)
                }
                i += 1
            }
        })
        task.taskDescription = stream.playlistURL
        task.resume()

        tasks.append(task)
    }

    static func getDrmTodayFairplayLicenseUrl(_ environment: String) -> String {
        switch environment {
        case "testing":
            return "https://lic.test.drmtoday.com/license-server-fairplay/"
        case "staging":
            return "https://lic.staging.drmtoday.com/license-server-fairplay/"
        case "production":
            return "https://lic.drmtoday.com/license-server-fairplay/"
        default:
            return ""
        }
    }

    static func encode(value url: String?) -> String {
        let queryKeyValueString = CharacterSet(charactersIn: ":?=&+").inverted
        return url?.addingPercentEncoding(withAllowedCharacters: queryKeyValueString) ?? ""
    }

    public static func getLicense(stream: Stream, spcData: Data, token: String?, offline: Bool, completion: ((_ ckcData: Data?) -> Void)?) {
        var urlComponents = URLComponents(string: getDrmTodayFairplayLicenseUrl(stream.environment!))
        if offline {
            urlComponents?.queryItems = [URLQueryItem(name: "offline", value: "true")]
        }
        guard let url = urlComponents?.url else { return }
        var request = URLRequest(url: url)

        let encodedSpcMessage = encode(value: spcData.base64EncodedString())
        print("SPC base64:", encodedSpcMessage)
        var post = String(format: "spc=%@", encodedSpcMessage)

        /// Additional params can be added to the post data
        var postItems = Dictionary<String, String>()
        if offline {
            postItems["offline"] = "true"
        }
        
        // REMARK: By providing assetId and variantId in query string parameters of the DRM license request, values from SKD are overridden.
        //         Additionally, requesting DRM license by assetId will work only for single key content but fail for multi-key content.
        //         Please use those two properties with caution and for debugging purposes only.
        //postItems["assetId"] = stream.assetId
        //postItems["variantId"] = stream.variantId

        if postItems.count > 0 {
            for element in postItems {
                post.append(contentsOf: String(format: "&%@=%@", element.key, element.value))
            }
        }
        request.httpMethod = "POST"
        request.httpBody = post.data(using: .utf8, allowLossyConversion: true)
        
        if (token != nil) {
            request.setValue(token, forHTTPHeaderField: "x-dt-auth-token")
        }
        else {
            let dict = ["merchant": stream.merchant,
                        "userId": stream.userId,
                        "sessionId": stream.sessionId]
            do {
                let customData = try JSONSerialization.data(withJSONObject: dict, options: [])
                request.setValue(customData.base64EncodedString(), forHTTPHeaderField: "x-dt-custom-data")
            } catch {
            }
        }
        
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(String(format: "%lu", request.httpBody?.count ?? 0), forHTTPHeaderField: "Content-Length")

        for t in tasks {
            if t.taskDescription == stream.playlistURL {
                completion?(nil)
                return
            }
        }
        print("Calling: \(url.absoluteString)")
        let requestBody = request.httpBody?.base64EncodedString()
        print("License request body: ", requestBody!)
        print("License request headers: ", request.allHTTPHeaderFields!)

        let task = session.dataTask(with: request, completionHandler: { (data: Data?, response: URLResponse?, error: Error?) -> Void in
            if let httpResponse = response as? HTTPURLResponse {
                let responseBody = String(data: data!, encoding: String.Encoding.ascii)
                print("License response body: ", responseBody!)
                print("License response headers: ", httpResponse.allHeaderFields)
            }

            if let error = error {
                print("URL Session Task Failed: %@", error.localizedDescription)
                return
            }
            let ckcMessage = Data(base64Encoded: data!)
            let ckcBase64 = data?.base64EncodedString()
            print("CKC base64:", ckcBase64!)
            completion?(ckcMessage)

            var i = 0
            for t in tasks {
                if t.taskDescription == stream.playlistURL {
                    tasks.remove(at: i)
                }
                i += 1
            }
        })
        task.taskDescription = stream.playlistURL
        task.resume()

        tasks.append(task)
    }
}
