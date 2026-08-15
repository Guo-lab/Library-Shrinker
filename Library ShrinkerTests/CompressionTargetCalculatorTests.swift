import XCTest
@testable import Library_Shrinker

final class CompressionTargetCalculatorTests: XCTestCase {
    func testRatioTargetUsesOriginalFileSize() {
        XCTAssertEqual(
            CompressionTargetCalculator.targetByteSize(
                originalByteSize: 1_000_000_000,
                ratio: 0.35
            ),
            350_000_000
        )
    }

    func testBitrateTargetConvertsBitsToBytesUsingDuration() {
        XCTAssertEqual(
            CompressionTargetCalculator.targetByteSize(
                megabitsPerSecond: 5,
                duration: 60
            ),
            37_500_000
        )
    }

    func testInvalidBitrateInputsProduceNoTarget() {
        XCTAssertEqual(
            CompressionTargetCalculator.targetByteSize(megabitsPerSecond: 0, duration: 60),
            0
        )
        XCTAssertEqual(
            CompressionTargetCalculator.targetByteSize(megabitsPerSecond: 5, duration: 0),
            0
        )
    }

    func testRatioQuantizationIsFinerAtLowValues() {
        XCTAssertEqual(CompressionTargetCalculator.quantizedRatio(0.334), 0.33)
        XCTAssertEqual(CompressionTargetCalculator.quantizedRatio(0.634), 0.65)
        XCTAssertEqual(CompressionTargetCalculator.quantizedRatio(0.864), 0.9)
    }

    func testLogarithmicSliderEndpoints() {
        XCTAssertEqual(CompressionTargetCalculator.ratio(forSliderPosition: 0), 0.01)
        XCTAssertEqual(CompressionTargetCalculator.ratio(forSliderPosition: 1), 1)
    }

    func testStorageEstimateIncludesOutputsLargestTemporaryCopyAndReserve() {
        XCTAssertEqual(
            CompressionTargetCalculator.requiredStorage(
                for: [100_000_000, 200_000_000],
                safetyReserve: 50_000_000
            ),
            550_000_000
        )
    }

    func testRecommendedMinimumBitrateAccountsForResolutionAndCodec() {
        XCTAssertEqual(
            CompressionTargetCalculator.recommendedMinimumMegabitsPerSecond(
                pixelWidth: 3_840,
                pixelHeight: 2_160,
                usesHEVC: false
            ),
            20
        )
        XCTAssertEqual(
            CompressionTargetCalculator.recommendedMinimumMegabitsPerSecond(
                pixelWidth: 3_840,
                pixelHeight: 2_160,
                usesHEVC: true
            ),
            12
        )
    }

    func testBitrateFiltersUseNonOverlappingBoundaries() {
        XCTAssertTrue(VideoBitRateFilter.below1Point5.contains(bitsPerSecond: 1_499_999))
        XCTAssertTrue(VideoBitRateFilter.onePoint5To2.contains(bitsPerSecond: 1_500_000))
        XCTAssertFalse(VideoBitRateFilter.onePoint5To2.contains(bitsPerSecond: 2_000_000))
        XCTAssertTrue(VideoBitRateFilter.twoTo2Point5.contains(bitsPerSecond: 2_000_000))
        XCTAssertTrue(VideoBitRateFilter.twoPoint5To5.contains(bitsPerSecond: 2_500_000))
        XCTAssertTrue(VideoBitRateFilter.twentyAndAbove.contains(bitsPerSecond: 20_000_000))
    }
}
