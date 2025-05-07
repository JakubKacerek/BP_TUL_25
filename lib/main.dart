import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

late List<CameraDescription> cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  cameras = await availableCameras();
  debugPrint('Available cameras: ${cameras.length}');
  final prefs = await SharedPreferences.getInstance();
  final themeMode = prefs.getString('themeMode') ?? 'light';
  final language = prefs.getString('language') ?? 'en';
  runApp(MyApp(
    camera: cameras.length > 1 ? cameras[1] : cameras.first,
    initialThemeMode: themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light,
    language: language,
  ));
}

class MyApp extends StatefulWidget {
  final CameraDescription camera;
  final ThemeMode initialThemeMode;
  final String language;

  const MyApp({
    Key? key,
    required this.camera,
    required this.initialThemeMode,
    required this.language,
  }) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
  }

  void updateTheme(ThemeMode newTheme) {
    setState(() {
      _themeMode = newTheme;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.light().copyWith(
        primaryColor: Colors.teal,
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.tealAccent,
          foregroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: Colors.teal,
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.tealAccent,
          foregroundColor: Colors.white,
        ),
      ),
      themeMode: _themeMode,
      home: CameraScreen(
        camera: widget.camera,
        language: widget.language,
        onThemeChanged: updateTheme,
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;
  final String language;
  final Function(ThemeMode) onThemeChanged;

  const CameraScreen({
    Key? key,
    required this.camera,
    required this.language,
    required this.onThemeChanged,
  }) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  late FaceDetector _faceDetector;
  late TextRecognizer _textRecognizer;
  bool _isDetecting = false;
  bool _faceDetectionEnabled = true;
  bool _faceRecognitionEnabled = false;
  bool _ocrEnabled = false;
  List<Face> _faces = [];
  Map<int, String> _faceNames = {};
  Map<int, double> _faceConfidences = {};
  Map<int, List<double>> _unrecognizedFeatures = {};
  String _detectionStatus = 'No faces detected';
  String _recognizedText = '';
  late CameraDescription _currentCamera;
  List<Map<String, dynamic>> _faceDatabase = [];
  late File _faceDatabaseFile;
  late String _language;

  final Map<String, Map<String, String>> _translations = {
    'en': {
      'app_title': 'Face Detection & Recognition',
      'unrecognized_face': 'Unrecognized Face',
      'select_or_enter': 'Select an existing name or enter a new one:',
      'no_faces_yet': 'No known faces yet',
      'new_name': 'New name',
      'cancel': 'Cancel',
      'save': 'Save',
      'clear_database': 'Clear Database',
      'clear_confirm': 'Are you sure you want to delete all learned faces? This action cannot be undone.',
      'controls': 'Controls',
      'settings': 'Settings',
      'switch_camera': 'Switch Camera',
      'toggle_detection': 'Toggle Detection',
      'toggle_recognition': 'Toggle Recognition',
      'toggle_ocr': 'Toggle OCR',
      'clear_db': 'Clear Database',
      'close': 'Close',
      'no_faces_detected': 'No faces detected',
      'detected_faces': 'Detected %d faces',
      'detection_disabled': 'Detection disabled',
      'ocr_enabled': 'OCR enabled',
      'no_text_detected': 'No text detected',
      'perm_denied': 'Camera permission denied',
      'perm_denied_perm': 'Camera permission permanently denied. Please enable in settings.',
      'open_settings': 'Open Settings',
      'theme': 'Theme',
      'light': 'Light',
      'dark': 'Dark',
      'language': 'Language',
      'english': 'English',
      'czech': 'Czech',
      'learned_faces': 'Learned Faces',
      'no_faces_learned': 'No faces learned',
      'database_cleared': 'Face database cleared',
    },
    'cs': {
      'app_title': 'Detekce a rozpoznávání obličejů',
      'unrecognized_face': 'Nerozpoznaný obličej',
      'select_or_enter': 'Vyberte existující jméno nebo zadejte nové:',
      'no_faces_yet': 'Zatím žádné známé obličeje',
      'new_name': 'Nové jméno',
      'cancel': 'Zrušit',
      'save': 'Uložit',
      'clear_database': 'Vymazat databázi',
      'clear_confirm': 'Opravdu chcete smazat všechny naučené obličeje? Tuto akci nelze vrátit zpět.',
      'controls': 'Ovládání',
      'settings': 'Nastavení',
      'switch_camera': 'Přepnout kameru',
      'toggle_detection': 'Přepnout detekci',
      'toggle_recognition': 'Přepnout rozpoznávání',
      'toggle_ocr': 'Přepnout OCR',
      'clear_db': 'Vymazat databázi',
      'close': 'Zavřít',
      'no_faces_detected': 'Žádné obličeje nebyly detekovány',
      'detected_faces': 'Detekováno %d obličejů',
      'detection_disabled': 'Detekce vypnuta',
      'ocr_enabled': 'OCR zapnuto',
      'no_text_detected': 'Žádný text nebyl detekován',
      'perm_denied': 'Přístup ke kameře zamítnut',
      'perm_denied_perm': 'Přístup ke kameře trvale zamítnut. Povolte v nastavení.',
      'open_settings': 'Otevřít nastavení',
      'theme': 'Motiv',
      'light': 'Světlý',
      'dark': 'Tmavý',
      'language': 'Jazyk',
      'english': 'Angličtina',
      'czech': 'Čeština',
      'learned_faces': 'Naučené obličeje',
      'no_faces_learned': 'Žádné naučené obličeje',
      'database_cleared': 'Databáze obličejů vymazána',
    },
  };

  @override
  void initState() {
    super.initState();
    _currentCamera = widget.camera;
    _language = widget.language;
    _initializeCamera();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableContours: false,
        enableLandmarks: false,
        enableTracking: true,
      ),
    );
    _textRecognizer = TextRecognizer();
    _loadFaceDatabase();
  }

  Future<void> _loadFaceDatabase() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _faceDatabaseFile = File('${directory.path}/faces.json');
      if (await _faceDatabaseFile.exists()) {
        final jsonString = await _faceDatabaseFile.readAsString();
        _faceDatabase = List<Map<String, dynamic>>.from(jsonDecode(jsonString));
        debugPrint('Loaded face database: ${_faceDatabase.length} entries');
      } else {
        _faceDatabase = [];
        debugPrint('No face database found, starting empty');
      }
    } catch (e) {
      debugPrint('Error loading face database: $e');
      _faceDatabase = [];
      setState(() {
        _detectionStatus = _t('Error loading database: $e');
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveFaceDatabase() async {
    try {
      await _faceDatabaseFile.writeAsString(jsonEncode(_faceDatabase));
      debugPrint('Saved face database: ${_faceDatabase.length} entries');
    } catch (e) {
      debugPrint('Error saving face database: $e');
      setState(() {
        _detectionStatus = _t('Error saving database: $e');
      });
    }
  }

  void _initializeCamera() {
    _controller = CameraController(
      _currentCamera,
      ResolutionPreset.medium,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    _initializeControllerFuture = _requestPermissions().then((granted) {
      if (granted) {
        return _controller.initialize().then((_) {
          debugPrint(
              'Camera stream started, lensDirection: ${_currentCamera.lensDirection}, '
              'sensorOrientation: ${_controller.description.sensorOrientation}');
          _controller.startImageStream(_processCameraImage);
        });
      } else {
        debugPrint('Permissions denied');
        return Future.error('Permissions denied');
      }
    });
  }

  Future<bool> _requestPermissions() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      debugPrint('Camera permission denied');
      if (status.isPermanentlyDenied) {
        debugPrint('Camera permission permanently denied');
        setState(() {
          _detectionStatus = _t('perm_denied_perm');
        });
      } else {
        setState(() {
          _detectionStatus = _t('perm_denied');
        });
      }
      return false;
    }
    debugPrint('Camera permission granted');
    return true;
  }

  @override
  void dispose() {
    _controller.dispose();
    _faceDetector.close();
    _textRecognizer.close();
    super.dispose();
  }

  String _t(String key, [Map<String, dynamic>? params]) {
    String text = _translations[_language]![key] ?? key;
    if (params != null) {
      params.forEach((k, v) {
        text = text.replaceAll('%$k', v.toString());
      });
    }
    return text;
  }

  Uint8List _convertCameraImageToBytes(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final ySize = width * height;
    final uvSize = (width ~/ 2) * (height ~/ 2) * 2;
    final nv21 = Uint8List(ySize + uvSize);

    for (int y = 0; y < height; y++) {
      final rowOffset = y * yPlane.bytesPerRow;
      for (int x = 0; x < width; x++) {
        nv21[y * width + x] = yPlane.bytes[rowOffset + x];
      }
    }

    final uvOffset = ySize;
    for (int y = 0; y < height ~/ 2; y++) {
      final uvRowOffset = y * uPlane.bytesPerRow;
      for (int x = 0; x < width ~/ 2; x++) {
        final uvIndex = uvOffset + (y * width + x * 2);
        nv21[uvIndex] = vPlane.bytes[uvRowOffset + x];
        nv21[uvIndex + 1] = uPlane.bytes[uvRowOffset + x];
      }
    }

    debugPrint(
        'Converted to NV21: totalBytes=${nv21.length}, ySize=$ySize, uvSize=$uvSize, '
        'width=$width, height=$height, yBytesPerRow=${yPlane.bytesPerRow}, '
        'uvBytesPerRow=${uPlane.bytesPerRow}');
    return nv21;
  }

  Future<void> _saveRawImage(Uint8List bytes, String prefix) async {
    try {
      final directory = await getExternalStorageDirectory();
      final path =
          '${directory!.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.bin';
      final file = File(path);
      await file.writeAsBytes(bytes);
      debugPrint('Saved raw image: $path');
    } catch (e) {
      debugPrint('Error saving raw image: $e');
      try {
        final directory = await getTemporaryDirectory();
        final path =
            '${directory.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.bin';
        final file = File(path);
        await file.writeAsBytes(bytes);
        debugPrint('Saved raw image to fallback: $path');
      } catch (fallbackError) {
        debugPrint('Error saving raw image to fallback: $fallbackError');
      }
    }
  }

  List<double> _extractFaceFeatures(Face face) {
    final box = face.boundingBox;
    final centerX = box.left + box.width / 2;
    final centerY = box.top + box.height / 2;
    debugPrint('Extracted features: centerX=$centerX, centerY=$centerY, width=${box.width}, height=${box.height}');
    return [centerX, centerY, box.width.toDouble(), box.height.toDouble()];
  }

  double _computeFeatureDistance(List<double> f1, List<double> f2) {
    double sum = 0;
    for (int i = 0; i < f1.length; i++) {
      sum += (f1[i] - f2[i]) * (f1[i] - f2[i]);
    }
    return math.sqrt(sum);
  }

Future<Map<String, dynamic>?> _recognizeFace(Face face) async {
  if (!_faceRecognitionEnabled || face.trackingId == null) return null;

  final features = _extractFaceFeatures(face);
  const threshold = 80.0;
  const minConfidence = 40.0; 

  for (var storedFace in _faceDatabase) {
    final storedFeaturesList = List<List<double>>.from(
      storedFace['features'].map((f) => List<double>.from(f)),
    );
    double minDistance = double.infinity;
    for (var storedFeatures in storedFeaturesList) {
      final distance = _computeFeatureDistance(features, storedFeatures);
      debugPrint('Face ${face.trackingId}: Distance to ${storedFace['name']}: $distance');
      minDistance = math.min(minDistance, distance);
    }
    if (minDistance < threshold) {
      double confidence = (100 - (minDistance / threshold) * 100).clamp(0, 100);
      if (confidence >= minConfidence) { 
        return {'name': storedFace['name'], 'features': features, 'confidence': confidence};
      }
    }
  }

  return {'name': null, 'features': features};
}

  Future<String?> _promptForName(BuildContext context, List<double> features, int trackingId) async {
    final controller = TextEditingController();
    String? selectedName;
    String? result;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_t('unrecognized_face')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_t('select_or_enter')),
                if (_faceDatabase.isNotEmpty)
                  DropdownButton<String>(
                    hint: Text(_t('no_faces_yet')),
                    value: selectedName,
                    isExpanded: true,
                    items: _faceDatabase.map((faceEntry) {
                      return DropdownMenuItem<String>(
                        value: faceEntry['name'],
                        child: Text(faceEntry['name']),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedName = value;
                        controller.text = value ?? '';
                      });
                    },
                  )
                else
                  Text(_t('no_faces_yet')),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(hintText: _t('new_name')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_t('cancel')),
            ),
            TextButton(
              onPressed: () {
                result = controller.text.trim();
                if (result?.isEmpty ?? true) return;
                Navigator.pop(dialogContext);
              },
              child: Text(_t('save')),
            ),
          ],
        ),
      ),
    );

    debugPrint('Prompt result: $result');
    if (result?.isNotEmpty ?? false) {
      final existingFaceIndex = _faceDatabase.indexWhere((f) => f['name'] == result);
      if (existingFaceIndex >= 0) {
        _faceDatabase[existingFaceIndex]['features'].add(features);
        debugPrint('Appended features for $result: $features');
      } else {
        _faceDatabase.add({'name': result!, 'features': [features]});
        debugPrint('Added new face: $result with features: $features');
      }
      await _saveFaceDatabase();
      debugPrint('Face database after save: $_faceDatabase');
      if (mounted) {
        setState(() {
          _faceNames[trackingId] = result!;
          _unrecognizedFeatures.remove(trackingId);
        });
      }
    }
    return result;
  }

  Future<void> _clearFaceDatabase() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('clear_database')),
        content: Text(_t('clear_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('clear_db')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (mounted) {
        setState(() {
          _faceDatabase.clear();
          _faceNames.clear();
          _faceConfidences.clear();
          _unrecognizedFeatures.clear();
          _detectionStatus = _t('database_cleared');
        });
      }
      await _saveFaceDatabase();
      debugPrint('Cleared face database');
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting || (!_faceDetectionEnabled && !_ocrEnabled)) return;
    _isDetecting = true;

    try {
      debugPrint(
          'Processing image: width=${image.width}, height=${image.height}, planes=${image.planes.length}');
      for (var i = 0; i < image.planes.length; i++) {
        debugPrint(
            'Plane $i: bytesPerRow=${image.planes[i].bytesPerRow}, bytesLength=${image.planes[i].bytes.length}');
      }

      final bytes = _convertCameraImageToBytes(image);
      await _saveRawImage(bytes, 'nv21');

      final sensorOrientation = _controller.description.sensorOrientation;
      final isFrontCamera = _currentCamera.lensDirection == CameraLensDirection.front;
      int rotationDegrees = sensorOrientation;
      if (isFrontCamera) {
        rotationDegrees = (sensorOrientation) % 360;
      }

      InputImageRotation rotation;
      switch (rotationDegrees) {
        case 0:
          rotation = InputImageRotation.rotation0deg;
          break;
        case 90:
          rotation = InputImageRotation.rotation90deg;
          break;
        case 180:
          rotation = InputImageRotation.rotation180deg;
          break;
        case 270:
          rotation = InputImageRotation.rotation270deg;
          break;
        default:
          rotation = InputImageRotation.rotation0deg;
          debugPrint('Unexpected sensorOrientation: $sensorOrientation');
      }

      debugPrint(
          'Using rotation: $rotation, sensorOrientation: $sensorOrientation, '
          'isFrontCamera: $isFrontCamera');

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      debugPrint(
          'InputImageMetadata: size=${inputImage.metadata!.size}, '
          'rotation=${inputImage.metadata!.rotation}, '
          'format=${inputImage.metadata!.format}, '
          'bytesPerRow=${inputImage.metadata!.bytesPerRow}');

      if (_ocrEnabled) {
        final recognizedText = await _textRecognizer.processImage(inputImage);
        debugPrint('Recognized text: ${recognizedText.text}');
        if (mounted) {
          setState(() {
            _recognizedText = recognizedText.text.isNotEmpty ? recognizedText.text : _t('no_text_detected');
            _detectionStatus = _t('ocr_enabled');
            _faces = [];
            _faceNames = {};
            _faceConfidences = {};
            _unrecognizedFeatures = {};
          });
        }
      } else if (_faceDetectionEnabled) {
        final faces = await _faceDetector.processImage(inputImage);
        debugPrint('Detected ${faces.length} faces with NV21');

        Map<int, String> newFaceNames = {};
        Map<int, double> newFaceConfidences = {};
        Map<int, List<double>> newUnrecognizedFeatures = {};
        for (var face in faces) {
          if (_faceRecognitionEnabled && face.trackingId != null) {
            final result = await _recognizeFace(face);
            if (result != null) {
              if (result['name'] != null) {
                newFaceNames[face.trackingId!] = result['name'];
                newFaceConfidences[face.trackingId!] = result['confidence'];
              } else {
                newUnrecognizedFeatures[face.trackingId!] = result['features'];
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _detectionStatus = faces.isNotEmpty
                ? _t('detected_faces', {'d': faces.length})
                : _t('no_faces_detected');
            _faces = faces;
            _faceNames = newFaceNames;
            _faceConfidences = newFaceConfidences;
            _unrecognizedFeatures = newUnrecognizedFeatures;
            _recognizedText = '';
          });
        }
      }
    } catch (e) {
      debugPrint('Error in processing: $e');
      if (mounted) {
        setState(() {
          _detectionStatus = 'Error: $e';
        });
      }
    } finally {
      _isDetecting = false;
    }
  }

  void _toggleFaceDetection() {
    setState(() {
      if (_ocrEnabled) {
        _ocrEnabled = false;
        _recognizedText = '';
      }
      _faceDetectionEnabled = !_faceDetectionEnabled;
      _faces = [];
      _faceNames = {};
      _faceConfidences = {};
      _unrecognizedFeatures = {};
      _detectionStatus = _faceDetectionEnabled ? _t('no_faces_detected') : _t('detection_disabled');
      debugPrint('Face detection enabled: $_faceDetectionEnabled');
    });
  }

  void _toggleFaceRecognition() {
    setState(() {
      if (_ocrEnabled) {
        _ocrEnabled = false;
        _recognizedText = '';
      }
      _faceRecognitionEnabled = !_faceRecognitionEnabled;
      _faceNames = {};
      _faceConfidences = {};
      _unrecognizedFeatures = {};
      debugPrint('Face recognition enabled: $_faceRecognitionEnabled');
      if (!_faceRecognitionEnabled) {
        _detectionStatus = _faceDetectionEnabled ? _t('no_faces_detected') : _t('detection_disabled');
      }
    });
  }

  void _toggleOCR() {
    setState(() {
      _ocrEnabled = !_ocrEnabled;
      if (_ocrEnabled) {
        _faceDetectionEnabled = false;
        _faceRecognitionEnabled = false;
        _faces = [];
        _faceNames = {};
        _faceConfidences = {};
        _unrecognizedFeatures = {};
        _detectionStatus = _t('ocr_enabled');
        _recognizedText = _t('no_text_detected');
      } else {
        _faceDetectionEnabled = true;
        _detectionStatus = _t('no_faces_detected');
        _recognizedText = '';
      }
      debugPrint('OCR enabled: $_ocrEnabled');
    });
  }

  void _switchCamera() async {
    await _controller.stopImageStream();
    await _controller.dispose();
    setState(() {
      _currentCamera = _currentCamera == cameras.first
          ? (cameras.length > 1 ? cameras[1] : cameras.first)
          : cameras.first;
      _detectionStatus = _ocrEnabled ? _t('ocr_enabled') : _t('no_faces_detected');
      _faces = [];
      _faceNames = {};
      _faceConfidences = {};
      _unrecognizedFeatures = {};
      _recognizedText = _ocrEnabled ? _t('no_text_detected') : '';
    });
    _initializeCamera();
  }

  void _openAppSettings() async {
    await openAppSettings();
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final newTheme = Theme.of(context).brightness == Brightness.light ? ThemeMode.dark : ThemeMode.light;
    await prefs.setString('themeMode', newTheme == ThemeMode.dark ? 'dark' : 'light');
    widget.onThemeChanged(newTheme);
  }

  Future<void> _saveLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', _language);
  }

  void _showControlMenu() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('controls')),
        content: Container(
          width: 300,
          height: 200,
          child: GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.7,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.3),
                          blurRadius: 5,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.visibility, color: Colors.white),
                      color: _faceDetectionEnabled ? Colors.blue : Colors.grey,
                      onPressed: () {
                        Navigator.pop(context);
                        _toggleFaceDetection();
                      },
                    ),
                  ),
                  Flexible(
                    child: Text(
                      _t('toggle_detection'),
                      style: const TextStyle(fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.purple.withOpacity(0.3),
                          blurRadius: 5,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.person, color: Colors.white),
                      color: _faceRecognitionEnabled ? Colors.purple : Colors.grey,
                      onPressed: () {
                        Navigator.pop(context);
                        _toggleFaceRecognition();
                      },
                    ),
                  ),
                  Flexible(
                    child: Text(
                      _t('toggle_recognition'),
                      style: const TextStyle(fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 5,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.text_fields, color: Colors.white),
                      color: _ocrEnabled ? Colors.green : Colors.grey,
                      onPressed: () {
                        Navigator.pop(context);
                        _toggleOCR();
                      },
                    ),
                  ),
                  Flexible(
                    child: Text(
                      _t('toggle_ocr'),
                      style: const TextStyle(fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.3),
                          blurRadius: 5,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.settings, color: Colors.white),
                      color: Colors.orange,
                      onPressed: () {
                        Navigator.pop(context);
                        _showSettingsDialog();
                      },
                    ),
                  ),
                  Flexible(
                    child: Text(
                      _t('settings'),
                      style: const TextStyle(fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('close')),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    debugPrint('Settings dialog face database: ${_faceDatabase.map((e) => e['name']).toList()}');
    try {
      debugPrint('Opening settings dialog');
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('settings')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.switch_camera, color: Colors.green),
                  title: Text(_t('switch_camera'), style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    _switchCamera();
                  },
                ),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: Text(_t('clear_db'), style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    _clearFaceDatabase();
                  },
                ),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.brightness_6),
                  title: Text(_t('theme'), style: const TextStyle(fontSize: 12)),
                  trailing: Switch(
                    value: Theme.of(context).brightness == Brightness.dark,
                    onChanged: (value) {
                      _toggleTheme();
                    },
                  ),
                ),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.language),
                  title: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 100),
                    child: Text(_t('language'), style: const TextStyle(fontSize: 12)),
                  ),
                  trailing: DropdownButton<String>(
                    value: _language,
                    items: [
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(_t('english')),
                      ),
                      DropdownMenuItem(
                        value: 'cs',
                        child: Text(_t('czech')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _language = value;
                          _saveLanguage();
                        });
                      }
                    },
                  ),
                ),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.face),
                  title: Text(_t('learned_faces'), style: const TextStyle(fontSize: 12)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: StatefulBuilder(
                      builder: (context, setDropdownState) => Container(
                        constraints: BoxConstraints(maxHeight: 100),
                        child: _faceDatabase.isEmpty
                            ? Text(_t('no_faces_learned'))
                            : SingleChildScrollView(
                                child: Column(
                                  children: _faceDatabase
                                      .asMap()
                                      .entries
                                      .map((entry) => Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                                            child: Text(entry.value['name']),
                                          ))
                                      .toList(),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t('close')),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Settings dialog error: $e');
    }
  }

  void _handleFaceTap(Face face) async {
    if (face.trackingId != null && _unrecognizedFeatures.containsKey(face.trackingId)) {
      debugPrint('Tapped unrecognized face ${face.trackingId}');
      await _controller.stopImageStream();
      try {
        await _promptForName(context, _unrecognizedFeatures[face.trackingId]!, face.trackingId!);
      } finally {
        if (mounted) {
          await _controller.startImageStream(_processCameraImage);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('app_title'))),
      body: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Error: ${snapshot.error}'),
                        if (_detectionStatus.contains('permanently denied'))
                          ElevatedButton(
                            onPressed: _openAppSettings,
                            child: Text(_t('open_settings')),
                          ),
                      ],
                    ),
                  );
                }
                return CameraPreview(_controller);
              } else {
                return const Center(child: CircularProgressIndicator());
              }
            },
          ),
          if (_faceDetectionEnabled)
            FaceOverlay(
              faces: _faces,
              faceNames: _faceNames,
              faceConfidences: _faceConfidences,
              unrecognizedFeatures: _unrecognizedFeatures,
              onFaceTap: _handleFaceTap,
            ),
          if (_ocrEnabled)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    _recognizedText,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black54,
              child: Text(
                _detectionStatus,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.tealAccent,
        onPressed: _showControlMenu,
        heroTag: 'control_menu',
        child: const Icon(Icons.menu, color: Colors.white),
      ),
    );
  }
}

