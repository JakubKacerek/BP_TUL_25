package com.example.new_camera_app

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc

class MainActivity : FlutterActivity() {
    private val CHANNEL = "opencv/preprocessing"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterPlugin.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "preprocessImage") {
                val imageBytes = call.argument<ByteArray>("image")
                if (imageBytes != null) {
                    try {
                        // Inicializace OpenCV
                        if (!OpenCVLoader.initDebug()) {
                            result.error("OPENCV_INIT", "Failed to initialize OpenCV", null)
                            return@setMethodCallHandler
                        }

                        // Převod YUV dat na Mat (předpokládáme YUV420SP/NV21 formát)
                        val width = call.argument<Int>("width") ?: 0
                        val height = call.argument<Int>("height") ?: 0
                        if (width == 0 || height == 0) {
                            result.error("INVALID_DIMENSIONS", "Width or height not provided", null)
                            return@setMethodCallHandler
                        }

                        val yuvMat = Mat(height + height / 2, width, CvType.CV_8UC1)
                        yuvMat.put(0, 0, imageBytes)

                        // Převod YUV na šedotón
                        val grayMat = Mat()
                        Imgproc.cvtColor(yuvMat, grayMat, Imgproc.COLOR_YUV2GRAY_NV21)

                        // Aplikace Gaussian blur
                        Imgproc.GaussianBlur(grayMat, grayMat, Size(5.0, 5.0), 0.0)

                        // Převod zpět na YUV420SP (NV21)
                        val processedYuvMat = Mat()
                        Imgproc.cvtColor(grayMat, processedYuvMat, Imgproc.COLOR_GRAY2YUV)

                        // Extrakce bajtů
                        val processedBytes = ByteArray((processedYuvMat.total() * processedYuvMat.channels()).toInt())
                        processedYuvMat.get(0, 0, processedBytes)

                        result.success(processedBytes)
                    } catch (e: Exception) {
                        result.error("OPENCV_ERROR", e.message, null)
                    }
                } else {
                    result.error("INVALID_IMAGE", "No image data provided", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}