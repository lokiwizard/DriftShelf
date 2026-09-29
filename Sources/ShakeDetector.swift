import Foundation

/// Three back-and-forth movements mean six deliberate changes of direction.
struct ShakeDetector {
    var threshold: Double = 14
    var interval: Double = 1.8
    private var previous: Double?
    private var extreme: Double = 0
    private var direction = 0
    private var turns: [Double] = []
    private var lastTime: Double = 0

    mutating func reset() {
        previous = nil
        direction = 0
        turns.removeAll()
    }

    mutating func sample(_ coordinate: Double, time: Double) -> Bool {
        if time - lastTime > interval { reset() }
        lastTime = time
        guard let previous else {
            self.previous = coordinate
            extreme = coordinate
            return false
        }
        if direction == 0 {
            if abs(coordinate - previous) >= threshold {
                direction = coordinate > previous ? 1 : -1
                extreme = coordinate
            }
            return false
        }
        if (coordinate - extreme) * Double(direction) >= 0 {
            extreme = coordinate
        } else if abs(coordinate - extreme) >= threshold {
            direction = -direction
            extreme = coordinate
            turns.append(time)
        }
        turns.removeAll { time - $0 > interval }
        if turns.count >= 6 {
            reset()
            return true
        }
        return false
    }
}
