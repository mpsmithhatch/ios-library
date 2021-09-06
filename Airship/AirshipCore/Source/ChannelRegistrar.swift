/* Copyright Airship and Contributors */

// NOTE: For internal use only. :nodoc:
@objc(UAChannelRegistrarProtocol)
public protocol ChannelRegistrarProtocol {
    @objc
    var delegate : ChannelRegistrarDelegate? { get set}
    
    var channelID : String? { get }
    
    @objc(registerForcefully:)
    func register(forcefully: Bool)
    
    @objc
    func performFullRegistration()
}

/**
 * The UAChannelRegistrarDelegate protocol for registration events.
 * - Note: For internal use only. :nodoc:
 */
@objc(UAChannelRegistrarDelegate)
public protocol ChannelRegistrarDelegate {
    /**
     * Get registration payload for current channel
     *
     * - Note: This method will be called on the main thread.
     *
     * - Parameter completionHandler: A completion handler which will be passed the created registration payload.
     */
    @objc
    func createChannelPayload(completionHandler: @escaping (ChannelRegistrationPayload) -> ())
    
    /**
     * Called when the channel registrar failed to register.
     */
    func registrationFailed()
    
    /**
     * Called when the channel registrar successfully registered.
     */
    func registrationSucceeded()
    
    /**
     * Called when the channel registrar creates a new channel.
     * - Parameter channelID: The channel ID string.
     * - Parameter existing: Boolean to indicate if the channel previously existed or not.
     */
    func channelCreated(channelID: String, existing: Bool)
}

/**
* The ChannelRegistrar class is responsible for device registrations.
* - Note: For internal use only. :nodoc:
*/
@objc
public class ChannelRegistrar : NSObject, ChannelRegistrarProtocol {
    private static let forcefullyKey = "forcefully";
    private static let taskID = "UAChannelRegistrar.registration";
    private static let channelIDKey = "UAChannelID";
    private static let lastPayloadKey = "ChannelRegistrar.payload";
    private static let lastUpdateKey = "payload-update-key";
    private static let deviceIDKey = "deviceID";

    @objc
    public weak var delegate : ChannelRegistrarDelegate?
    
    private var _channelID: String? {
        get {
            self.dataStore.string(forKey: ChannelRegistrar.channelIDKey)
        }
        set {
            self.dataStore.setObject(newValue, forKey: ChannelRegistrar.channelIDKey)
            AirshipLogger.importantInfo("Channel ID: \(newValue ?? "")")
        }
    }
    
    private var lastSuccessPayload: ChannelRegistrationPayload? {
        get {
            if let data = self.dataStore.data(forKey: ChannelRegistrar.lastPayloadKey) {
                do {
                    return try ChannelRegistrationPayload.decode(data)
                } catch {
                    AirshipLogger.error("Unable to load last payload \(error)")
                    return nil
                }
            } else {
                return nil
            }
        }
        set {
            if (newValue != nil) {
                if let data = try? newValue?.encode() {
                    self.dataStore.setValue(data, forKey: ChannelRegistrar.lastPayloadKey)
                }
            } else {
                self.dataStore.removeObject(forKey: ChannelRegistrar.lastPayloadKey)
            }
        }
    }
    
    private var lastUpdateDate: Date {
        get {
            return self.dataStore.object(forKey: ChannelRegistrar.lastUpdateKey) as? Date ?? Date.distantPast
        }
        set {
            self.dataStore.setObject(newValue, forKey: ChannelRegistrar.lastUpdateKey)
        }
    }
    
    /**
     * The channel ID for this device.
     */
    @objc
    public var channelID : String? {
        get {
            return self._channelID
        }
    }
    
    private let dataStore: UAPreferenceDataStore
    private let channelAPIClient: ChannelAPIClient
    private let date: UADate
    private let dispatcher: UADispatcher
    private let taskManager: UATaskManager

