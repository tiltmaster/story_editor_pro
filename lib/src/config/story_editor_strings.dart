/// Localization strings for Story Editor Pro
/// All strings have English defaults and can be customized for any language
///
/// Naming convention: [screenName][elementName]
/// - settings* = Camera Settings Screen
/// - camera* = Camera Screen
/// - gradient* = Gradient Text Editor
/// - editor* = Story Editor Screen
class StoryEditorStrings {
  // ============ Camera Settings Screen ============
  final String settingsTitle;
  final String settingsControlsSection;
  final String settingsFrontCameraTitle;
  final String settingsFrontCameraSubtitle;
  final String settingsToolsSection;
  final String settingsToolbarPositionTitle;
  final String settingsToolbarPositionSubtitle;
  final String settingsLeftSide;
  final String settingsRightSide;

  // ============ Camera Screen ============
  final String cameraStory;
  final String cameraGallery;
  final String cameraCancel;
  final String cameraDelete;
  final String cameraSettings;
  final String cameraPermissionRequired;
  final String cameraPermissionDescription;
  final String cameraGrantPermission;
  final String cameraGalleryAccessDenied;
  final String cameraNoMediaInGallery;
  final String cameraNoImagesInGallery;
  final String cameraCouldNotOpenGallery;
  final String cameraCouldNotTakePhoto;
  final String cameraCouldNotStartVideo;
  final String cameraCouldNotCreateCollage;
  final String cameraCouldNotCreateBoomerang;
  final String cameraBoomerangProcessingError;
  final String cameraDeletePhoto;
  final String cameraDeletePhotoConfirmation;
  final String cameraCapture;
  final String cameraStartAfter;
  final String cameraProcessingImage;
  final String cameraProcessingVideo;
  final String cameraProcessing;
  final String cameraCreatingBoomerang;
  final String cameraPhoto;
  final String cameraVideo;
  final String cameraBoomerang;
  final String cameraFilterNormal;
  final String cameraFilterVivid;
  final String cameraFilterWarm;
  final String cameraFilterCool;
  final String cameraFilterSunset;
  final String cameraFilterFade;
  final String cameraFilterMono;
  final String cameraFilterNoir;
  final String cameraFilterDream;
  final String cameraFilterVignette;
  final String cameraFilter2044;
  final String cameraFilterCinematic;
  final String cameraFilterTealOrange;
  final String cameraFilterBulge;
  final String cameraFilterSwirl;
  final String cameraFilterPortraitPop;
  final String cameraFilterNightNeon;
  final String cameraFilterProductCrisp;
  final String cameraFilterFilmicFade;
  final String cameraFilterPastelMist;

  // ============ Gradient Text Editor ============
  final String gradientBalance;
  final String gradientWriteSomething;
  final String gradientProcessingImage;

  // ============ Story Editor Screen ============
  final String editorImageSettings;
  final String editorOk;
  final String editorShare;
  final String editorCloseFriends;
  final String editorPeopleCount;
  final String editorCouldNotSave;
  final String editorYourStory;
  final String editorFacebookStory;
  final String editorEnterText;
  final String editorSaved;
  final String editorSaving;
  final String editorSharing;

  // ============ Story Editor - Brush Types ============
  final String editorBrushNormal;
  final String editorBrushArrow;
  final String editorBrushMarker;
  final String editorBrushGlow;
  final String editorBrushEraser;
  final String editorBrushChalk;

