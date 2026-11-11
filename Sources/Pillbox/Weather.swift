import CoreLocation
import Foundation

/// One current reading, as the Home tab shows it.
struct WeatherReading: Equatable {
    let temperature: Int
    let symbol: String
    let summary: String
}

@MainActor
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherService()
    @Published private(set) var temperature: Int?
    @Published private(set) var symbol = "cloud.fill"
    @Published private(set) var summary = ""
    @Published private(set) var city = ""
    /// Location is refused, so the Home tab can say why there is no weather.
    @Published private(set) var denied = false

    private let manager = CLLocationManager()
    /// Kept as a property: a geocoder released before it answers never calls back, and the city would never update.
    private let geocoder = CLGeocoder()
    private var timer: Timer?
    private var location: CLLocation?
    /// When the shown reading was fetched. A failed request keeps the old one, but not for longer than `staleAfter`.
    private var readAt: Date?
    private static let staleAfter: TimeInterval = 3600

    /// Read from the long-lived manager: a new manager can report a stale status.
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    /// Asks for the permission, the one place that can show the prompt.
    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
        if timer == nil { start() }
    }

    /// Safe to call at launch: it never prompts. A stale authorization status cannot stop it, since a denied request just fails quietly.
    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.location = loc
            self.fetch(loc)
            self.geocoder.reverseGeocodeLocation(loc) { marks, _ in
                let name = marks?.first?.locality ?? ""
                DispatchQueue.main.async { MainActor.assumeIsolated { self.city = name } }
            }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        let refused = (error as? CLError)?.code == .denied
        Task { @MainActor in self.denied = refused }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let status = m.authorizationStatus
        if status == .authorized || status == .authorizedAlways { m.requestLocation() }
        Task { @MainActor in self.denied = status == .denied || status == .restricted }
    }

    private func fetch(_ loc: CLLocation) {
        let fahrenheit = Locale.current.measurementSystem == .us
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(loc.coordinate.latitude)&longitude=\(loc.coordinate.longitude)&current=temperature_2m,weather_code,is_day&temperature_unit=\(fahrenheit ? "fahrenheit" : "celsius")")!
        URLSession.shared.dataTask(with: url) { data, resp, _ in
            let reading = Self.parse(data, status: (resp as? HTTPURLResponse)?.statusCode)
            DispatchQueue.main.async { MainActor.assumeIsolated { self.apply(reading) } }
        }.resume()
    }

    /// A fresh reading replaces the shown one. A failed request keeps it, but once it is over an hour old the
    /// temperature is dropped rather than shown as current.
    private func apply(_ reading: WeatherReading?) {
        if let reading {
            temperature = reading.temperature; symbol = reading.symbol; summary = reading.summary; readAt = Date()
        } else if let readAt, Date().timeIntervalSince(readAt) > Self.staleAfter {
            temperature = nil; self.readAt = nil
        }
    }

    /// The current conditions from an Open-Meteo body. Anything but HTTP 200 with those fields gives nil.
    nonisolated static func parse(_ data: Data?, status: Int?) -> WeatherReading? {
        guard status == 200, let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = obj["current"] as? [String: Any], let t = cur["temperature_2m"] as? Double,
              let code = cur["weather_code"] as? Int else { return nil }
        let day = (cur["is_day"] as? Int ?? 1) == 1
        let (sym, text) = describe(code, day: day)
        return WeatherReading(temperature: Int(t.rounded()), symbol: sym, summary: L(text))
    }

    /// WMO weather interpretation codes.
    nonisolated static func describe(_ code: Int, day: Bool) -> (String, String) {
        switch code {
        case 0: return (day ? "sun.max.fill" : "moon.stars.fill", "Clear sky")
        case 1, 2: return (day ? "cloud.sun.fill" : "cloud.moon.fill", "Partly cloudy")
        case 3: return ("cloud.fill", "Overcast")
        case 45, 48: return ("cloud.fog.fill", "Fog")
        case 51...57: return ("cloud.drizzle.fill", "Drizzle")
        case 61...67, 80...82: return ("cloud.rain.fill", "Rain")
        case 71...77, 85, 86: return ("cloud.snow.fill", "Snow")
        case 95...99: return ("cloud.bolt.rain.fill", "Thunderstorm")
        default: return ("cloud.fill", "Cloudy")
        }
    }
}
