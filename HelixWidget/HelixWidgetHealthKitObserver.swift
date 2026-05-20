import HealthKit
import WidgetKit

struct HelixWidgetHealthKitObserver {

    static let shared = HelixWidgetHealthKitObserver()
    private let store = HKHealthStore()

    private let observedTypes: [HKSampleType] = [
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    ]

    func registerBackgroundDelivery() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        for sampleType in observedTypes {
            let query = HKObserverQuery(sampleType: sampleType,
                                        predicate: nil) { _, completionHandler, error in
                guard error == nil else {
                    completionHandler()
                    return
                }
                WidgetCenter.shared.reloadAllTimelines()
                completionHandler()
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: sampleType,
                                           frequency: .immediate) { _, _ in }
        }
    }
}