    @objc
    public init(config: RuntimeConfig,
                dataStore: UAPreferenceDataStore,
                channelAPIClient: ChannelAPIClient,
                date: UADate,
                dispatcher: UADispatcher,
                taskManager: UATaskManager) {
        
        self.dataStore = dataStore
        self.channelAPIClient = channelAPIClient
        self.date = date
        self.dispatcher = dispatcher
        self.taskManager = taskManager
        
        super.init()

        if (self.channelID != nil) {
            self.dispatcher.dispatchAsync {
                self.checkAppRestore()
            }
        }
        
        self.taskManager.register(taskID: ChannelRegistrar.taskID, dispatcher: self.dispatcher) { [weak self] task in
            if (task.taskID == ChannelRegistrar.taskID) {
                self?.handleRegistrationTask(task)
            } else {
                AirshipLogger.error("Invalid task: \(task.taskID)")
                task.taskCompleted()
            }
        }
    }
    
    @objc
    public convenience init(config: RuntimeConfig,
                            dataStore: UAPreferenceDataStore) {
        self.init(config: config,
                  dataStore:dataStore,
                  channelAPIClient: ChannelAPIClient(config: config),
                  date: UADate(),
                  dispatcher: UADispatcher.serial(),
                  taskManager: UATaskManager.shared)
    }
    
    /**
     * Register the device with Airship.
     *
     * - Note: This method will execute asynchronously on the main thread.
     *
     * - Parameter forcefully: YES to force the registration.
     */
    public func register(forcefully: Bool) {
        let extras = [ChannelRegistrar.forcefullyKey: forcefully]
        let policy = forcefully ? UATaskConflictPolicy.replace : UATaskConflictPolicy.keep
        let options = UATaskRequestOptions(conflictPolicy: policy, requiresNetwork: true, extras: extras)
        
        self.taskManager.enqueueRequest(taskID: ChannelRegistrar.taskID, options: options)
    }
    
    /**
     * Performs a full channel registration.
     */
    @objc
    public func performFullRegistration() {
        self.dispatcher .dispatchAsync {
            self.lastSuccessPayload = nil
            self.lastUpdateDate = Date.distantPast
            self.register(forcefully: true)
        }
    }
    
    private func checkAppRestore() {
        let deviceID = UAKeychainUtils.getDeviceID()
        
        guard let previousDeviceID = self.dataStore.string(forKey: ChannelRegistrar.deviceIDKey) else {
            self.dataStore.setObject(deviceID, forKey:ChannelRegistrar.deviceIDKey)
            return
        }

        if (deviceID != previousDeviceID) {
            AirshipLogger.debug("Device ID changed.")
            self.clearChannelData()
            self.dataStore.setObject(deviceID, forKey:ChannelRegistrar.deviceIDKey)
        }
    }
    
    private func handleRegistrationTask(_ task: UATask) {
        AirshipLogger.trace("Handling registration task: \(task)")
        
        guard let payload = self.createPayload() else {
            AirshipLogger.error("Airship payload is nil, unable to update")
            task.taskFailed()
            return
        }
        
        let forcefully = task.requestOptions.extras[ChannelRegistrar.forcefullyKey] as? Bool ?? false
        let channelID = self.channelID
        let lastPayload = self.lastSuccessPayload
        let shouldUpdate = self.shouldUpdate(payload, lastPayload: lastPayload)
        
        guard (channelID == nil || forcefully || shouldUpdate) else {
            AirshipLogger.debug("Ignoring registration request, registration is up to date.")
            task.taskCompleted()
            return
        }
        
        if let channelID = channelID {
            self.updateChannel(channelID, payload: payload, lastPayload: payload, task: task)
        } else {
            self.createChannel(payload: payload, task: task)
        }
    }
    
