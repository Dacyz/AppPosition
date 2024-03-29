import 'package:app_position/core/const.dart';
import 'package:app_position/features/providers/camera.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CameraView extends StatefulWidget {
  const CameraView({
    Key? key,
  }) : super(key: key);

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  late Camera camera;

  @override
  void initState() {
    camera = Provider.of<Camera>(context, listen: false);
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => camera.initialize());
  }

  @override
  void dispose() {
    if (mounted) {
      camera.stopLiveFeed();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _liveFeedBody(),
        _backButton(),
        _switchExercise(),
        _decoration(),
      ],
    );
  }

  Widget _decoration() => Positioned(
        bottom: -1,
        left: 0,
        right: 0,
        child: Container(
          height: 32,
          width: double.infinity,
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
            color: Colors.white,
          ),
        ),
      );
  Widget _switchExercise() {
    final list = camera.listExercises;
    return Positioned(
      bottom: 32,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 72,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(),
          clipBehavior: Clip.none,
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) => GestureDetector(
            onTap: () => camera.currentExercise = list[index],
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: camera.currentExercise == list[index]
                        ? AppConstants.colors.primary
                        : AppConstants.colors.disabled,
                    borderRadius: BorderRadius.circular(32)),
                child: Text(
                  list[index].name,
                  style: TextStyle(
                    color: camera.currentExercise == list[index]
                        ? AppConstants.colors.disabled
                        : AppConstants.colors.primary,
                  ),
                )),
          ),
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemCount: list.length,
        ),
      ),
    );
  }

  Widget _liveFeedBody() {
    final camera = Provider.of<Camera>(context);
    if (camera.cameras.isEmpty) return const SizedBox();
    if (camera.controller == null) return const SizedBox();
    if (camera.controller?.value.isInitialized == false) return const SizedBox();
    if (camera.changingCameraLens) return const Center(child: Text('Changing camera lens'));
    final value = camera.controller!.value;
    // fetch screen size
    final size = MediaQuery.sizeOf(context);
    // calculate scale depending on screen and camera ratios
    // this is actually size.aspectRatio / (1 / camera.aspectRatio)
    // because camera preview size is received as landscape
    // but we're calculating for portrait orientation
    var scale = size.aspectRatio * value.aspectRatio;

    // to prevent scaling down, invert the value
    if (scale < 1) scale = 1 / scale;
    return Center(
      child: Transform.scale(
        scale: scale,
        child: Center(
          child: CameraPreview(
            camera.controller!,
            child: camera.customPaint,
          ),
        ),
      ),
    );
  }

  Widget _backButton() => Positioned(
        top: 42,
        left: 16,
        child: FloatingActionButton(
          heroTag: Object(),
          shape: const CircleBorder(),
          elevation: 0,
          onPressed: () => Navigator.of(context).pop(),
          backgroundColor: Colors.white,
          child: Icon(
            Icons.arrow_back_ios_outlined,
            color: AppConstants.colors.primary,
            size: 20,
          ),
        ),
      );
}
