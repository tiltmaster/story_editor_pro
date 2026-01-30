import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'story_editor_screen.dart';
import 'advanced_boomerang_service.dart';
import 'gradient_text_editor.dart';
import 'camera_settings_screen.dart';
import 'config/story_editor_config.dart';
import 'models/story_result.dart';

/// Layout türleri - Instagram Layout tarzı kolaj düzenleri
enum LayoutType {
  /// Dikey 2'li - Alt alta 2 kare
  twoVertical,

  /// Yatay 2'li - Yan yana 2 uzun kare
  twoHorizontal,

  /// 2x2 Grid - 4 kare
  fourGrid,

  /// 2x3 Grid - 6 kare
  sixGrid,
}

/// LayoutType için helper extension
extension LayoutTypeExtension on LayoutType {
  /// Bu layout kaç fotoğraf gerektiriyor
  int get photoCount {
    switch (this) {
      case LayoutType.twoVertical:
      case LayoutType.twoHorizontal:
        return 2;
      case LayoutType.fourGrid:
        return 4;
      case LayoutType.sixGrid:
        return 6;
    }
  }

  /// Layout için ikon gösterimi (basit temsil)
  String get label {
    switch (this) {
      case LayoutType.twoVertical:
        return '2V';
      case LayoutType.twoHorizontal:
        return '2H';
      case LayoutType.fourGrid:
        return '2×2';
      case LayoutType.sixGrid:
        return '2×3';
    }
  }
}

class StoryCameraScreen extends StatefulWidget {
  /// Called when an image is captured (before editing)
  final Function(String imagePath)? onImageCaptured;

  /// Called when story is shared
  /// Contains story file info and selected close friends (if any)
  final Function(StoryShareResult result)? onStoryShare;

  final Color? primaryColor;
  final bool showEditor;

  /// List of close friends to show in the share bottomsheet
  /// If not empty, close friends sharing option will be enabled
  /// If empty, the share bottomsheet will be skipped
  final List<CloseFriend> closeFriendsList;

  /// Returns true if close friends list is not empty
  bool get closeFriendsEnabled => closeFriendsList.isNotEmpty;

  const StoryCameraScreen({
    super.key,
    this.onImageCaptured,
    this.onStoryShare,
    this.primaryColor,
    this.showEditor = true,
    this.closeFriendsList = const [],
  });

  @override
  State<StoryCameraScreen> createState() => _StoryCameraScreenState();
}