    private func updateChannel(_ channelID: String, payload: ChannelRegistrationPayload, lastPayload: ChannelRegistrationPayload?,  task: UATask) {
        let semaphore = UASemaphore()
        let disposable = self.channelAPIClient.updateChannel(withID: channelID, withPayload: payload) { response, error in
            guard let response = response else {
                if let error = error {
                    AirshipLogger.error("Failed request with error: \(error)")
                }
                
                task.taskFailed()
                semaphore.signal()
                return
            }
            
            if (response.isSuccess) {
                AirshipLogger.debug("Channel updated succesfully")
                self.registrationFinished(payload, success: true)
                task.taskCompleted()
            } else if (response.status == 409) {
                AirshipLogger.trace("Channel conflict, recreating")
                self.clearChannelData()
                self.register(forcefully: true)
                task.taskCompleted()
            } else {
                AirshipLogger.debug("Channel update failed with response \(response)")
                self.registrationFinished(payload, success: false)
                if (response.isServerError || response.status == 429) {
                    task.taskFailed()
                } else {
                    task.taskCompleted()
                }
            }
            
            semaphore.signal()
        }
        
        task.expirationHandler = {
            disposable.dispose()
        }
        
        semaphore.wait()
    }
    
    private func createChannel(payload: ChannelRegistrationPayload, task: UATask) {
        let semaphore = UASemaphore()
        let disposable = self.channelAPIClient.createChannel(withPayload: payload) { response, error in
            
            guard let response = response else {
                if let error = error {
                    AirshipLogger.error("Failed request with error: \(error)")
                }
                
                task.taskFailed()
                semaphore.signal()
                return
            }
            
            if (response.isSuccess) {
                AirshipLogger.debug("Channel \(response.channelID!) created succesfully")
                self._channelID = response.channelID
                self.delegate?.channelCreated(channelID: response.channelID!, existing: response.status == 200)
                self.registrationFinished(payload, success: true)
                task.taskCompleted()
            } else {
                AirshipLogger.debug("Channel creation failed with response \(response)")
                self.registrationFinished(payload, success: false)
                
                if (response.isServerError || response.status == 429) {
                    task.taskFailed()
                } else {
                    task.taskCompleted()
                }
            }
            
            semaphore.signal()
        }
        
        task.expirationHandler = {
            disposable.dispose()
        }
        
        semaphore.wait()
    }
    
    private func clearChannelData() {
        self._channelID = nil
        self.lastUpdateDate = Date.distantPast
        self.lastSuccessPayload = nil
    }
    
    private func registrationFinished(_ payload: ChannelRegistrationPayload, success: Bool) {
        if (success) {
            self.lastSuccessPayload = payload
            self.lastUpdateDate = self.date.now
            delegate?.registrationSucceeded()
            
            if (self.shouldUpdate(self.createPayload(), lastPayload: payload)) {
                self.register(forcefully: false)
            }
        } else {
            delegate?.registrationFailed()
        }
    }

    
    private func shouldUpdate(_ payload: ChannelRegistrationPayload?, lastPayload: ChannelRegistrationPayload?) -> Bool {
        guard let payload = payload else {
            return false
        }
        
        let timeSinceLastUpdate = self.date.now.timeIntervalSince(self.lastUpdateDate)
        
        if (lastPayload == nil) {
            AirshipLogger.trace("Should update registration. Last payload is nil.")
            return true;
        }
        
        if (payload != lastPayload) {
            AirshipLogger.trace("Should update registration. Channel registration payload has changed.")
            return true
        }
        

        if (timeSinceLastUpdate >= (24 * 60 * 60)) {
            AirshipLogger.trace("Should update registration. Time since last registration time is greater than 24 hours.")
            return true
        }
        
        return false
    }
    
    private func createPayload() -> ChannelRegistrationPayload? {
        var result: ChannelRegistrationPayload?
        let semaphore = UASemaphore()
        
        guard let strongDelegate = delegate else {
            return nil
        }
        
        strongDelegate.createChannelPayload { payload in
            result = payload
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }

}
