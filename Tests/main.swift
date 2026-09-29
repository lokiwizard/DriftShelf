import Foundation

func detect(_ points: [Double], step: Double = 0.1) -> Bool {
    var detector = ShakeDetector()
    return points.enumerated().reduce(false) { result, point in
        detector.sample(point.element, time: Double(point.offset) * step) || result
    }
}
precondition(detect([0, 30, -30, 30, -30, 30, -30, 30]))
precondition(!detect([0, 30, -30, 30, -30, 30, -30]))
precondition(!detect(Array(stride(from: 0.0, through: 300, by: 10))))
precondition(!detect([0, 3, -3, 4, -4, 3, -3, 4, -4]))
precondition(!detect([0, 30, -30, 30, -30, 30, -30, 30], step: 1))
var resetDetector = ShakeDetector()
_ = resetDetector.sample(0, time: 0)
_ = resetDetector.sample(40, time: 0.1)
resetDetector.reset()
precondition(!resetDetector.sample(-40, time: 0.2))
print("PASS: three shakes, insufficient shakes, straight drag, jitter, timeout, reset")