class FaceOverlay extends StatelessWidget {
  final List<Face> faces;
  final Map<int, String> faceNames;
  final Map<int, double> faceConfidences;
  final Map<int, List<double>> unrecognizedFeatures;
  final Function(Face) onFaceTap;

  const FaceOverlay({
    Key? key,
    required this.faces,
    required this.faceNames,
    required this.faceConfidences,
    required this.unrecognizedFeatures,
    required this.onFaceTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: FacePainter(faces, faceNames, faceConfidences, unrecognizedFeatures),
      child: GestureDetector(
        onTapUp: (details) {
          for (var face in faces) {
            if (face.trackingId != null &&
                unrecognizedFeatures.containsKey(face.trackingId)) {
              final box = face.boundingBox;
              if (box.contains(details.localPosition)) {
                onFaceTap(face);
                break;
              }
            }
          }
        },
      ),
    );
  }
}

class FacePainter extends CustomPainter {
  final List<Face> faces;
  final Map<int, String> faceNames;
  final Map<int, double> faceConfidences;
  final Map<int, List<double>> unrecognizedFeatures;

  FacePainter(this.faces, this.faceNames, this.faceConfidences, this.unrecognizedFeatures) {
    debugPrint('Painting ${faces.length} faces');
  }

  @override
  void paint(Canvas canvas, Size size) {
    final recognizedPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..color = Colors.red;

    final unrecognizedPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..color = Colors.yellow;

    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 16,
      backgroundColor: Colors.black54,
    );

    for (final face in faces) {
      final paint = (face.trackingId != null && unrecognizedFeatures.containsKey(face.trackingId))
          ? unrecognizedPaint
          : recognizedPaint;
      canvas.drawRect(face.boundingBox, paint);

      if (face.trackingId != null && faceNames.containsKey(face.trackingId)) {
        final name = faceNames[face.trackingId]!;
        final confidence = faceConfidences[face.trackingId]!.toStringAsFixed(0);
        final textSpan = TextSpan(text: '$name: $confidence%', style: textStyle);
        final textPainter = TextPainter(
          text: textSpan,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        final offset = Offset(
          face.boundingBox.left + (face.boundingBox.width - textPainter.width) / 2,
          face.boundingBox.bottom + 5,
        );
        textPainter.paint(canvas, offset);
      }
    }
  }

  @override
  bool shouldRepaint(covariant FacePainter oldDelegate) {
    return oldDelegate.faces != faces ||
        oldDelegate.faceNames != faceNames ||
        oldDelegate.faceConfidences != faceConfidences ||
        oldDelegate.unrecognizedFeatures != unrecognizedFeatures;
  }
}