class _StoryCameraScreenState extends State<StoryCameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // Flutter Camera
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;
  bool _isInitialized = false;

  bool _isLoading = true;
  bool _hasPermission = false;
  bool _isCapturing = false;
  FlashMode _flashMode = FlashMode.off;
  double _zoomLevel = 1.0;
  double _baseZoomLevel = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  Uint8List? _lastGalleryThumbnail; // Thumbnail data for gallery button
  bool _hasGalleryPermission = false;

  // Ayarlar
  bool _toolsOnLeft = false; // Araç çubuğu sol tarafta mı

  // Boomerang state
  bool _isBoomerangMode = false;
  static const int _boomerangMaxSeconds = 4; // Max 4 saniye

  // Video recording state
  bool _isVideoRecording = false;
  bool _isProcessingVideo = false;
  Timer? _videoRecordingTimer;
  int _videoRecordingElapsedMs = 0;
  static const int _videoMaxSeconds = 60; // Max 60 saniye

  // Boomerang recording progress
  Timer? _boomerangTimer;
  double _boomerangProgress = 0.0; // 0.0 - 1.0
  int _boomerangElapsedMs = 0;

  // Flash efekti için
  bool _showFlash = false;

  // MultiLayout (Collage) state
  bool _isLayoutMode = false;
  bool _showLayoutSelector = false;
  LayoutType _selectedLayout = LayoutType.twoVertical;
  List<File?> _capturedLayoutPhotos = [];
  int _activeLayoutIndex = 0;

  // Create Mode'dan gelen bekleyen metin overlay'i
  TextOverlay? _pendingTextOverlay;

  // Hands-free (eller serbest) mode state
  bool _isHandsFreeMode = false;
  bool _showHandsFreeSelector = false;
  int _handsFreeDelaySeconds = 3; // 3, 5 veya 10 saniye
  bool _isHandsFreeCountingDown = false;
  int _handsFreeCountdown = 0;
  Timer? _handsFreeCountdownTimer;
  Timer? _handsFreeRecordingTimer;
  int _handsFreeRecordingElapsed = 0;
  static const int _handsFreeMaxRecordingSeconds = 60; // 60 saniye max

  // Animasyon controller (boomerang butonu için)
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Pulse animasyonu
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    _loadSettings();
    _initializeCamera();
  }

  /// Load settings from config
  Future<void> _loadSettings() async {
    final config = StoryEditorConfigProvider.read(context);
    final toolsOnLeft = await config.settings.getToolsOnLeft();
    if (mounted) {
      setState(() {
        _toolsOnLeft = toolsOnLeft;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _boomerangTimer?.cancel();
    _flashTimer?.cancel();
    _videoRecordingTimer?.cancel();
    _handsFreeCountdownTimer?.cancel();
    _handsFreeRecordingTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _isInitialized = false;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    setState(() => _isLoading = true);

    try {
      // Kamera izni kontrolü
      var cameraStatus = await Permission.camera.status;
      if (!cameraStatus.isGranted) {
        cameraStatus = await Permission.camera.request();
      }
      _hasPermission = cameraStatus.isGranted;

      if (!_hasPermission) {
        setState(() => _isLoading = false);
        return;
      }

      // Mikrofon izni (video için)
      var micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        await Permission.microphone.request();
      }

      // Kameraları al
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        debugPrint('No cameras available');
        setState(() => _isLoading = false);
        return;
      }

      // Get default camera from config
      if (!mounted) return;
      final config = StoryEditorConfigProvider.read(context);
      final useFrontCamera = await config.settings.getFrontCameraDefault();
      final preferredDirection = useFrontCamera
          ? CameraLensDirection.front
          : CameraLensDirection.back;

      _currentCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == preferredDirection,
      );
      if (_currentCameraIndex == -1) _currentCameraIndex = 0;

      // Controller oluştur
      await _setupCameraController(_cameras[_currentCameraIndex]);

      // Galeri izni
      var galleryStatus = await Permission.photos.status;
      if (!galleryStatus.isGranted) {
        galleryStatus = await Permission.photos.request();
      }
      _hasGalleryPermission = galleryStatus.isGranted;

      if (_hasGalleryPermission && mounted) {
        await _loadLastGalleryImage();
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setupCameraController(CameraDescription camera) async {
    await _cameraController?.dispose();

    _cameraController = CameraController(
      camera,
      ResolutionPreset.veryHigh,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cameraController!.initialize();
      await _cameraController!.lockCaptureOrientation(
        DeviceOrientation.portraitUp,
      );

      _minZoom = await _cameraController!.getMinZoomLevel();
      _maxZoom = await _cameraController!.getMaxZoomLevel();
      _zoomLevel = _minZoom;

      await _cameraController!.setFlashMode(_flashMode);

      _isInitialized = true;

      debugPrint('Camera initialized: ${_cameraController!.value.previewSize}');

      if (mounted) setState(() {});
    } on CameraException catch (e) {
      debugPrint('CameraException: ${e.description}');
      _isInitialized = false;
    }
  }

  Future<void> _loadLastGalleryImage() async {
    try {
      // Galeri izni kontrolü
      final PermissionState permission =
          await PhotoManager.requestPermissionExtend(
            requestOption: const PermissionRequestOption(
              iosAccessLevel: IosAccessLevel.readWrite,
            ),
          );

      if (!permission.hasAccess) {
        debugPrint('Gallery permission denied: $permission');
        return;
      }

      // Cache'i temizle - yeni fotoğrafları görebilmek için
      await PhotoManager.clearFileCache();

      // Tüm albümleri al (resim ve video)
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
        onlyAll: true,
      );

      debugPrint('Found ${albums.length} albums');

      if (albums.isEmpty) {
        debugPrint('No albums found');
        return;
      }

      // İlk albüm (All Photos / Recent)
      final AssetPathEntity recentAlbum = albums.first;
      final int assetCount = await recentAlbum.assetCountAsync;
      debugPrint('Album: ${recentAlbum.name}, asset count: $assetCount');

      if (assetCount == 0) {
        debugPrint('No assets in album');
        return;
      }

      // Son eklenen medyaları al (daha fazla dene, görüntülenebilen ilkini bul)
      final List<AssetEntity> recentAssets = await recentAlbum
          .getAssetListPaged(
            page: 0,
            size: 20, // Daha fazla al, thumbnail alınabileni bul
          );

      if (recentAssets.isEmpty) {
        debugPrint('No assets found in gallery');
        return;
      }

      // Thumbnail alınabilen ilk asset'i bul (retry ile)
      for (final asset in recentAssets) {
        debugPrint('Trying asset: ${asset.id}, type: ${asset.type}');

        // Her asset için 2 deneme yap
        for (int retry = 0; retry < 2; retry++) {
          try {
            // Thumbnail al (daha güvenilir)
            final Uint8List? thumbData = await asset.thumbnailDataWithSize(
              const ThumbnailSize(200, 200),
              quality: 80,
            );

            if (thumbData != null && mounted) {
              debugPrint('Thumbnail loaded for asset: ${asset.id}');
              setState(() {
                _lastGalleryThumbnail = thumbData;
                _hasGalleryPermission = true;
              });
              return; // İlk başarılı olanı bulduk, çık
            }
          } catch (e) {
            debugPrint('Thumbnail load attempt ${retry + 1} failed: $e');
          }

          // İlk denemede başarısız olduysa biraz bekle
          if (retry == 0) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
        }
      }

      // Hiçbir thumbnail alınamadıysa, en azından permission'ı true yap
      if (mounted) {
        setState(() {
          _hasGalleryPermission = true;
        });
      }
      debugPrint('Could not get thumbnail from any asset');
    } catch (e, stackTrace) {
      debugPrint('Error loading last gallery image: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// Galeriye tıklandığında çalışır - izin iste ve galeriyi aç
  Future<void> _openGallery() async {
    try {
      // Önce izin kontrolü yap
      final PermissionState permission =
          await PhotoManager.requestPermissionExtend(
            requestOption: const PermissionRequestOption(
              iosAccessLevel: IosAccessLevel.readWrite,
            ),
          );

      if (!permission.hasAccess) {
        // İzin verilmedi - uyarı göster
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Gallery access denied'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: () => PhotoManager.openSetting(),
              ),
            ),
          );
        }
        return;
      }

      // İzin varsa - galeri permission'ı güncelle
      if (mounted) {
        setState(() => _hasGalleryPermission = true);
      }

      // Cache'i temizle - yeni fotoğrafları görebilmek için
      await PhotoManager.clearFileCache();

      // Galeri seçici aç - filterOption ile güncel medyaları al
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
        onlyAll: true,
      );

      if (albums.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No media found in gallery'),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Tüm medyaları al
      final AssetPathEntity album = albums.first;
      final int totalCount = await album.assetCountAsync;

      if (totalCount == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No media found in gallery'),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Galeri seçici sayfasını aç
      if (mounted) {
        final selectedAsset = await Navigator.push<AssetEntity>(
          context,
          MaterialPageRoute(
            builder: (context) =>
                _GalleryPickerPage(album: album, totalCount: totalCount),
          ),
        );

        // Seçilen medyayı işle
        if (selectedAsset != null && mounted) {
          final File? file = await selectedAsset.originFile;
          if (file != null && mounted) {
            // Resim mi video mu kontrol et
            if (selectedAsset.type == AssetType.image) {
              widget.onImageCaptured?.call(file.path);

              if (widget.showEditor && mounted) {
                final pendingOverlay = _pendingTextOverlay;
                _pendingTextOverlay = null; // Kullanıldıktan sonra temizle

                await Navigator.push<Map<String, dynamic>?>(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => StoryEditorScreen(
                      imagePath: file.path,
                      primaryColor: widget.primaryColor,
                      isFromGallery: true,
                      initialTextOverlay: pendingOverlay,
                      closeFriendsList: widget.closeFriendsList,
                      onShare: widget.onStoryShare,
                    ),
                  ),
                );
                // onStoryShare callback is called from StoryEditorScreen
              }
            } else if (selectedAsset.type == AssetType.video) {
              // Video selected - call callback
              widget.onImageCaptured?.call(file.path);
            }
          }
        }

        // Galeri thumbnail'ini güncelle
        if (mounted) {
          _loadLastGalleryImage();
        }
      }
    } catch (e) {
      debugPrint('Gallery open error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open gallery'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _takePicture() async {
    if (_cameraController == null ||
        !_isInitialized ||
        _isCapturing ||
        _isVideoRecording) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      HapticFeedback.mediumImpact();

      final XFile file = await _cameraController!.takePicture();
      final imagePath = file.path;

      if (mounted) {
        // Layout modunda çekilen fotoğrafı listeye ekle
        if (_isLayoutMode) {
          await _handleLayoutCapture(imagePath);
        } else {
          // Normal mod
          widget.onImageCaptured?.call(imagePath);

          if (widget.showEditor) {
            final pendingOverlay = _pendingTextOverlay;
            _pendingTextOverlay = null; // Kullanıldıktan sonra temizle

            await Navigator.push<Map<String, dynamic>?>(
              context,
              MaterialPageRoute(
                builder: (context) => StoryEditorScreen(
                  imagePath: imagePath,
                  primaryColor: widget.primaryColor,
                  initialTextOverlay: pendingOverlay,
                  closeFriendsList: widget.closeFriendsList,
                  onShare: widget.onStoryShare,
                ),
              ),
            );
            // onStoryShare callback is called from StoryEditorScreen
          }

          // Update gallery thumbnail after photo capture
          _loadLastGalleryImage();
        }
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not take photo: $e')));
      }
    }

    if (mounted) {
      setState(() => _isCapturing = false);
    }
  }

  /// Layout modunda fotoğraf çekildiğinde
  Future<void> _handleLayoutCapture(String imagePath) async {
    // Fotoğrafı aktif tile'a kaydet
    setState(() {
      _capturedLayoutPhotos[_activeLayoutIndex] = File(imagePath);
    });

    // Bir sonraki boş tile'ı bul
    int? nextEmptyIndex;
    for (int i = 0; i < _capturedLayoutPhotos.length; i++) {
      if (_capturedLayoutPhotos[i] == null) {
        nextEmptyIndex = i;
        break;
      }
    }

    if (nextEmptyIndex != null) {
      // Sonraki boş tile'a geç
      setState(() {
        _activeLayoutIndex = nextEmptyIndex!;
      });
    } else {
      // Tüm fotoğraflar çekildi - collage oluştur
      await _createCollage();
    }
  }

  /// Layout modunda tile için galeriden resim seç
  Future<void> _pickImageForLayoutTile(int tileIndex) async {
    try {
      // Önce izin kontrolü yap
      final PermissionState permission =
          await PhotoManager.requestPermissionExtend(
            requestOption: const PermissionRequestOption(
              iosAccessLevel: IosAccessLevel.readWrite,
            ),
          );

      if (!permission.hasAccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Gallery access denied'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: () => PhotoManager.openSetting(),
              ),
            ),
          );
        }
        return;
      }

      // Cache'i temizle
      await PhotoManager.clearFileCache();

      // Albümleri al - sadece resimler için
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
        onlyAll: true,
      );

      if (albums.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No images found in gallery'),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final AssetPathEntity album = albums.first;
      final int totalCount = await album.assetCountAsync;

      if (totalCount == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No images found in gallery'),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Galeri seçici sayfasını aç
      if (mounted) {
        final selectedAsset = await Navigator.push<AssetEntity>(
          context,
          MaterialPageRoute(
            builder: (context) =>
                _GalleryPickerPage(album: album, totalCount: totalCount),
          ),
        );

        // Seçilen resmi tile'a yerleştir
        if (selectedAsset != null && mounted) {
          final File? file = await selectedAsset.originFile;
          if (file != null && mounted) {
            HapticFeedback.mediumImpact();

            setState(() {
              _capturedLayoutPhotos[tileIndex] = file;
            });

            // Bir sonraki boş tile'ı bul
            int? nextEmptyIndex;
            for (int i = 0; i < _capturedLayoutPhotos.length; i++) {
              if (_capturedLayoutPhotos[i] == null) {
                nextEmptyIndex = i;
                break;
              }
            }

            if (nextEmptyIndex != null) {
              // Sonraki boş tile'a geç
              setState(() {
                _activeLayoutIndex = nextEmptyIndex!;
              });
            } else {
              // Tüm fotoğraflar hazır - collage oluştur
              await _createCollage();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Layout gallery pick error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open gallery'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Tüm fotoğraflar çekildiğinde collage oluştur
  Future<void> _createCollage() async {
    // Tüm fotoğrafların çekildiğinden emin ol
    if (_capturedLayoutPhotos.any((photo) => photo == null)) {
      return;
    }

    setState(() => _isProcessingVideo = true);

    try {
      // Collage oluştur
      final collagePath = await _generateCollageImage();

      if (collagePath != null && mounted) {
        // İşleme tamamlandı
        setState(() {
          _isProcessingVideo = false;
          _isLayoutMode = false;
          _showLayoutSelector = false;
        });

        // Editor'e yönlendir
        widget.onImageCaptured?.call(collagePath);

        if (widget.showEditor) {
          final pendingOverlay = _pendingTextOverlay;
          _pendingTextOverlay = null; // Kullanıldıktan sonra temizle

          await Navigator.push<Map<String, dynamic>?>(
            context,
            MaterialPageRoute(
              builder: (context) => StoryEditorScreen(
                imagePath: collagePath,
                primaryColor: widget.primaryColor,
                initialTextOverlay: pendingOverlay,
                closeFriendsList: widget.closeFriendsList,
                onShare: widget.onStoryShare,
              ),
            ),
          );
          // onStoryShare callback is called from StoryEditorScreen
        }

        // Reset layout state
        setState(() {
          _capturedLayoutPhotos = [];
          _activeLayoutIndex = 0;
        });

        _loadLastGalleryImage();
      }
    } catch (e) {
      debugPrint('Collage creation error: $e');
      if (mounted) {
        setState(() => _isProcessingVideo = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not create collage: $e')));
      }
    }
  }

  /// Collage görüntüsü oluştur (Canvas ile birleştir)
  Future<String?> _generateCollageImage() async {
    try {
      // Fotoğrafları yükle
      final List<File> photos = _capturedLayoutPhotos
          .whereType<File>()
          .toList();
      if (photos.isEmpty) return null;

      // Canvas boyutu (1080x1920 story formatı)
      const int canvasWidth = 1080;
      const int canvasHeight = 1920;
      const double spacing = 0.0; // Boşluksuz tam ekran

      // Picture recorder ile canvas oluştur
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Arka plan siyah
      canvas.drawRect(
        Rect.fromLTWH(0, 0, canvasWidth.toDouble(), canvasHeight.toDouble()),
        Paint()..color = Colors.black,
      );

      // Her fotoğrafı layout'a göre yerleştir
      await _drawLayoutPhotos(
        canvas,
        photos,
        canvasWidth,
        canvasHeight,
        spacing,
      );

      // Picture'ı image'e çevir
      final picture = recorder.endRecording();
      final img = await picture.toImage(canvasWidth, canvasHeight);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) return null;

      // Dosyaya kaydet
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/collage_$timestamp.png';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(byteData.buffer.asUint8List());

      return outputPath;
    } catch (e) {
      debugPrint('Generate collage error: $e');
      return null;
    }
  }

  /// Sadece gradient arka plan görseli oluştur (yazısız)
  Future<String?> _createGradientBackground(LinearGradient gradient) async {
    try {
      const int canvasWidth = 1080;
      const int canvasHeight = 1920;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Gradient arka planı çiz
      final gradientPaint = Paint()
        ..shader = gradient.createShader(
          Rect.fromLTWH(0, 0, canvasWidth.toDouble(), canvasHeight.toDouble()),
        );
      canvas.drawRect(
        Rect.fromLTWH(0, 0, canvasWidth.toDouble(), canvasHeight.toDouble()),
        gradientPaint,
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(canvasWidth, canvasHeight);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) return null;

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/gradient_bg_$timestamp.png';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(byteData.buffer.asUint8List());

      return outputPath;
    } catch (e) {
      debugPrint('Create gradient background error: $e');
      return null;
    }
  }

  /// Layout'a göre fotoğrafları canvas'a çiz
  Future<void> _drawLayoutPhotos(
    Canvas canvas,
    List<File> photos,
    int canvasWidth,
    int canvasHeight,
    double spacing,
  ) async {
    final List<Rect> rects = _getLayoutRects(
      canvasWidth.toDouble(),
      canvasHeight.toDouble(),
      spacing,
    );

    for (int i = 0; i < photos.length && i < rects.length; i++) {
      final rect = rects[i];
      final photoBytes = await photos[i].readAsBytes();
      final codec = await ui.instantiateImageCodec(photoBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      // Fotoğrafı rect'e sığdır (cover)
      final srcRect = _getCoverRect(
        Size(image.width.toDouble(), image.height.toDouble()),
        rect.size,
      );

      canvas.save();
      canvas.clipRect(rect); // Köşesiz, tam ekran
      canvas.drawImageRect(image, srcRect, rect, Paint());
      canvas.restore();
    }
  }

  /// Layout türüne göre rect pozisyonlarını hesapla
  List<Rect> _getLayoutRects(double width, double height, double spacing) {
    switch (_selectedLayout) {
      case LayoutType.twoVertical:
        final tileHeight = (height - spacing) / 2;
        return [
          Rect.fromLTWH(0, 0, width, tileHeight),
          Rect.fromLTWH(0, tileHeight + spacing, width, tileHeight),
        ];

      case LayoutType.twoHorizontal:
        final tileWidth = (width - spacing) / 2;
        return [
          Rect.fromLTWH(0, 0, tileWidth, height),
          Rect.fromLTWH(tileWidth + spacing, 0, tileWidth, height),
        ];

      case LayoutType.fourGrid:
        final tileWidth = (width - spacing) / 2;
        final tileHeight = (height - spacing) / 2;
        return [
          Rect.fromLTWH(0, 0, tileWidth, tileHeight),
          Rect.fromLTWH(tileWidth + spacing, 0, tileWidth, tileHeight),
          Rect.fromLTWH(0, tileHeight + spacing, tileWidth, tileHeight),
          Rect.fromLTWH(
            tileWidth + spacing,
            tileHeight + spacing,
            tileWidth,
            tileHeight,
          ),
        ];

      case LayoutType.sixGrid:
        final tileWidth = (width - spacing) / 2;
        final tileHeight = (height - spacing * 2) / 3;
        return [
          Rect.fromLTWH(0, 0, tileWidth, tileHeight),
          Rect.fromLTWH(tileWidth + spacing, 0, tileWidth, tileHeight),
          Rect.fromLTWH(0, tileHeight + spacing, tileWidth, tileHeight),
          Rect.fromLTWH(
            tileWidth + spacing,
            tileHeight + spacing,
            tileWidth,
            tileHeight,
          ),
          Rect.fromLTWH(0, (tileHeight + spacing) * 2, tileWidth, tileHeight),
          Rect.fromLTWH(
            tileWidth + spacing,
            (tileHeight + spacing) * 2,
            tileWidth,
            tileHeight,
          ),
        ];
    }
  }

  /// Cover mode için kaynak rect hesapla
  Rect _getCoverRect(Size srcSize, Size dstSize) {
    final srcAspect = srcSize.width / srcSize.height;
    final dstAspect = dstSize.width / dstSize.height;

    double cropWidth, cropHeight;
    if (srcAspect > dstAspect) {
      // Kaynak daha geniş, yatay crop
      cropHeight = srcSize.height;
      cropWidth = cropHeight * dstAspect;
    } else {
      // Kaynak daha uzun, dikey crop
      cropWidth = srcSize.width;
      cropHeight = cropWidth / dstAspect;
    }

    final left = (srcSize.width - cropWidth) / 2;
    final top = (srcSize.height - cropHeight) / 2;

    return Rect.fromLTWH(left, top, cropWidth, cropHeight);
  }

  Future<void> _startVideoRecording() async {
    if (_cameraController == null ||
        !_isInitialized ||
        _isCapturing ||
        _isVideoRecording) {
      return;
    }

    HapticFeedback.heavyImpact();

    try {
      await _cameraController!.startVideoRecording();

      if (mounted) {
        setState(() {
          _isVideoRecording = true;
          _isCapturing = true;
          _videoRecordingElapsedMs = 0;
        });

        // Video süre timer'ı başlat
        _videoRecordingTimer?.cancel();
        _videoRecordingTimer = Timer.periodic(
          const Duration(milliseconds: 100),
          (timer) {
            if (!mounted || !_isVideoRecording) {
              timer.cancel();
              return;
            }
            setState(() {
              _videoRecordingElapsedMs += 100;
            });
            // 60 saniyeye ulaşınca otomatik durdur
            if (_videoRecordingElapsedMs >= _videoMaxSeconds * 1000) {
              _stopVideoRecording();
            }
          },
        );
      }
    } catch (e) {
      debugPrint('Video start error: $e');
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_cameraController == null || !_isVideoRecording) return;

    HapticFeedback.mediumImpact();

    // Timer'ı durdur
    _videoRecordingTimer?.cancel();
    _videoRecordingTimer = null;

    setState(() {
      _isVideoRecording = false;
      _isProcessingVideo = true;
    });

    try {
      final XFile file = await _cameraController!.stopVideoRecording();
      final videoPath = file.path;

      if (mounted) {
        // Normal video - boomerang efekti uygulamadan direkt kullan
        setState(() {
          _isProcessingVideo = false;
          _isCapturing = false;
          _videoRecordingElapsedMs = 0;
        });

        if (mounted && widget.showEditor) {
          await Navigator.push<Map<String, dynamic>?>(
            context,
            MaterialPageRoute(
              builder: (context) => StoryEditorScreen(
                imagePath: videoPath,
                mediaType: MediaType.video,
                primaryColor: widget.primaryColor,
                closeFriendsList: widget.closeFriendsList,
                onShare: widget.onStoryShare,
              ),
            ),
          );
          // onStoryShare callback is called from StoryEditorScreen
        } else {
          // No editor - call onStoryShare directly
          final result = await StoryResult.fromFile(
            videoPath,
            durationMs: _videoRecordingElapsedMs,
          );
          widget.onStoryShare?.call(
            StoryShareResult(
              story: result,
              shareTarget: ShareTarget.story,
              selectedFriends: [],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Video stop error: $e');
      setState(() {
        _isProcessingVideo = false;
        _isCapturing = false;
        _videoRecordingElapsedMs = 0;
      });
    }
  }

  // ==================== BOOMERANG RECORDING ====================

  // Flash efekti timer'ı (boomerang kayıt sırasında sürekli yanıp söner)
  Timer? _flashTimer;

  /// Yanıp sönen flash efektini başlat (kayıt boyunca)
  void _startFlashEffect() {
    _flashTimer?.cancel();
    // Her 200ms'de bir flash yap
    _flashTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!_isVideoRecording || !mounted) {
        timer.cancel();
        if (mounted) setState(() => _showFlash = false);
        return;
      }
      // Flash'ı aç
      setState(() => _showFlash = true);
      // 80ms sonra kapat
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) setState(() => _showFlash = false);
      });
    });
  }

  /// Flash efektini durdur
  void _stopFlashEffect() {
    _flashTimer?.cancel();
    _flashTimer = null;
    if (mounted) setState(() => _showFlash = false);
  }

  void _startBoomerangRecording() async {
    if (_cameraController == null ||
        !_isInitialized ||
        _isCapturing ||
        _isVideoRecording) {
      return;
    }

    HapticFeedback.heavyImpact();

    try {
      await _cameraController!.startVideoRecording();

      // Kayıt başladı - flash efektini başlat
      _startFlashEffect();

      setState(() {
        _isVideoRecording = true;
        _isCapturing = true;
        _boomerangProgress = 0.0;
        _boomerangElapsedMs = 0;
      });

      // Progress timer - her 50ms'de güncelle
      const updateInterval = 50;
      final maxMs = _boomerangMaxSeconds * 1000;

      _boomerangTimer = Timer.periodic(
        const Duration(milliseconds: updateInterval),
        (timer) {
          _boomerangElapsedMs += updateInterval;
          final progress = _boomerangElapsedMs / maxMs;

          if (mounted) {
            setState(() {
              _boomerangProgress = progress.clamp(0.0, 1.0);
            });
          }

          // Max süreye ulaşıldı - otomatik durdur
          if (_boomerangElapsedMs >= maxMs) {
            timer.cancel();
            _stopBoomerangRecording();
          }
        },
      );
    } catch (e) {
      debugPrint('Boomerang start error: $e');
    }
  }

  void _stopBoomerangRecording() async {
    _boomerangTimer?.cancel();
    _boomerangTimer = null;

    // Flash efektini durdur
    _stopFlashEffect();

    if (_cameraController == null || !_isVideoRecording) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _isVideoRecording = false;
      _isProcessingVideo = true;
      _boomerangProgress = 0.0;
    });

    try {
      final XFile file = await _cameraController!.stopVideoRecording();
      final videoPath = file.path;

      // Çekilen süreyi hesapla (saniye)
      final recordedSeconds = _boomerangElapsedMs / 1000.0;

      if (mounted) {
        // Boomerang efekti uygula
        final boomerangPath = await _createBoomerangEffect(
          videoPath,
          maxDuration: recordedSeconds.clamp(
            0.5,
            _boomerangMaxSeconds.toDouble(),
          ),
        );
        final finalPath = boomerangPath ?? videoPath;

        setState(() {
          _isProcessingVideo = false;
          _isCapturing = false;
          _boomerangElapsedMs = 0;
        });

        if (mounted && widget.showEditor) {
          await Navigator.push<Map<String, dynamic>?>(
            context,
            MaterialPageRoute(
              builder: (context) => StoryEditorScreen(
                imagePath: finalPath,
                mediaType: MediaType.video,
                primaryColor: widget.primaryColor,
                closeFriendsList: widget.closeFriendsList,
                onShare: widget.onStoryShare,
              ),
            ),
          );
          // onStoryShare callback is called from StoryEditorScreen
        } else {
          // No editor - call onStoryShare directly
          final result = await StoryResult.fromFile(
            finalPath,
            durationMs: _boomerangElapsedMs,
          );
          widget.onStoryShare?.call(
            StoryShareResult(
              story: result,
              shareTarget: ShareTarget.story,
              selectedFriends: [],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Boomerang stop error: $e');
      setState(() {
        _isProcessingVideo = false;
        _isCapturing = false;
        _boomerangElapsedMs = 0;
      });
    }
  }

  Future<String?> _createBoomerangEffect(
    String videoPath, {
    double maxDuration = 4.0,
  }) async {
    try {
      final inputFile = File(videoPath);

      final boomerangService = AdvancedBoomerangService(
        speedFactor: 2.0,
        loopCount: 3,
        maxInputDuration: maxDuration,
        outputQuality: 23, // 18'den 23'e çıkarıldı - daha hızlı encoding
        outputFps: 30,
      );

      final outputFile = await boomerangService.generateBoomerang(inputFile);

      if (outputFile != null && await outputFile.exists()) {
        debugPrint('Advanced Boomerang created: ${outputFile.path}');

        try {
          await inputFile.delete();
        } catch (e) {
          debugPrint('Failed to delete original video: $e');
        }

        return outputFile.path;
      }
    } catch (e) {
      debugPrint('Boomerang effect error: $e');
    }
    return null;
  }

  // ==================== HANDS-FREE RECORDING ====================

  /// Hands-free geri sayımı başlat
  void _startHandsFreeCountdown() {
    if (_isVideoRecording || _isCapturing || _isHandsFreeCountingDown) return;

    HapticFeedback.heavyImpact();

    setState(() {
      _isHandsFreeCountingDown = true;
      _handsFreeCountdown = _handsFreeDelaySeconds;
    });

    // Her saniye geri say
    _handsFreeCountdownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _handsFreeCountdown--;
      });

      HapticFeedback.lightImpact();

      if (_handsFreeCountdown <= 0) {
        timer.cancel();
        _startHandsFreeRecording();
      }
    });
  }

  /// Hands-free geri sayımı iptal et
  void _cancelHandsFreeCountdown() {
    _handsFreeCountdownTimer?.cancel();
    _handsFreeCountdownTimer = null;

    if (mounted) {
      setState(() {
        _isHandsFreeCountingDown = false;
        _handsFreeCountdown = 0;
      });
    }
  }

  /// Hands-free video kaydını başlat
  Future<void> _startHandsFreeRecording() async {
    if (_cameraController == null || !_isInitialized) return;

    HapticFeedback.heavyImpact();

    try {
      await _cameraController!.startVideoRecording();

      setState(() {
        _isHandsFreeCountingDown = false;
        _isVideoRecording = true;
        _isCapturing = true;
        _handsFreeRecordingElapsed = 0;
      });

      // Her saniye kayıt süresini güncelle
      _handsFreeRecordingTimer = Timer.periodic(const Duration(seconds: 1), (
        timer,
      ) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _handsFreeRecordingElapsed++;
        });

        // 60 saniyeye ulaşınca otomatik durdur
        if (_handsFreeRecordingElapsed >= _handsFreeMaxRecordingSeconds) {
          timer.cancel();
          _stopHandsFreeRecording();
        }
      });
    } catch (e) {
      debugPrint('Hands-free recording start error: $e');
      setState(() {
        _isHandsFreeCountingDown = false;
      });
    }
  }

  /// Hands-free video kaydını durdur
  Future<void> _stopHandsFreeRecording() async {
    _handsFreeRecordingTimer?.cancel();
    _handsFreeRecordingTimer = null;

    if (_cameraController == null || !_isVideoRecording) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _isVideoRecording = false;
      _isProcessingVideo = true;
    });

    try {
      final XFile file = await _cameraController!.stopVideoRecording();
      final videoPath = file.path;

      if (mounted) {
        setState(() {
          _isProcessingVideo = false;
          _isCapturing = false;
          _handsFreeRecordingElapsed = 0;
        });

        // Video editörüne yönlendir
        if (widget.showEditor) {
          await Navigator.push<Map<String, dynamic>?>(
            context,
            MaterialPageRoute(
              builder: (context) => StoryEditorScreen(
                imagePath: videoPath,
                mediaType: MediaType.video,
                primaryColor: widget.primaryColor,
                closeFriendsList: widget.closeFriendsList,
                onShare: widget.onStoryShare,
              ),
            ),
          );
          // onStoryShare callback is called from StoryEditorScreen
        } else {
          // No editor - call onStoryShare directly
          final result = await StoryResult.fromFile(
            videoPath,
            durationMs: _handsFreeRecordingElapsed * 1000,
          );
          widget.onStoryShare?.call(
            StoryShareResult(
              story: result,
              shareTarget: ShareTarget.story,
              selectedFriends: [],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Hands-free recording stop error: $e');
      setState(() {
        _isProcessingVideo = false;
        _isCapturing = false;
        _handsFreeRecordingElapsed = 0;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isVideoRecording) return;

    HapticFeedback.lightImpact();

    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
    await _setupCameraController(_cameras[_currentCameraIndex]);
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_isInitialized) return;

    HapticFeedback.lightImpact();

    setState(() {
      if (_flashMode == FlashMode.off) {
        _flashMode = FlashMode.always;
      } else if (_flashMode == FlashMode.always) {
        _flashMode = FlashMode.auto;
      } else {
        _flashMode = FlashMode.off;
      }
    });

    await _cameraController!.setFlashMode(_flashMode);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoomLevel = _zoomLevel;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_cameraController == null || !_isInitialized) return;

    final newZoom = (_baseZoomLevel * details.scale).clamp(_minZoom, _maxZoom);
    if (newZoom != _zoomLevel) {
      setState(() => _zoomLevel = newZoom);
      _cameraController!.setZoomLevel(_zoomLevel);
    }
  }

  Widget get _flashIcon {
    switch (_flashMode) {
      case FlashMode.always:
        return SvgPicture.asset(
          'packages/story_editor_pro/assets/icons/flash.svg',
          width: 24,
          height: 24,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        );
      case FlashMode.auto:
        return SvgPicture.asset(
          'packages/story_editor_pro/assets/icons/flash.svg',
          width: 24,
          height: 24,
          colorFilter: const ColorFilter.mode(
            Colors.yellowAccent,
            BlendMode.srcIn,
          ),
        );
      default:
        return SvgPicture.asset(
          'packages/story_editor_pro/assets/icons/flash-off.svg',
          width: 24,
          height: 24,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).viewPadding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            // Status bar alanı - siyah
            Container(height: statusBarHeight, color: Colors.black),
            // Geri kalan alan
            Expanded(
              child: _isLayoutMode ? _buildLayoutModeBody() : _buildNormalModeBody(),
            ),
          ],
        ),
      ),
    );
  }

  /// Layout modu için ayrı body
  Widget _buildLayoutModeBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (!_hasPermission) {
      return _buildPermissionDenied();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Layout preview - bottom bar'ın üstünde kalacak şekilde
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
            child: GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              child: Container(color: Colors.black, child: _buildLayoutGrid()),
            ),
          ),
        ),
        // UI her zaman görünür
        _buildTopControlsRow(),
        _buildSideTools(),
        // Bekleyen text overlay göstergesi
        if (_pendingTextOverlay != null) _buildPendingTextIndicator(),
        _buildCenterCaptureButton(),
        _buildBottomBar(),
        if (_zoomLevel > _minZoom) _buildZoomIndicator(),
        // Beyaz flash efekti
        if (_showFlash)
          AnimatedOpacity(
            opacity: _showFlash ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 100),
            child: Container(color: Colors.white.withValues(alpha: 0.1)),
          ),
      ],
    );
  }

  /// Bekleyen text overlay göstergesi - kullanıcıya Create Mode'dan
  /// metin oluşturulduğunu ve fotoğraf çekildikten sonra ekleneceğini gösterir
  Widget _buildPendingTextIndicator() {
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () {
            // İptal et
            setState(() {
              _pendingTextOverlay = null;
            });
            HapticFeedback.selectionClick();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: _pendingTextOverlay?.backgroundGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _pendingTextOverlay?.text ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 4)],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.close, color: Colors.white70, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Normal mod için body - kamera tam ekran
  Widget _buildNormalModeBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (!_hasPermission) {
      return _buildPermissionDenied();
    }

    return Column(
      children: [
        // Kamera preview alanı (üst kontroller + kamera + capture button)
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Kamera preview - sadece buna ClipRRect uygula
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: _buildFullscreenCameraPreview(),
              ),
              // Üst kontroller (X, Flash, Settings)
              _buildTopControlsRow(),
              // Sağ taraf ikonları (Boomerang, Text, Collage, HandsFree)
              _buildSideToolsColumn(),
              // Capture button - altta ortalanmış
              _buildCaptureButtonArea(),
              // Bekleyen text overlay göstergesi
              if (_pendingTextOverlay != null) _buildPendingTextIndicator(),
              // Zoom göstergesi
              if (_zoomLevel > _minZoom) _buildZoomIndicator(),
              // Hands-free geri sayım overlay'i
              if (_isHandsFreeCountingDown) _buildHandsFreeCountdownOverlay(),
              // Beyaz flash efekti
              if (_showFlash)
                AnimatedOpacity(
                  opacity: _showFlash ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 100),
                  child: Container(color: Colors.white.withValues(alpha: 0.1)),
                ),
            ],
          ),
        ),
        // Bottom bar
        _buildBottomBarRow(),
      ],
    );
  }

  /// Hands-free geri sayım overlay'i - büyük sayı gösterir
  Widget _buildHandsFreeCountdownOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Büyük geri sayım sayısı
              TweenAnimationBuilder<double>(
                key: ValueKey(_handsFreeCountdown),
                tween: Tween(begin: 1.5, end: 1.0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale,
                    child: Text(
                      '$_handsFreeCountdown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 120,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(color: Colors.black54, blurRadius: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              // İptal butonu
              GestureDetector(
                onTap: _cancelHandsFreeCountdown,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white54),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Hands-free kayıt süresi overlay'i
  /// Seçilen layout türüne göre grid oluştur - boşluksuz tam ekran
  Widget _buildLayoutGrid() {
    switch (_selectedLayout) {
      case LayoutType.twoVertical:
        return Column(
          children: [
            Expanded(child: _buildLayoutTile(0)),
            Expanded(child: _buildLayoutTile(1)),
          ],
        );

      case LayoutType.twoHorizontal:
        return Row(
          children: [
            Expanded(child: _buildLayoutTile(0)),
            Expanded(child: _buildLayoutTile(1)),
          ],
        );

      case LayoutType.fourGrid:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildLayoutTile(0)),
                  Expanded(child: _buildLayoutTile(1)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildLayoutTile(2)),
                  Expanded(child: _buildLayoutTile(3)),
                ],
              ),
            ),
          ],
        );

      case LayoutType.sixGrid:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildLayoutTile(0)),
                  Expanded(child: _buildLayoutTile(1)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildLayoutTile(2)),
                  Expanded(child: _buildLayoutTile(3)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildLayoutTile(4)),
                  Expanded(child: _buildLayoutTile(5)),
                ],
              ),
            ),
          ],
        );
    }
  }

  /// Tek bir layout tile'ı - aktif olanda kamera preview, çekilmişlerde fotoğraf
  /// Tam ekran, boşluksuz ve köşesiz tasarım
  Widget _buildLayoutTile(int index) {
    final isActive = index == _activeLayoutIndex;
    final File? capturedPhoto = index < _capturedLayoutPhotos.length
        ? _capturedLayoutPhotos[index]
        : null;

    return GestureDetector(
      onTap: () {
        // Tile'a tıklanınca o tile'ı aktif yap (henüz çekilmemişse)
        if (capturedPhoto == null) {
          HapticFeedback.selectionClick();
          setState(() {
            _activeLayoutIndex = index;
          });
        } else {
          // Çekilmiş fotoğrafa tıklanınca silme seçeneği
          _showDeletePhotoDialog(index);
        }
      },
      onLongPress: () {
        // Uzun basınca galeriden resim seç
        HapticFeedback.mediumImpact();
        _pickImageForLayoutTile(index);
      },
      child: Container(
        // İnce beyaz çizgi ile ayırma
        decoration: BoxDecoration(
          border: Border.all(
            color: isActive
                ? Colors.white
                : Colors.white.withValues(alpha: 0.2),
            width: isActive ? 2 : 0.5,
          ),
        ),
        child: capturedPhoto != null
            // Çekilmiş fotoğraf
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(capturedPhoto, fit: BoxFit.cover),
                  // Silme ikonu
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  // Index göstergesi
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            // Aktif tile - kamera preview
            : isActive
            ? _buildTileCameraPreview(index)
            // Bekleyen tile
            : Container(
                color: Colors.grey.shade900,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.camera_alt_outlined,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  /// Aktif tile için kamera preview - tam ekran
  Widget _buildTileCameraPreview(int index) {
    if (_cameraController == null || !_isInitialized) {
      return Container(
        color: Colors.grey.shade900,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Kamera preview (crop edilmiş, tam ekran)
        ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _cameraController!.value.previewSize?.height ?? 1920,
                height: _cameraController!.value.previewSize?.width ?? 1080,
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),
        ),
        // Index ve "ÇEK" yazısı
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Capture: ${index + 1}/${_selectedLayout.photoCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Çekilmiş fotoğrafı silme dialogu
  void _showDeletePhotoDialog(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'Delete Photo',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Do you want to delete this photo?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _capturedLayoutPhotos[index] = null;
                _activeLayoutIndex = index;
              });
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildFullscreenCameraPreview() {
    if (_cameraController == null || !_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Positioned alanının boyutlarını kullan (bottom bar hariç)
          final availableWidth = constraints.maxWidth;
          final availableHeight = constraints.maxHeight;
          final availableAspectRatio = availableWidth / availableHeight;
          final cameraAspectRatio = _cameraController!.value.aspectRatio;

          var scale = availableAspectRatio * cameraAspectRatio;
          if (scale < 1) scale = 1 / scale;

          return ClipRect(
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: Center(child: CameraPreview(_cameraController!)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.camera_alt_outlined,
              size: 80,
              color: Colors.white54,
            ),
            const SizedBox(height: 24),
            const Text(
              'Camera Permission Required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'We need camera access to create stories.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _initializeCamera,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.primaryColor ?? Colors.blue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Grant Permission',
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Üst kontroller - status bar zaten ayrı, SafeArea yok
  Widget _buildTopControlsRow() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildIconButton(
              iconWidget: SvgPicture.asset(
                'packages/story_editor_pro/assets/icons/xmark.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
              onTap: () {
                // Özel modlardaysa sadece modu kapat, değilse ekranı kapat
                if (_isLayoutMode) {
                  setState(() {
                    _isLayoutMode = false;
                    _showLayoutSelector = false;
                    _capturedLayoutPhotos = [];
                    _activeLayoutIndex = 0;
                  });
                } else if (_isBoomerangMode) {
                  setState(() {
                    _isBoomerangMode = false;
                  });
                } else if (_isHandsFreeMode) {
                  setState(() {
                    _isHandsFreeMode = false;
                    _showHandsFreeSelector = false;
                  });
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            _buildIconButton(iconWidget: _flashIcon, onTap: _toggleFlash),
            _buildIconButton(
              iconWidget: SvgPicture.asset(
                'packages/story_editor_pro/assets/icons/settings.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CameraSettingsScreen(),
                  ),
                );
                if (mounted) {
                  _loadSettings();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Capture button alanı - Stack içinde altta konumlanır
  Widget _buildCaptureButtonArea() {
    Widget captureButton;
    if (_isBoomerangMode || _isProcessingVideo) {
      captureButton = _buildBoomerangCaptureButton();
    } else if (_isHandsFreeMode) {
      captureButton = _buildHandsFreeCaptureButton();
    } else {
      captureButton = _buildNormalCaptureButton();
    }

    final screenHeight = MediaQuery.of(context).size.height;
    final bottomOffset = screenHeight < 700 ? 10.0 : 20.0;

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomOffset,
      child: Center(child: captureButton),
    );
  }

  /// Eski metod - Layout mode için hala kullanılıyor
  Widget _buildCenterCaptureButton() {
    // Bottom bar yüksekliği + butonun yarısı + biraz boşluk
    final bottomBarHeight =
        16 + 44 + MediaQuery.of(context).viewPadding.bottom + 16;
    final buttonBottomOffset =
        bottomBarHeight + 20; // Bottom bar'ın üstünde 20px boşluk

    // Boomerang modunda özel buton
    if (_isBoomerangMode || _isProcessingVideo) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: buttonBottomOffset,
        child: Center(child: _buildBoomerangCaptureButton()),
      );
    }

    // Hands-free modunda özel buton
    if (_isHandsFreeMode) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: buttonBottomOffset,
        child: Center(child: _buildHandsFreeCaptureButton()),
      );
    }

    // Normal mod - Custom video/photo buton
    return Positioned(
      left: 0,
      right: 0,
      bottom: buttonBottomOffset,
      child: Center(child: _buildNormalCaptureButton()),
    );
  }

  /// Normal mod için fotoğraf/video butonu - süre göstergesi ve progress ile
  Widget _buildNormalCaptureButton() {
    final screenHeight = MediaQuery.of(context).size.height;
    final double size = screenHeight < 700 ? 70 : 90; // Küçük ekranda 70, büyükte 90
    final double strokeWidth = screenHeight < 700 ? 4 : 6;
    const Color recordingColor = Color(0xFFFF3B30); // Kırmızı

    // Video kayıt progress (0.0 - 1.0)
    final videoProgress = _videoRecordingElapsedMs / (_videoMaxSeconds * 1000);

    // Süre formatı: 00:44
    final seconds = (_videoRecordingElapsedMs / 1000).floor();
    final timeString = '00:${seconds.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () {
        // Kısa dokunuş - fotoğraf çek
        if (!_isVideoRecording && !_isCapturing) {
          _takePicture();
        }
      },
      onLongPressStart: (_) {
        // Uzun basış - video kaydını başlat
        if (!_isVideoRecording && !_isCapturing) {
          _startVideoRecording();
        }
      },
      onLongPressEnd: (_) {
        // Parmak kaldırıldı - video kaydını durdur
        if (_isVideoRecording) {
          _stopVideoRecording();
        }
      },
      onLongPressCancel: () {
        // Parmak butondan kaydırıldı - video kaydını durdur
        if (_isVideoRecording) {
          _stopVideoRecording();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Süre göstergesi - butonun üstünde (sadece kayıt sırasında)
          if (_isVideoRecording)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                timeString,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          // Ana buton
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Dış halka - video kaydında progress gösterir
                SizedBox(
                  width: size,
                  height: size,
                  child: _isVideoRecording
                      ? CustomPaint(
                          painter: _VideoProgressPainter(
                            progress: videoProgress,
                            strokeWidth: strokeWidth,
                            progressColor: recordingColor,
                            backgroundColor: Colors.white,
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                        ),
                ),

                // İç daire - video kaydında küçülür ve kırmızı olur
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _isVideoRecording ? 35 : 70,
                  height: _isVideoRecording ? 35 : 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isVideoRecording ? recordingColor : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Hands-free için özel çekim butonu - video kaydı ile aynı görünüm
  Widget _buildHandsFreeCaptureButton() {
    const double size = 90;
    const double strokeWidth = 6;
    const Color recordingColor = Color(0xFFFF3B30); // Kırmızı

    // Video kayıt progress (0.0 - 1.0)
    final videoProgress =
        _handsFreeRecordingElapsed / _handsFreeMaxRecordingSeconds;

    // Süre formatı: 00:44
    final timeString =
        '00:${_handsFreeRecordingElapsed.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () {
        if (!_isVideoRecording && !_isCapturing && !_isHandsFreeCountingDown) {
          _startHandsFreeCountdown();
        } else if (_isVideoRecording) {
          _stopHandsFreeRecording();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Süre göstergesi - butonun üstünde (kayıt sırasında veya başlangıç bilgisi)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _isVideoRecording
                  ? timeString
                  : 'Start after ${_handsFreeDelaySeconds}s',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // Ana buton
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Dış halka - video kaydında progress gösterir
                SizedBox(
                  width: size,
                  height: size,
                  child: _isVideoRecording
                      ? CustomPaint(
                          painter: _VideoProgressPainter(
                            progress: videoProgress,
                            strokeWidth: strokeWidth,
                            progressColor: recordingColor,
                            backgroundColor: Colors.white,
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                        ),
                ),

                // İç daire - video kaydında küçülür ve kırmızı olur
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _isVideoRecording ? 35 : 70,
                  height: _isVideoRecording ? 35 : 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isVideoRecording ? recordingColor : Colors.white,
                  ),
                  child: _isVideoRecording
                      ? null
                      : Center(
                          child: SvgPicture.asset(
                            'packages/story_editor_pro/assets/icons/hand-free.svg',
                            width: 32,
                            height: 32,
                            colorFilter: const ColorFilter.mode(
                              Colors.black54,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Boomerang için özel çekim butonu - dairesel ilerleme göstergesi ile
  /// Instagram Boomerang renkleri: turuncu -> pembe gradient
  Widget _buildBoomerangCaptureButton() {
    const double size = 90;
    const double strokeWidth = 6;

    // Instagram Boomerang gradient renkleri
    const boomerangGradient = LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [
        Color(0xFFF77737), // Turuncu
        Color(0xFFE1306C), // Pembe
        Color(0xFFC13584), // Koyu pembe
      ],
    );

    return GestureDetector(
      onLongPressStart: (_) {
        if (!_isVideoRecording && !_isCapturing) {
          _startBoomerangRecording();
        }
      },
      onLongPressEnd: (_) {
        if (_isVideoRecording) {
          _stopBoomerangRecording();
        }
      },
      onLongPressCancel: () {
        if (_isVideoRecording) {
          _stopBoomerangRecording();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Üst yazı alanı - kayıt veya işleme durumuna göre
          Visibility(
            visible: _isVideoRecording || _isProcessingVideo,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (_isVideoRecording || _isProcessingVideo)
                    ? Colors.black54
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _isProcessingVideo
                    ? (_isLayoutMode
                          ? 'Processing image...'
                          : 'Processing video...')
                    : '${(_boomerangElapsedMs / 1000).toStringAsFixed(1)}s / ${_boomerangMaxSeconds}s',
                style: TextStyle(
                  color: (_isVideoRecording || _isProcessingVideo)
                      ? Colors.white
                      : Colors.transparent,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // Ana buton alanı
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Dış halka - her zaman görünür (processing dahil)
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isVideoRecording || _isProcessingVideo
                          ? 1.0
                          : (_isBoomerangMode ? _pulseAnimation.value : 1.0),
                      child: SizedBox(
                        width: size,
                        height: size,
                        child: _isVideoRecording
                            // Kayıt sırasında: progress ile dolan halka
                            ? CustomPaint(
                                painter: _GradientCircularProgressPainter(
                                  progress: _boomerangProgress,
                                  strokeWidth: strokeWidth,
                                  gradient: boomerangGradient,
                                  backgroundColor: Colors.white,
                                ),
                              )
                            // Normal ve Processing: beyaz border
                            : Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 4,
                                  ),
                                ),
                              ),
                      ),
                    );
                  },
                ),

                // İç daire - gradient veya processing circular
                _isProcessingVideo
                    ? const SizedBox(
                        width: 50,
                        height: 50,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          color: Colors.white,
                        ),
                      )
                    : AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: _isVideoRecording ? 35 : 70,
                        height: _isVideoRecording ? 35 : 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: boomerangGradient,
                        ),
                        child: _isVideoRecording
                            ? null
                            : Center(
                                child: SvgPicture.asset(
                                  'packages/story_editor_pro/assets/icons/infinite.svg',
                                  width: 28,
                                  height: 28,
                                  colorFilter: const ColorFilter.mode(
                                    Colors.white,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom bar - Column yapısı için (Positioned değil)
  Widget _buildBottomBarRow() {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewPadding.bottom + 16,
      ),
      decoration: const BoxDecoration(color: Colors.black),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildGalleryButton(),
          if (!_isLayoutMode) _buildModeSelector(),
          if (_isLayoutMode) const SizedBox(width: 40),
          _buildIconButton(
            iconWidget: SvgPicture.asset(
              'packages/story_editor_pro/assets/icons/refresh-double.svg',
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(
                _isProcessingVideo || _isVideoRecording
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.white,
                BlendMode.srcIn,
              ),
            ),
            onTap: _isProcessingVideo || _isVideoRecording
                ? null
                : _switchCamera,
          ),
        ],
      ),
    );
  }

  /// Eski _buildBottomBar - Layout mode için hala kullanılıyor
  Widget _buildBottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewPadding.bottom + 16,
        ),
        decoration: const BoxDecoration(color: Colors.black),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildGalleryButton(),
            // Layout modunda mode selector'ı gizle
            if (!_isLayoutMode) _buildModeSelector(),
            // Layout modunda boşluk için SizedBox
            if (_isLayoutMode) const SizedBox(width: 40),
            _buildIconButton(
              iconWidget: SvgPicture.asset(
                'packages/story_editor_pro/assets/icons/refresh-double.svg',
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  _isProcessingVideo || _isVideoRecording
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.white,
                  BlendMode.srcIn,
                ),
              ),
              onTap: _isProcessingVideo || _isVideoRecording
                  ? null
                  : _switchCamera,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryButton() {
    final hasThumbnail = _hasGalleryPermission && _lastGalleryThumbnail != null;
    final isDisabled = _isProcessingVideo || _isVideoRecording;

    // %30 küçültülmüş boyutlar: 56->40, 48->34, 8->6, 2->1.5, 24->17, 20->14, 10->7
    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: GestureDetector(
        onTap: isDisabled
            ? null
            : () {
                // Layout modunda aktif tile'a galeri resmi seç
                if (_isLayoutMode) {
                  _pickImageForLayoutTile(_activeLayoutIndex);
                } else {
                  _openGallery();
                }
              },
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            children: [
              // Ana galeri kutusu - beyaz border ile
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white, width: 1.5),
                  color: hasThumbnail ? null : Colors.white10,
                ),
                child: hasThumbnail
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.memory(
                          _lastGalleryThumbnail!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: SvgPicture.asset(
                                'packages/story_editor_pro/assets/icons/media-image-folder.svg',
                                width: 17,
                                height: 17,
                                colorFilter: const ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    : Center(
                        child: SvgPicture.asset(
                          'packages/story_editor_pro/assets/icons/media-image-folder.svg',
                          width: 17,
                          height: 17,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
              ),
              // Sağ alt köşede artı simgesi
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      'packages/story_editor_pro/assets/icons/plus.svg',
                      width: 7,
                      height: 7,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return SizedBox(
      height: 40,
      child: Center(
        child: Text(
          'Story',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    IconData? icon,
    Widget? iconWidget,
    VoidCallback? onTap,
    double size = 44,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.15),
        ),
        child: Center(
          child: iconWidget ?? Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildZoomIndicator() {
    return Positioned(
      top: 100,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${_zoomLevel.toStringAsFixed(1)}x',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }

  /// Sağ (veya sol) taraftaki araç butonları - Positioned olarak döner
  /// Eski _buildSideTools - Layout mode için hala kullanılıyor
  Widget _buildSideTools() {
    return Positioned(
      right: _toolsOnLeft ? null : 16,
      left: _toolsOnLeft ? 16 : null,
      top: 0,
      bottom: 120,
      child: IgnorePointer(
        ignoring: _isProcessingVideo,
        child: Opacity(
          opacity: _isProcessingVideo ? 0.5 : 1.0,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBoomerangButton(),
                const SizedBox(height: 16),
                _buildCreateModeButton(),
                const SizedBox(height: 16),
                _buildCollageButton(),
                const SizedBox(height: 16),
                _buildHandsFreeButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Sağ taraftaki araç butonları - Column yapısı için
  Widget _buildSideToolsColumn() {
    final screenHeight = MediaQuery.of(context).size.height;
    // Küçük ekranlarda daha az boşluk, büyük ekranlarda daha fazla
    final bottomOffset = screenHeight * 0.15; // Ekranın %15'i
    final itemSpacing = screenHeight < 700 ? 8.0 : 16.0; // Küçük ekranda 8, büyükte 16

    return Positioned(
      right: _toolsOnLeft ? null : 16,
      left: _toolsOnLeft ? 16 : null,
      top: 0,
      bottom: bottomOffset,
      child: IgnorePointer(
        ignoring: _isProcessingVideo,
        child: Opacity(
          opacity: _isProcessingVideo ? 0.5 : 1.0,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBoomerangButton(),
                SizedBox(height: itemSpacing),
                _buildCreateModeButton(),
                SizedBox(height: itemSpacing),
                _buildCollageButton(),
                SizedBox(height: itemSpacing),
                _buildHandsFreeButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Boomerang butonu
  Widget _buildBoomerangButton() {
    // Instagram Boomerang gradient
    const boomerangGradient = LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [
        Color(0xFFF77737), // Turuncu
        Color(0xFFE1306C), // Pembe
        Color(0xFFC13584), // Koyu pembe
      ],
    );

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _isBoomerangMode = !_isBoomerangMode;
          // Boomerang açılırsa diğer modları kapat
          if (_isBoomerangMode) {
            _isLayoutMode = false;
            _showLayoutSelector = false;
            _isHandsFreeMode = false;
            _showHandsFreeSelector = false;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: _isBoomerangMode
            ? BoxDecoration(shape: BoxShape.circle, gradient: boomerangGradient)
            : BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.15),
              ),
        child: SvgPicture.asset(
          'packages/story_editor_pro/assets/icons/infinite.svg',
          width: 24,
          height: 24,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      ),
    );
  }

  /// Create Mode (Gradient Text Editor) butonu
  Widget _buildCreateModeButton() {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.selectionClick();
        // Gradient Text Editor'ı aç
        await openGradientTextEditor(
          context,
          onComplete: (text, gradient) async {
            debugPrint('Create Mode: onComplete called with text: $text');

            // Sadece gradient arka plan görseli oluştur (yazısız)
            final bgImagePath = await _createGradientBackground(gradient);

            if (bgImagePath != null && mounted) {
              final screenSize = MediaQuery.of(context).size;
              await Navigator.push<Map<String, dynamic>?>(
                context,
                MaterialPageRoute(
                  builder: (ctx) => StoryEditorScreen(
                    imagePath: bgImagePath,
                    primaryColor: widget.primaryColor,
                    closeFriendsList: widget.closeFriendsList,
                    onShare: widget.onStoryShare,
                    // Yazıyı TextOverlay olarak gönder (taşınabilir, düzenlenebilir)
                    initialTextOverlay: TextOverlay(
                      text: text,
                      color: Colors.white,
                      fontSize: 32,
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      offset: Offset(
                        screenSize.width / 2 - 80,
                        screenSize.height / 2 - 30,
                      ),
                    ),
                  ),
                ),
              );
              // onStoryShare callback is called from StoryEditorScreen
            }
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.15),
        ),
        child: const Icon(Icons.text_fields, color: Colors.white, size: 24),
      ),
    );
  }

  /// Hands-free butonu - tıklandığında aşağı doğru genişleyerek süre seçenekleri gösterir
  Widget _buildHandsFreeButton() {
    // Süre seçenekleri (saniye)
    const List<int> delayOptions = [3, 5, 10, 15];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: _showHandsFreeSelector
            ? BorderRadius.circular(24)
            : BorderRadius.circular(100),
        color: _isHandsFreeMode
            ? Colors.white.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.15),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ana hands-free butonu (her zaman görünür)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (!_isHandsFreeMode) {
                  // Hands-free modunu ve selector'ü aç
                  _isHandsFreeMode = true;
                  _showHandsFreeSelector = true;
                  _isBoomerangMode = false;
                  _isLayoutMode = false;
                  _showLayoutSelector = false;
                } else {
                  // Mod aktifken tıklayınca her şeyi kapat (normal moda dön)
                  _isHandsFreeMode = false;
                  _showHandsFreeSelector = false;
                }
              });
            },
            child: SvgPicture.asset(
              'packages/story_editor_pro/assets/icons/hand-free.svg',
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),

          // Süre seçenekleri (aşağı doğru açılır)
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: _showHandsFreeSelector
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      ...delayOptions.map((seconds) {
                        final isSelected = _handsFreeDelaySeconds == seconds;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _handsFreeDelaySeconds = seconds;
                            });
                            // Sadece süreyi seç, butona basınca başlayacak
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.3)
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white60,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '$seconds',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white60,
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Collage butonu - tıklandığında aşağı doğru genişleyerek layout seçenekleri gösterir
  Widget _buildCollageButton() {
    // Layout SVG ikon yolları
    const Map<LayoutType, String> layoutIcons = {
      LayoutType.twoVertical:
          'packages/story_editor_pro/assets/icons/collage-frame-two-horizontal.svg',
      LayoutType.twoHorizontal:
          'packages/story_editor_pro/assets/icons/collage-frame-two-vertical.svg',
      LayoutType.fourGrid:
          'packages/story_editor_pro/assets/icons/collage-frame-four.svg',
      LayoutType.sixGrid:
          'packages/story_editor_pro/assets/icons/collage-frame-six.svg',
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: _showLayoutSelector
            ? BorderRadius.circular(24)
            : BorderRadius.circular(100),
        color: _isLayoutMode
            ? Colors.white.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.15),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ana collage butonu (her zaman görünür)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (!_isLayoutMode) {
                  // Layout modunu ve selector'ü aç
                  _isLayoutMode = true;
                  _showLayoutSelector = true;
                  _isBoomerangMode = false;
                  _isHandsFreeMode = false;
                  _showHandsFreeSelector = false;
                  _capturedLayoutPhotos = List.filled(
                    _selectedLayout.photoCount,
                    null,
                  );
                  _activeLayoutIndex = 0;
                } else if (_showLayoutSelector) {
                  // Selector açıkken tıklayınca modu kapat
                  _isLayoutMode = false;
                  _showLayoutSelector = false;
                  _capturedLayoutPhotos = [];
                  _activeLayoutIndex = 0;
                } else {
                  // Selector kapalıyken tıklayınca selector'ü aç
                  _showLayoutSelector = true;
                }
              });
            },
            onLongPress: () {
              // Uzun basınca layout modunu kapat
              if (_isLayoutMode) {
                HapticFeedback.mediumImpact();
                setState(() {
                  _isLayoutMode = false;
                  _showLayoutSelector = false;
                  _capturedLayoutPhotos = [];
                  _activeLayoutIndex = 0;
                });
              }
            },
            child: SvgPicture.asset(
              'packages/story_editor_pro/assets/icons/collage-frame.svg',
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),

          // Layout seçenekleri (aşağı doğru açılır)
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: _showLayoutSelector
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      ...LayoutType.values.map((layout) {
                        final isSelected = _selectedLayout == layout;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedLayout = layout;
                              _capturedLayoutPhotos = List.filled(
                                layout.photoCount,
                                null,
                              );
                              _activeLayoutIndex = 0;
                            });
                          },
                          child: Container(
                            width: 24,
                            height: 24,
                            margin: const EdgeInsets.only(bottom: 12),
                            child: SvgPicture.asset(
                              layoutIcons[layout]!,
                              width: 24,
                              height: 24,
                              colorFilter: ColorFilter.mode(
                                isSelected ? Colors.white : Colors.white60,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Gradient ile circular progress indicator çizen CustomPainter
class _GradientCircularProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Gradient gradient;
  final Color backgroundColor;

  _GradientCircularProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.gradient,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Arka plan çemberi (beyaz, dolmamış kısım)
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Progress varsa gradient çember çiz
    if (progress > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);

      final progressPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      // -90 derece (üstten başla), progress kadar çiz
      const startAngle = -3.14159 / 2; // -90 derece (üst)
      final sweepAngle = 2 * 3.14159 * progress;

      canvas.drawArc(rect, startAngle, sweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(_GradientCircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Video kayıt için circular progress painter
class _VideoProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color progressColor;
  final Color backgroundColor;

  _VideoProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.progressColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Arka plan çemberi (beyaz, dolmamış kısım)
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Progress varsa kırmızı çember çiz
    if (progress > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);

      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      // -90 derece (üstten başla), progress kadar çiz
      const startAngle = -3.14159 / 2; // -90 derece (üst)
      final sweepAngle = 2 * 3.14159 * progress;

      canvas.drawArc(rect, startAngle, sweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(_VideoProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Galeri seçici sayfası
class _GalleryPickerPage extends StatefulWidget {
  final AssetPathEntity album;
  final int totalCount;

  const _GalleryPickerPage({required this.album, required this.totalCount});

  @override
  State<_GalleryPickerPage> createState() => _GalleryPickerPageState();
}

class _GalleryPickerPageState extends State<_GalleryPickerPage> {
  final List<AssetEntity> _assets = [];
  bool _isLoading = true;
  int _currentPage = 0;
  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    final assets = await widget.album.getAssetListPaged(
      page: _currentPage,
      size: _pageSize,
    );

    if (mounted) {
      setState(() {
        _assets.addAll(assets);
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _assets.length >= widget.totalCount) return;

    setState(() => _isLoading = true);
    _currentPage++;

    final assets = await widget.album.getAssetListPaged(
      page: _currentPage,
      size: _pageSize,
    );

    if (mounted) {
      setState(() {
        _assets.addAll(assets);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Gallery'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading && _assets.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollEndNotification &&
                    notification.metrics.extentAfter < 200) {
                  _loadMore();
                }
                return false;
              },
              child: GridView.builder(
                padding: const EdgeInsets.all(2),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: _assets.length,
                itemBuilder: (context, index) {
                  final asset = _assets[index];
                  return _GalleryThumbnail(
                    asset: asset,
                    onTap: () => Navigator.pop(context, asset),
                  );
                },
              ),
            ),
    );
  }
}

/// Galeri thumbnail widget'ı
class _GalleryThumbnail extends StatefulWidget {
  final AssetEntity asset;
  final VoidCallback onTap;

  const _GalleryThumbnail({required this.asset, required this.onTap});

  @override
  State<_GalleryThumbnail> createState() => _GalleryThumbnailState();
}

class _GalleryThumbnailState extends State<_GalleryThumbnail> {
  Uint8List? _thumbData;
  bool _loadFailed = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    try {
      final data = await widget.asset.thumbnailDataWithSize(
        const ThumbnailSize(200, 200),
        quality: 80,
      );

      if (mounted && data != null) {
        setState(() {
          _thumbData = data;
          _loadFailed = false;
        });
      } else if (mounted && _retryCount < _maxRetries) {
        // Thumbnail alınamadı, biraz bekleyip tekrar dene
        _retryCount++;
        await Future.delayed(Duration(milliseconds: 500 * _retryCount));
        if (mounted) {
          _loadThumbnail();
        }
      } else if (mounted) {
        setState(() => _loadFailed = true);
      }
    } catch (e) {
      debugPrint('Thumbnail load error: $e');
      if (mounted) {
        setState(() => _loadFailed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail
          _thumbData != null
              ? Image.memory(_thumbData!, fit: BoxFit.cover)
              : Container(
                  color: Colors.grey.shade900,
                  child: Center(
                    child: _loadFailed
                        ? const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white38,
                            size: 24,
                          )
                        : const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white54,
                            ),
                          ),
                  ),
                ),

          // Video ise süre göster
          if (widget.asset.type == AssetType.video)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow, color: Colors.white, size: 12),
                    const SizedBox(width: 2),
                    Text(
                      _formatDuration(widget.asset.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
