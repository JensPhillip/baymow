// swift-tools-version:5.9
import PackageDescription

// Piper-stemmer afvikles med sherpa-onnx (Apache-2.0), der linkes statisk fra Vendor/sherpa-onnx/lib.
// Bemærk: version 1.x indeholder espeak-ng (GPL-3.0) til udtale. Se docs/TEKNISK-VURDERING.md.
let sherpaLibraries = [
    "sherpa-onnx-c-api", "sherpa-onnx-core", "sherpa-onnx-fst", "sherpa-onnx-fstfar", "sherpa-onnx-kaldifst-core",
    "kaldi-decoder-core", "kaldi-native-fbank-core", "kissfft-float", "piper_phonemize", "espeak-ng", "ucd",
    "ssentencepiece_core", "onnxruntime",
]

let package = Package(
    name: "Baymow",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CSherpaOnnx", path: "Sources/CSherpaOnnx"),
        // Al logik og UI ligger i BaymowKit, så det kan testes uden at starte appen.
        .target(
            name: "BaymowKit",
            dependencies: ["CSherpaOnnx"],
            path: "Sources/BaymowKit",
            linkerSettings: [.unsafeFlags(["-LVendor/sherpa-onnx/lib"]), .linkedLibrary("c++")]
                + sherpaLibraries.map { .linkedLibrary($0) }
        ),
        .executableTarget(name: "Baymow", dependencies: ["BaymowKit"], path: "Sources/Baymow"),
        .testTarget(name: "BaymowKitTests", dependencies: ["BaymowKit"], path: "Tests/BaymowKitTests"),
    ]
)
