import AVFoundation
import Accelerate
import SwiftUI

#if os(iOS)
    import UIKit
    import CoreGraphics
    import DynamsoftCameraEnhancer
    import DynamsoftCaptureVisionRouter
    import DynamsoftLicense
    import DynamsoftCodeParser
    import DynamsoftLabelRecognizer
    import DynamsoftDocumentNormalizer
    typealias ViewController = UIViewController
    typealias ImageType = UIImage
#elseif os(macOS)
    import Cocoa
    typealias ViewController = NSViewController
    typealias ImageType = NSImage
#endif

class CameraViewController: ViewController, AVCapturePhotoCaptureDelegate,
    AVCaptureVideoDataOutputSampleBufferDelegate
{
    var captureSession: AVCaptureSession!
    var photoOutput: AVCapturePhotoOutput!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var onImageCaptured: ((ImageType) -> Void)?
    var isCaptureEnabled = false

    #if os(iOS)
        let cvr = CaptureVisionRouter()
    #elseif os(macOS)
        let cv = CaptureVisionWrapper()
    #endif

    private var overlayView: DocumentOverlayView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Initialize the license here
        let licenseKey =
            "DLS2eyJoYW5kc2hha2VDb2RlIjoiMjAwMDAxLTE2NDk4Mjk3OTI2MzUiLCJvcmdhbml6YXRpb25JRCI6IjIwMDAwMSIsInNlc3Npb25QYXNzd29yZCI6IndTcGR6Vm05WDJrcEQ5YUoifQ=="

        #if os(iOS)
            setLicense(license: licenseKey)
        #elseif os(macOS)
            let result = CaptureVisionWrapper.initializeLicense(licenseKey)
            if result == 0 {
                print("License initialized successfully")
            } else {
                print("Failed to initialize license with error code: \(result)")
            }
        #endif

        // Initialize the overlay view
        overlayView = DocumentOverlayView()

        #if os(iOS)
            overlayView.backgroundColor = UIColor.clear
        #elseif os(macOS)
            overlayView.wantsLayer = true  // Ensure the NSView has a layer
            overlayView.layer?.backgroundColor = NSColor.clear.cgColor
        #endif

        // Add the overlay view above the preview layer
        #if os(iOS)
            overlayView.frame = view.bounds
            view.addSubview(overlayView)
        #elseif os(macOS)
            overlayView.frame = view.bounds
            view.addSubview(overlayView, positioned: .above, relativeTo: nil)
        #endif

        setupCamera()
    }

    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(for: .video) else {
            print("Unable to access the camera!")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            photoOutput = AVCapturePhotoOutput()
            let videoOutput = AVCaptureVideoDataOutput()

            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))

            if captureSession.canAddInput(input) && captureSession.canAddOutput(photoOutput) {
                captureSession.addInput(input)
                captureSession.addOutput(photoOutput)
                captureSession.addOutput(videoOutput)

                // Set up preview layer
                previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
                previewLayer.videoGravity = .resizeAspectFill
                previewLayer.frame = view.bounds  // Set frame here

                #if os(iOS)
                    view.layer.insertSublayer(previewLayer, at: 0)
                #elseif os(macOS)
                    view.layer = CALayer()
                    view.wantsLayer = true
                    view.layer?.insertSublayer(previewLayer, at: 0)
                #endif

                DispatchQueue.global(qos: .userInitiated).async {
                    self.captureSession.startRunning()
                }
            }
        } catch {
            print("Error Unable to initialize camera: \(error.localizedDescription)")
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Extract the pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Process the frame
        processCameraFrame(pixelBuffer)
    }

    func flipVertically(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

        guard let srcBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var srcBuffer = vImage_Buffer(
            data: srcBaseAddress,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: bytesPerRow
        )

        guard let dstData = malloc(bytesPerRow * height) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return nil
        }

        var dstBuffer = vImage_Buffer(
            data: dstData,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: bytesPerRow
        )

        // Perform vertical flip
        vImageVerticalReflect_ARGB8888(&srcBuffer, &dstBuffer, 0)

        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        // Create a new CVPixelBuffer for the flipped image
        var flippedPixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            nil,
            width,
            height,
            CVPixelBufferGetPixelFormatType(pixelBuffer),
            nil,
            &flippedPixelBuffer
        )

        if let flippedPixelBuffer = flippedPixelBuffer {
            CVPixelBufferLockBaseAddress(flippedPixelBuffer, .readOnly)
            memcpy(
                CVPixelBufferGetBaseAddress(flippedPixelBuffer), dstBuffer.data,
                bytesPerRow * height)
            CVPixelBufferUnlockBaseAddress(flippedPixelBuffer, .readOnly)
        }

        free(dstData)
        return flippedPixelBuffer
    }

    func processCameraFrame(_ pixelBuffer: CVPixelBuffer) {
        // Get camera preview size from pixel buffer
        let previewWidth = CVPixelBufferGetWidth(pixelBuffer)
        let previewHeight = CVPixelBufferGetHeight(pixelBuffer)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.overlayView.cameraPreviewSize = CGSize(width: previewWidth, height: previewHeight)
        }
        #if os(iOS)

            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

            let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

            //            switch pixelFormat {
            //            case kCVPixelFormatType_32ARGB:
            //                print("Pixel format: 32-bit ARGB (Alpha, Red, Green, Blue)")
            //            case kCVPixelFormatType_32BGRA:
            //                print("Pixel format: 32-bit BGRA (Blue, Green, Red, Alpha)")
            //            case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            //                print("Pixel format: 420YpCbCr8 Bi-Planar Full Range (NV12)")
            //            case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            //                print("Pixel format: 420YpCbCr8 Bi-Planar Video Range")
            //            case kCVPixelFormatType_422YpCbCr8:
            //                print("Pixel format: 422 YpCbCr8")
            //            case kCVPixelFormatType_OneComponent8:
            //                print("Pixel format: 8-bit single component grayscale")
            //            default:
            //                print("Unknown pixel format: \(pixelFormat)")
            //            }

            // Pass frame data to C++ via the wrapper
            if let baseAddress = baseAddress {
                let buffer = Data(bytes: baseAddress, count: bytesPerRow * height)
                let imageData = ImageData(
                    bytes: buffer, width: UInt(width), height: UInt(height),
                    stride: UInt(bytesPerRow), format: .ARGB8888, orientation: 0, tag: nil)
                let result = cvr.captureFromBuffer(
                    imageData, templateName: PresetTemplate.detectAndNormalizeDocument.rawValue)

                var documentArray: [[String: Any]] = []
                if let items = result.items, items.count > 0 {
                    print("Decoded document Count: \(items.count)")

                    for item in items {
                        if item.type == .normalizedImage,
                            let documentItem = item as? NormalizedImageResultItem
                        {

                            do {
                                let image = try documentItem.imageData?.toUIImage()
                                let points = documentItem.location.points

                                // Map points to a dictionary format
                                let pointArray: [[String: CGFloat]] = points.compactMap { point in
                                    guard let cgPoint = point as? CGPoint else { return nil }
                                    return ["x": cgPoint.x, "y": cgPoint.y]
                                }

                                // rotate image
                                let rotatedImage = image!.rotate(byDegrees: 90)

                                // Create dictionary for barcode data
                                let documentData: [String: Any] = [
                                    "image": rotatedImage!,
                                    "points": pointArray,
                                ]

                                // Append barcode data to array
                                documentArray.append(documentData)
                            } catch {
                                print("Failed to convert image data to UIImage: \(error)")
                            }

                        }
                    }
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.overlayView.documentData = documentArray
                    self.overlayView.setNeedsDisplay()
                    if isCaptureEnabled && documentArray.count > 0 {
                        onImageCaptured?(documentArray[0]["image"] as! ImageType)
                        isCaptureEnabled = false
                    }
                }
            }

            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        #elseif os(macOS)
            //        let image = convertPixelBufferToNSImage(pixelBuffer: pixelBuffer)

            //            let flippedPixelBuffer = flipVertically(pixelBuffer: pixelBuffer) ?? pixelBuffer
            var flippedPixelBuffer = pixelBuffer

            let image = convertPixelBufferToNSImage(pixelBuffer: flippedPixelBuffer)

            CVPixelBufferLockBaseAddress(flippedPixelBuffer, .readOnly)

            defer { CVPixelBufferUnlockBaseAddress(flippedPixelBuffer, .readOnly) }

            guard let baseAddress = CVPixelBufferGetBaseAddress(flippedPixelBuffer) else {
                print("Failed to get base address of pixel buffer.")
                return
            }
            let width = CVPixelBufferGetWidth(flippedPixelBuffer)
            let height = CVPixelBufferGetHeight(flippedPixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(flippedPixelBuffer)
            let pixelFormat = CVPixelBufferGetPixelFormatType(flippedPixelBuffer)

            // Pass frame data to C++ via the wrapper

            var buffer = Data(bytes: baseAddress, count: bytesPerRow * height)
            buffer = flipBufferVertically(
                buffer: buffer, width: width, height: height, bytesPerRow: bytesPerRow)
            let documentArray =
                cv.captureImage(
                    with: buffer, width: Int32(width), height: Int32(height),
                    stride: Int32(bytesPerRow), pixelFormat: pixelFormat)
                as? [[String: Any]] ?? []

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.overlayView.documentData = documentArray
                self.overlayView.setNeedsDisplay(self.overlayView.bounds)  // macOS
                if isCaptureEnabled && documentArray.count > 0 {
                    onImageCaptured?(documentArray[0]["image"] as! ImageType)
                    isCaptureEnabled = false
                }
            }

        #endif
    }

    #if os(iOS)

        // Helper function to convert CVPixelBuffer to UIImage
        func imageFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> ImageType {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()

            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                fatalError("Failed to create CGImage from pixel buffer.")
            }

            // Convert the CGImage to UIImage
            let orientation: UIImage.Orientation
            switch UIDevice.current.orientation {
            case .portrait: orientation = .right
            case .portraitUpsideDown: orientation = .left
            case .landscapeLeft: orientation = .up
            case .landscapeRight: orientation = .down
            default: orientation = .up
            }

            return ImageType(cgImage: cgImage, scale: 1.0, orientation: orientation)
        }

        func transformPoints(
            for points: [CGPoint], imageWidth: CGFloat, imageHeight: CGFloat, rotation: CGFloat
        ) -> [CGPoint] {
            return points.map { point in
                switch rotation {
                case 90:  // Clockwise 90 degrees
                    return CGPoint(x: imageHeight - point.y, y: point.x)
                case -90:  // Counterclockwise 90 degrees
                    return CGPoint(x: point.y, y: imageWidth - point.x)
                case 180:  // 180 degrees
                    return CGPoint(x: imageWidth - point.x, y: imageHeight - point.y)
                default:  // No rotation
                    return point
                }
            }
        }
    #elseif os(macOS)
        func flipBufferVertically(buffer: Data, width: Int, height: Int, bytesPerRow: Int) -> Data {
            var flippedBuffer = Data(capacity: buffer.count)

            for row in 0..<height {
                // Calculate the range of the current row in the buffer
                let start = (height - row - 1) * bytesPerRow
                let end = start + bytesPerRow

                // Append the row from the original buffer to the flipped buffer
                flippedBuffer.append(buffer[start..<end])
            }

            return flippedBuffer
        }

        func convertPixelBufferToNSImage(pixelBuffer: CVPixelBuffer) -> NSImage? {
            // Step 1: Create a CIImage from the CVPixelBuffer
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            // Step 2: Create a CIContext to render the CIImage
            let ciContext = CIContext(options: nil)

            // Step 3: Get the pixel buffer properties
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)

            // Step 4: Create a CGImage from the CIImage
            guard
                let cgImage = ciContext.createCGImage(
                    ciImage, from: CGRect(x: 0, y: 0, width: width, height: height))
            else {
                print("Failed to create CGImage from CIImage.")
                return nil
            }

            // Step 5: Create an NSImage from the CGImage
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))

            return nsImage
        }

    #endif

    func capturePhoto() {
        //        let settings = AVCapturePhotoSettings()
        //        #if os(iOS)
        //            settings.flashMode = .auto
        //        #endif
        //        photoOutput.capturePhoto(with: settings, delegate: self)
        isCaptureEnabled = true
    }

    // MARK: AVCapturePhotoCaptureDelegate
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            print("Error capturing photo: \(error)")
            return
        }

        guard let data = photo.fileDataRepresentation(),
            let image = ImageType(data: data)
        else {
            return
        }

        onImageCaptured?(image)
    }

    // Handle view resizing
    #if os(iOS)
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            if previewLayer != nil {
                previewLayer.frame = view.bounds
            }

            if overlayView != nil {
                overlayView.frame = view.bounds
            }
        }
    #elseif os(macOS)
        override func viewDidLayout() {
            super.viewDidLayout()
            if previewLayer != nil {
                previewLayer.frame = view.bounds
            }

            if overlayView != nil {
                overlayView.frame = view.bounds
            }
        }
    #endif
}

