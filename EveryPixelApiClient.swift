//
//  EveryPixelApiClient.swift
//  TakeEatEasy
//
//  Created by Nadezhda Zenkova on 09.11.2021.
//

import UIKit

enum EveryPixelNetworkError: Error {
    case noAccess
    case exceedAvailableRequests
    case apiError(message: String)
}

struct Token: Codable {
    var token: String
    var type: String
    var scope: String
    
    enum CodingKeys: String, CodingKey {
        case token = "access_token"
        case type = "token_type"
        case scope
    }
}

extension EveryPixelNetworkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noAccess:
            return NSLocalizedString("Developer has no access to a specified endpoint. It might happen if access token has been expired", comment: "401 Every Pixel Network Error")
        case .exceedAvailableRequests:
            return NSLocalizedString("Developer has exceeded available requests from plan", comment: "429 Every Pixel Network Error")
        case .apiError(message: let message):
            return NSLocalizedString(message, comment: "Every Pixel Network Error")
        }
    }
}

enum EveryPixelStatus: String {
    case ok = "ok"
    case error = "error"
}

struct EveryPixelApiErrorModel: Codable {
    var status: String
    var message: String
    
    enum CodingKeys: String, CodingKey {
        case status, message
    }
}

struct EveryPixelMessageErrorModel: Codable {
    var message: String
    
    enum CodingKeys: String, CodingKey {
        case message
    }
}

protocol EveryPixelApiClientProtocol {
    
    func getTagsRequest(image: UIImage, imageName: String, accuracy: Float, completion: @escaping (Result<[TagModel], EveryPixelNetworkError>) -> Void)
    
    func checkTokenExpiration()
}

class EveryPixelApiClient: EveryPixelApiClientProtocol {
    
    //
    // MARK: - Constants
    //

    private let scheme = "https"
    private let host = "api.everypixel.com"
    private let hostPath = "https://api.everypixel.com"
    private let keywordsPath = "/v1/keywords"
    private let authorizationPath = "/oauth/token"
    private let apiEndpoint = "https://api.everypixel.com/v1/keywords"
    
    private let clientID = "123456"
    private let clientSecret = "qwerty"
    private var token: String?
    private var tokenSaved: Bool?
    private var lastDateTokenSaved: Date?
    private let keychainService = KeychainService()
    
    // MARK: - Type Alias
    //
    
    public typealias KeywordsRequestResult = [String : [TagModel]]
    public typealias TagsResult = (Result<[TagModel], EveryPixelNetworkError>) -> Void
    private typealias Parameters = [String: String]
    
    //
    // MARK: - Init
    //
    
    public func checkTokenExpiration() {
        if hasTokenExpired() {
            refreshToken()
        }
    }
    
    //
    // MARK: - Public Methods
    //
    
    public func getTagsRequest(image: UIImage, imageName: String, accuracy: Float, completion: @escaping TagsResult) {
        
        self.checkTokenExpiration()
        
        let boundary = generateBoundary()
        var uploadRequest = uploadRequestWith(boundary: boundary, accuracy: accuracy)
        
        let data = createDataBody(photo: image, fileName: imageName, boundary: boundary)
        uploadRequest?.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        
        guard let request = uploadRequest else { return }
        
        let task = URLSession.shared.uploadTask(with: request, from: data) {
            data, response, error in
            guard let response = response as? HTTPURLResponse else {
                if let errorMessage = self.parseMessageError(from: data ?? Data()) {
                    DispatchQueue.main.async {
                        completion(.failure(.apiError(message: errorMessage)))
                    }
                }
                return
            }
            switch response.statusCode {
            case 429:
                completion(.failure(.exceedAvailableRequests))
            case 401:
                completion(.failure(.noAccess))
            case 200:
                if let status = self.parseStatus(from: data ?? Data()) {
                    switch status {
                    case .ok:
                        if let tags = self.parseTags(from: data ?? Data()) {
                            DispatchQueue.main.async {
                                completion(.success(tags))
                            }
                        }
                    case .error:
                        if let errorMessage = self.parseApiError(from: data ?? Data()) {
                            DispatchQueue.main.async {
                                completion(.failure(.apiError(message: errorMessage)))
                            }
                        }
                    }
                }
            default:
                if let errorMessage = self.parseMessageError(from: data ?? Data()) {
                    DispatchQueue.main.async {
                        completion(.failure(.apiError(message: errorMessage)))
                    }
                }
            }
        }
        
        task.resume()
    }
    
