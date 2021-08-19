/* Copyright Airship and Contributors */

// NOTE: For internal use only. :nodoc:
@objc(UARemoteConfigManager)
public class RemoteConfigManager : NSObject {
    
    @objc
    public static let remoteConfigUpdatedEvent = Notification.Name("com.urbanairship.airship_remote_config_updated")
    
    @objc
    public static let remoteConfigKey = "remote_config"
    
    private let decoder = JSONDecoder()
    private var remoteDataSubscription: UADisposable?
    private let moduleAdapter: RemoteConfigModuleAdapterProtocol
    private let remoteDataManager: UARemoteDataProvider
    private let privacyManager: UAPrivacyManager
    private let versionBlock: (() -> String)
    private let notificationCenter: NotificationCenter

    @objc
    public convenience init(remoteDataManager: UARemoteDataProvider,
                            privacyManager: UAPrivacyManager) {

        self.init(remoteDataManager: remoteDataManager,
                  privacyManager: privacyManager,
                  moduleAdapter: RemoteConfigModuleAdapter(),
                  notificationCenter: NotificationCenter.default,
                  versionBlock: { return UAUtils.bundleShortVersionString() ?? "" })
    }
    
    init(remoteDataManager: UARemoteDataProvider,
         privacyManager: UAPrivacyManager,
         moduleAdapter: RemoteConfigModuleAdapterProtocol,
         notificationCenter: NotificationCenter,
         versionBlock: @escaping () -> String) {
        
        self.remoteDataManager = remoteDataManager
        self.privacyManager = privacyManager
        self.moduleAdapter = moduleAdapter
        self.versionBlock = versionBlock
        self.notificationCenter = notificationCenter
        
        super.init()
        
        updateRemoteConfigSubscription()

        self.notificationCenter.addObserver(
            self,
            selector: #selector(updateRemoteConfigSubscription),
            name: UAPrivacyManager.changeEvent,
            object: nil)
    }
    
    deinit {
        remoteDataSubscription?.dispose()
    }
    
    func processRemoteConfig(_ payloads: [UARemoteDataPayload]?) {
        // Combine the data
        var combinedData: [AnyHashable : Any] = [:]
        payloads?.forEach {
            combinedData.merge($0.data) { (current, _) in current }
        }

        // Disable features
        applyDisableInfos(combinedData)

        // Module config
        applyConfigs(combinedData)

        //Remote config
        applyRemoteConfig(combinedData)
    }

    func applyDisableInfos(_ data: [AnyHashable : Any]) {
        let disableJSONArray = data["disable_features"] as? [[AnyHashable : Any]]
        let versionObject = [ "ios": [ "version": versionBlock() ] ]
        
        let disableInfos = disableJSONArray?
            .compactMap { return RemoteConfigDisableInfo(json: $0) }
            .filter { info in
                if (info.appVersionConstraint?.evaluateObject(versionObject) == false) {
                    return false
                }
                
                if (!info.sdkVersionConstraints.isEmpty) {
                    let matches = info.sdkVersionConstraints.contains(where: { return $0.evaluateObject(UAirshipVersion.get()) })
                    if (!matches) {
                        return false
                    }
                }
                
                return true
            }
        
        var disableModules: [RemoteConfigModule] = []
        var remoteDataRefreshInterval: TimeInterval = 10.0
        
        disableInfos?.forEach {
            disableModules.append(contentsOf: $0.disableModules)
            remoteDataRefreshInterval = max(remoteDataRefreshInterval, ($0.remoteDataRefreshInterval ?? 0.0))
        }
        
        let disabled = Set(disableModules)
        disabled.forEach { moduleAdapter.setComponentsEnabled(false, module: $0)}

        let enabled = Set(RemoteConfigModule.allCases).subtracting(disabled)
        enabled.forEach { moduleAdapter.setComponentsEnabled(true, module: $0)}
        
        remoteDataManager.setRefreshInterval(remoteDataRefreshInterval)
    }

    func applyConfigs(_ data: [AnyHashable : Any]) {
        RemoteConfigModule.allCases.forEach {
            self.moduleAdapter.applyConfig(data[$0.rawValue], module: $0)
        }
    }

    func applyRemoteConfig(_ data: [AnyHashable : Any]) {
        guard let remoteConfigData = data["airship_config"] else {
            return
        }
    
        var parsedConfig: RemoteConfig?
        do {
            let data = try JSONSerialization.data(withJSONObject: remoteConfigData, options: [])
            parsedConfig = try self.decoder.decode(RemoteConfig.self, from: data)
        } catch {
            AirshipLogger.error("Invalid remote config \(error)")
            return
        }
        
        guard let remoteConfig = parsedConfig else {
            return
        }
        
        self.notificationCenter.post(name: RemoteConfigManager.remoteConfigUpdatedEvent,
                                     object: nil,
                                     userInfo: [RemoteConfigManager.remoteConfigKey : remoteConfig])
    }

    @objc
    func updateRemoteConfigSubscription() {
        if self.privacyManager.isAnyFeatureEnabled() && self.remoteDataSubscription == nil {
            self.remoteDataSubscription = self.remoteDataManager.subscribe(
                withTypes: ["app_config", "app_config:ios"],
                block: { [weak self] remoteConfig in
                    self?.processRemoteConfig(remoteConfig)
                })
        } else {
            remoteDataSubscription?.dispose()
            remoteDataSubscription = nil
        }
    }
}