#if os(iOS)
    extension CameraViewController: LicenseVerificationListener {

        func onLicenseVerified(_ isSuccess: Bool, error: Error?) {
            if !isSuccess {
                if let error = error {
                    print("\(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.displayLicenseMessage(
                            message: "License initialization failed：" + error.localizedDescription)
                    }
                }
            }
        }

        func setLicense(license: String) {
            LicenseManager.initLicense(license, verificationDelegate: self)
        }

        func displayLicenseMessage(message: String) {
            let label = UILabel()
            label.text = message
            label.textAlignment = .center
            label.numberOfLines = 0
            label.textColor = .red
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.bottomAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
                label.leadingAnchor.constraint(
                    greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(
                    lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            ])
        }
    }

    extension UIImage {
        func rotate(byDegrees degrees: CGFloat) -> UIImage? {
            // Calculate the size of the rotated view's bounding box
            let radians = degrees * .pi / 180
            var newSize = CGRect(
                origin: .zero,
                size: self.size
            ).applying(CGAffineTransform(rotationAngle: radians)).size

            // Normalize size
            newSize.width = floor(newSize.width)
            newSize.height = floor(newSize.height)

            // Create a new graphics context
            UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
            guard let context = UIGraphicsGetCurrentContext() else { return nil }

            // Move origin to the middle of the image so the rotation will happen around the center
            context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            // Rotate the context
            context.rotate(by: radians)

            // Draw the image in the context
            self.draw(
                in: CGRect(
                    x: -self.size.width / 2,
                    y: -self.size.height / 2,
                    width: self.size.width,
                    height: self.size.height
                )
            )

            // Capture the rotated image
            let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            return rotatedImage
        }
    }
#endif