    //
    // MARK: - Private Methods
    //
    
    private func signInRequest(completion: @escaping (String?) -> Void) {
        guard let request = signInUrlRequest() else { return }
        
        let task = URLSession.shared.dataTask(with: request) {
            data, response, error in
            
            if let response = response as? HTTPURLResponse,
                      response.statusCode != 200 {
                completion(nil)
            } else if let data = data,
                      let response = response as? HTTPURLResponse,
                      response.statusCode == 200 {
                guard let token = self.parseToken(from: data)?.token else { return }
                completion(token)
            }
            
        }
        
        task.resume()
    }
    
    private func signInUrlRequest() -> URLRequest? {
        var urlComponents = URLComponents()
        urlComponents.scheme = scheme
        urlComponents.host = host
        urlComponents.path = keywordsPath
        urlComponents.queryItems = [URLQueryItem(name: "client_id", value: "\(clientID)"),
                                    URLQueryItem(name: "client_secret", value: "\(clientSecret)"),
                                    URLQueryItem(name: "grant_type", value: "client_credentials")]
        
        guard let url = URL(string: "https://api.everypixel.com/oauth/token") else {return nil}
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let postData = "client_id=4W6PvhrpejcQ2uV8aPNtnLOD&client_secret=mSVrJKYPtTa1oHlqw7D1cUg54AGqux5E4y5WLCryGbCAg67t&grant_type=client_credentials".data(using: .utf8)
        request.httpBody = postData
        return request
    }
    
    private func uploadRequestWith(boundary: String, accuracy: Float) -> URLRequest? {
        guard let token = keychainService.readToken() else { return nil }
        
        var urlComponents = URLComponents()
        urlComponents.scheme = scheme
        urlComponents.host = host
        urlComponents.path = keywordsPath
        urlComponents.queryItems = [URLQueryItem(name: "num_keywords", value: "5"), URLQueryItem(name: "threshold", value: "\(accuracy)")]
        
        guard let url = urlComponents.url else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        return request
    }
    
    private func createDataBody(photo: UIImage?,  fileName: String, boundary: String) -> Data {
        let mimeType = "image/jpeg"
        let paramName = "data"
        let fileData = photo?.jpegData(compressionQuality: 1.0)
        let lineBreak = "\r\n"
        var body = Data()
        
        if let data = fileData {
            body.appendString("\(lineBreak)--\(boundary + lineBreak)")
            body.appendString("Content-Disposition: form-data; name=\"\(paramName)\"; filename=\"\(fileName)\"\(lineBreak)")
            body.appendString("Content-Type: \(mimeType + lineBreak + lineBreak)")
            body.append(data)
            body.appendString("\(lineBreak)--\(boundary)--\(lineBreak)")
        }
        
        return body
    }
    
    private func parseToken(from data: Data) -> Token? {
        return parseData(data, as: Token.self)
    }
    
    private func parseTags(from data: Data) -> [TagModel]? {
        guard let tagResults = parseData(data, as: TagResultsModel.self) else { return nil }
        return tagResults.keywords
    }
    
    private func parseApiError(from data: Data) -> String? {
        guard let errorMessage = parseData(data, as: EveryPixelApiErrorModel.self) else { return nil }
        return errorMessage.message
    }
    
    private func parseStatus(from data: Data) -> EveryPixelStatus? {
        guard let statusModel = parseData(data, as: StatusModel.self) else { return nil }
        return EveryPixelStatus(rawValue: statusModel.status)
    }
    
    private func parseMessageError(from data: Data) -> String? {
        return parseData(data, as: String.self)
    }
    
    private func parseData<T: Decodable>(_ data: Data, as type: T.Type) -> T? {
        let decoder = JSONDecoder()
        do {
            let parsedData = try decoder.decode(T.self, from: data)
            return parsedData
        } catch {
            return nil
        }
    }
    
    private func generateBoundary() -> String {
        return UUID().uuidString
    }
    
    private func hasTokenExpired() -> Bool {
        guard let lastDateTokenSaved = self.lastDateTokenSaved else { return true }
        let oneHourAgo = Date().addingTimeInterval(-3600)
        return lastDateTokenSaved < oneHourAgo
    }
    
    private func refreshToken() {
        signInRequest { [weak self] token in
            if let token = token {
                self?.tokenSaved = (self?.keychainService.saveToken(token: token)) != nil
                self?.lastDateTokenSaved = Date()
            }
        }
    }
}


extension Data {
    mutating func append(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
            append(data)
    }
}

