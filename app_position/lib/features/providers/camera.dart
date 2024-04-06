import 'dart:async';
import 'dart:io';
import 'package:app_position/features/data/exercise.dart';
import 'package:app_position/features/models/exercise.dart';
import 'package:app_position/features/providers/settings.dart';
import 'package:app_position/features/views/widgets/pose_painter.dart';
import 'package:wakelock/wakelock.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class Camera extends ChangeNotifier with Settings {
  Camera() {
    _initTTS();
  }

  void _initTTS() async {
    final voiceList = await flutterTts.getVoices;
    try {
      final voicesList = List<Map>.from(voiceList);
      for (var element in voicesList) {
        final e = element['locale'] as String;
        // if (e.contains('es') || e.contains('en')) {
        if (e.contains('es')) {
          availableVoices.add(element);
          if (!localeVoices.contains(e)) {
            localeVoices.add(e);
          }
        }
      }
      notifyListeners();
    } catch (ex) {
      debugPrint(ex.toString());
    }
  }

  var initialCameraLensDirection = CameraLensDirection.back;
  List<CameraDescription> cameras = [];
  final List<Exercise> listExercises = [
    fullBridge,
    sideLeftBridge,
    sideRightBridge,
    dBridge,
    cBridge,
  ];
  late Exercise currentExercise = listExercises.first;
  int get fullTime =>
      listExercises.reduce((value, element) => element.copyWith(time: value.time + element.time)).time.inSeconds;
  int get totalTime => fullTime * 1000;
  String get time =>
      '${(fullMillisecondsElapsed ~/ 60000).toString().padLeft(2, '0')}:${((fullMillisecondsElapsed ~/ 1000) % 60).toString().padLeft(2, '0')}.${((fullMillisecondsElapsed % 1000) ~/ 10).toString().padLeft(2, '0')}';
  CameraController? controller;
  int cameraIndex = -1;
  bool changingCameraLens = false;

  bool isTimerRunning = false;
  int millisecondsElapsed = 0;
  Timer? timer;

  void startTimer(BuildContext context, [Exercise? currentExercise]) {
    final exercise = currentExercise ?? this.currentExercise;
    isTimerRunning = true;
    talk(exercise.name);
    bool isBecomingOtherExercise = false;
    timer = Timer.periodic(
      const Duration(milliseconds: 10),
      (Timer t) {
        millisecondsElapsed += 10;
        exercise.millisecondsElapsed = millisecondsElapsed;
        if (millisecondsElapsed >= exercise.time.inMilliseconds - 4000 && !isBecomingOtherExercise) {
          isBecomingOtherExercise = true;
          talk('3 segundos');
        }
        if (millisecondsElapsed >= exercise.time.inMilliseconds) {
          stopTimer();
          final id = listExercises.indexOf(exercise);
          millisecondsElapsed = 0;
          exercise.isDone = true;
          if (id != -1 && id < listExercises.length - 1) {
            this.currentExercise = listExercises[id + 1];
            startTimer(context, this.currentExercise);
          }
        }
        notifyListeners();
      },
    );
  }

  void restartTimer(BuildContext context) {
    listExercises.forEach((element) {
      element.isDone = false;
      element.millisecondsElapsed = 0;
    });
    millisecondsElapsed = 0;
    currentExercise = listExercises.first;
    startTimer(context);
    notifyListeners();
  }

  void stopTimer() {
    timer?.cancel();
    isTimerRunning = false;
    notifyListeners();
  }

  double get exerciseProgress => millisecondsElapsed / currentExercise.time.inMilliseconds;
  int get fullMillisecondsElapsed => listExercises
      .reduce((value, element) =>
          element.copyWith(millisecondsElapsed: value.millisecondsElapsed + element.millisecondsElapsed))
      .millisecondsElapsed;
  double get fullProgress => fullMillisecondsElapsed / totalTime;

  Future<void> initCameras() async {
    if (cameras.isEmpty) {
      cameras = await availableCameras();
    }
  }

  final PoseDetector _poseDetector = PoseDetector(options: PoseDetectorOptions(model: PoseDetectionModel.base));

  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? customPaint;

  void disposeCameras() {
    _canProcess = false;
    _poseDetector.close();
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;
    notifyListeners();
    await _paintLines(inputImage);
    _isBusy = false;
    notifyListeners();
  }

  Future<void> _paintLines(InputImage inputImage) async {
    final poses = await _poseDetector.processImage(inputImage);
    if (poses.isEmpty || inputImage.metadata?.size == null || inputImage.metadata?.rotation == null) {
      customPaint = null;
      return;
    }
    customPaint = CustomPaint(
      painter: PosePainter(
        poses.first,
        inputImage.metadata!.size,
        inputImage.metadata!.rotation,
        initialCameraLensDirection,
        currentExercise,
      ),
    );
  }

  void initialize() async {
    await initCameras();
    Wakelock.enable();
    for (var i = 0; i < cameras.length; i++) {
      if (cameras[i].lensDirection == initialCameraLensDirection) {
        cameraIndex = i;
        notifyListeners();
        break;
      }
    }
    if (cameraIndex != -1) {
      await startLiveFeed();
    }
    notifyListeners();
  }

  Future startLiveFeed() async {
    final camera = cameras[cameraIndex];
    controller = CameraController(
      camera,
      // Set to ResolutionPreset.high. Do NOT set it to ResolutionPreset.max because for some phones does NOT work.
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    if (controller == null) return;
    await controller?.initialize();
    await controller?.startImageStream(_processCameraImage);
    notifyListeners();
  }

  Future stopLiveFeed() async {
    await controller?.stopImageStream();
    // await controller?.dispose();
    // controller = null;
  }

  Future switchLiveCamera() async {
    changingCameraLens = true;
    notifyListeners();
    cameraIndex = (cameraIndex + 1) % cameras.length;

    await stopLiveFeed();
    await startLiveFeed();
    changingCameraLens = false;
    notifyListeners();
  }

  void _processCameraImage(CameraImage image) {
    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) return;
    _processImage(inputImage);
  }

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (controller == null) return null;

    // get image rotation
    // it is used in android to convert the InputImage from Dart to Java: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/android/src/main/java/com/google_mlkit_commons/InputImageConverter.java
    // `rotation` is not used in iOS to convert the InputImage from Dart to Obj-C: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/ios/Classes/MLKVisionImage%2BFlutterPlugin.m
    // in both platforms `rotation` and `camera.lensDirection` can be used to compensate `x` and `y` coordinates on a canvas: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/example/lib/vision_detector_views/painters/coordinates_translator.dart
    final camera = cameras[cameraIndex];
    final sensorOrientation = camera.sensorOrientation;
    // print(
    //     'lensDirection: ${camera.lensDirection}, sensorOrientation: $sensorOrientation, ${_controller?.value.deviceOrientation} ${_controller?.value.lockedCaptureOrientation} ${_controller?.value.isCaptureOrientationLocked}');
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = _orientations[controller!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        // front-facing
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // back-facing
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      // print('rotationCompensation: $rotationCompensation');
    }
    if (rotation == null) return null;
    // print('final rotation: $rotation');

    // get image format
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    // validate format depending on platform
    // only supported formats:
    // * nv21 for Android
    // * bgra8888 for iOS
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;

    // since format is constraint to nv21 or bgra8888, both only have one plane
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    // compose InputImage using bytes
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation, // used only in Android
        format: format, // used only in iOS
        bytesPerRow: plane.bytesPerRow, // used only in iOS
      ),
    );
  }
}