  const StoryEditorStrings({
    // ─────────────────────────────────────────────────────────────
    // Camera Settings Screen
    // ─────────────────────────────────────────────────────────────
    this.settingsTitle = 'Settings',
    this.settingsControlsSection = 'Controls',
    this.settingsFrontCameraTitle = 'Front Camera Default',
    this.settingsFrontCameraSubtitle = 'Start with front camera when app opens',
    this.settingsToolsSection = 'Camera Tools',
    this.settingsToolbarPositionTitle = 'Toolbar Position',
    this.settingsToolbarPositionSubtitle = 'Choose which side of the screen boomerang, text editor, and frame tools appear.',
    this.settingsLeftSide = 'Left Side',
    this.settingsRightSide = 'Right Side',

    // ─────────────────────────────────────────────────────────────
    // Camera Screen
    // ─────────────────────────────────────────────────────────────
    this.cameraStory = 'Story',
    this.cameraGallery = 'Gallery',
    this.cameraCancel = 'Cancel',
    this.cameraDelete = 'Delete',
    this.cameraSettings = 'Settings',
    this.cameraPermissionRequired = 'Camera Permission Required',
    this.cameraPermissionDescription = 'We need camera access to create stories.',
    this.cameraGrantPermission = 'Grant Permission',
    this.cameraGalleryAccessDenied = 'Gallery access denied',
    this.cameraNoMediaInGallery = 'No media found in gallery',
    this.cameraNoImagesInGallery = 'No images found in gallery',
    this.cameraCouldNotOpenGallery = 'Could not open gallery',
    this.cameraCouldNotTakePhoto = 'Could not take photo',
    this.cameraCouldNotStartVideo = 'Could not start video',
    this.cameraCouldNotCreateCollage = 'Could not create collage',
    this.cameraCouldNotCreateBoomerang = 'Could not create boomerang',
    this.cameraBoomerangProcessingError = 'Error processing boomerang',
    this.cameraDeletePhoto = 'Delete Photo',
    this.cameraDeletePhotoConfirmation = 'Do you want to delete this photo?',
    this.cameraCapture = 'Capture',
    this.cameraStartAfter = 'Start after',
    this.cameraProcessingImage = 'Processing image...',
    this.cameraProcessingVideo = 'Processing video...',
    this.cameraProcessing = 'Processing...',
    this.cameraCreatingBoomerang = 'Creating boomerang...',
    this.cameraPhoto = 'Photo',
    this.cameraVideo = 'Video',
    this.cameraBoomerang = 'Boomerang',
    this.cameraFilterNormal = 'Normal',
    this.cameraFilterVivid = 'Vivid',
    this.cameraFilterWarm = 'Warm',
    this.cameraFilterCool = 'Cool',
    this.cameraFilterSunset = 'Sunset',
    this.cameraFilterFade = 'Fade',
    this.cameraFilterMono = 'Mono',
    this.cameraFilterNoir = 'Noir',
    this.cameraFilterDream = 'Dream',
    this.cameraFilterVignette = 'Vignette',
    this.cameraFilter2044 = '2044',
    this.cameraFilterCinematic = 'Cinematic',
    this.cameraFilterTealOrange = 'Teal Orange',
    this.cameraFilterBulge = 'Bulge',
    this.cameraFilterSwirl = 'Swirl',
    this.cameraFilterPortraitPop = 'Portrait Pop',
    this.cameraFilterNightNeon = 'Night Neon',
    this.cameraFilterProductCrisp = 'Product Crisp',
    this.cameraFilterFilmicFade = 'Filmic Fade',
    this.cameraFilterPastelMist = 'Pastel Mist',

    // ─────────────────────────────────────────────────────────────
    // Gradient Text Editor
    // ─────────────────────────────────────────────────────────────
    this.gradientBalance = 'Balance',
    this.gradientWriteSomething = 'Write something...',
    this.gradientProcessingImage = 'Processing image...',

    // ─────────────────────────────────────────────────────────────
    // Story Editor Screen
    // ─────────────────────────────────────────────────────────────
    this.editorImageSettings = 'Image Settings',
    this.editorOk = 'OK',
    this.editorShare = 'Share',
    this.editorCloseFriends = 'Close Friends',
    this.editorPeopleCount = '0 people',
    this.editorCouldNotSave = 'Could not save',
    this.editorYourStory = 'Your Story',
    this.editorFacebookStory = 'And Facebook Story',
    this.editorEnterText = 'Enter text...',
    this.editorSaved = 'Saved',
    this.editorSaving = 'Saving...',
    this.editorSharing = 'Sharing...',

    // ─────────────────────────────────────────────────────────────
    // Story Editor - Brush Types
    // ─────────────────────────────────────────────────────────────
    this.editorBrushNormal = 'Normal',
    this.editorBrushArrow = 'Arrow',
    this.editorBrushMarker = 'Marker',
    this.editorBrushGlow = 'Glow',
    this.editorBrushEraser = 'Eraser',
    this.editorBrushChalk = 'Chalk',
  });

  /// Format capture text: "Capture: 1/4"
  String formatCaptureText(int current, int total) => '$cameraCapture: $current/$total';

  /// Format start after text: "Start after 3s"
  String formatStartAfter(int seconds) => '$cameraStartAfter ${seconds}s';

  /// Format people count: "5 people"
  String formatPeopleCount(int count) => editorPeopleCount.replaceFirst('0', '$count');

  /// Format error with details
  String formatError(String baseError, String details) => '$baseError: $details';

  String filterNameForPreset(String presetId) {
    switch (presetId) {
      case 'vivid':
        return cameraFilterVivid;
      case 'warm':
        return cameraFilterWarm;
      case 'cool':
        return cameraFilterCool;
      case 'sunset':
        return cameraFilterSunset;
      case 'fade':
        return cameraFilterFade;
      case 'mono':
        return cameraFilterMono;
      case 'noir':
        return cameraFilterNoir;
      case 'dream':
        return cameraFilterDream;
      case 'vignette':
        return cameraFilterVignette;
      case 'retro2044':
        return cameraFilter2044;
      case 'cinematic':
        return cameraFilterCinematic;
      case 'tealorange':
        return cameraFilterTealOrange;
      case 'portraitpop':
        return cameraFilterPortraitPop;
      case 'nightneon':
        return cameraFilterNightNeon;
      case 'productcrisp':
        return cameraFilterProductCrisp;
      case 'filmicfade':
        return cameraFilterFilmicFade;
      case 'pastelmist':
        return cameraFilterPastelMist;
      case 'none':
      default:
        return cameraFilterNormal;
    }
  }
}
