import 'package:intl/intl.dart';

/// Localization strings for Story Editor Pro
/// All strings have English defaults and can be customized for any language
///
/// Naming convention: [screenName][elementName]
/// - settings* = Camera Settings Screen
/// - camera* = Camera Screen
/// - gradient* = Gradient Text Editor
/// - editor* = Story Editor Screen
class StoryEditorStrings {
  final String languageCode;
  final String cameraEffects;
  final String cameraLensLoading;
  final String cameraLensUnavailable;
  final String cameraEffectsUnavailable;
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
  final String cameraFilterGoldenHour;
  final String cameraFilterArctic;
  final String cameraFilterSepia;
  final String cameraFilterEmerald;
  final String cameraFilterRoseGold;
  final String cameraFilterMoody;
  final String cameraFilterBleach;
  final String cameraFilterVelvet;
  final String cameraFilterSoftBeauty;
  final String cameraFilterCleanGlow;
  final String cameraFilterVhs1993;
  final String cameraFilterDayTime;
  final String cameraFilterTimeFocus;
  final String cameraFilterKuwaitGold;
  final String cameraFilterRetroDate;
  final String cameraLensClassicGlasses;
  final String cameraLensClassicGlassesArabic;

  // Legacy host-app localization inputs retained for source compatibility.
  // These labels do not add presets; native mesh lenses use the dedicated
  // cameraLens* fields above.
  final String cameraFilterArGolden;
  final String cameraFilterArFrost;
  final String cameraFilterArNeon;
  final String cameraFilterArNoir;
  final String cameraFilterArPrism;
  final String cameraFilterArRetro;
  final String cameraFilterArStargaze;
  final String cameraFilterArGlasses;
  final String cameraGlassesPhotoOnly;

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
  final String editorClose;
  final String editorMuteAudio;
  final String editorUnmuteAudio;
  final String editorUndo;
  final String editorDraw;
  final String editorAddText;
  final String editorSmartTags;
  final String editorSave;
  final String editorPublish;
  final String editorDeleteLayer;
  final String editorDone;
  final String editorCancel;
  final String editorApply;
  final String editorTrimVideo;
  final String editorAddMusic;
  final String editorChangeMusic;

  // ============ Story Editor - Smart Tags ============
  final String editorSmartSection;
  final String editorStickersSection;
  final String editorEmojiSection;
  final String editorSearchStickers;
  final String editorAllEmoji;
  final String editorLocation;
  final String editorLocating;
  final String editorEnterLocation;
  final String editorAdd;
  final String editorGreeting;
  final String editorTime;
  final String editorDate;
  final String editorDay;
  final String editorBattery;

  // ============ Story Editor - Brush Types ============
  final String editorBrushNormal;
  final String editorBrushArrow;
  final String editorBrushMarker;
  final String editorBrushGlow;
  final String editorBrushEraser;
  final String editorBrushChalk;

  const StoryEditorStrings({
    this.languageCode = 'en',
    this.cameraEffects = 'Effects',
    this.cameraLensLoading = 'Loading lens…',
    this.cameraLensUnavailable = 'Lens unavailable',
    this.cameraEffectsUnavailable =
        'Could not apply the effects. Try another effect.',
    // ─────────────────────────────────────────────────────────────
    // Camera Settings Screen
    // ─────────────────────────────────────────────────────────────
    this.settingsTitle = 'Settings',
    this.settingsControlsSection = 'Controls',
    this.settingsFrontCameraTitle = 'Front Camera Default',
    this.settingsFrontCameraSubtitle = 'Start with front camera when app opens',
    this.settingsToolsSection = 'Camera Tools',
    this.settingsToolbarPositionTitle = 'Toolbar Position',
    this.settingsToolbarPositionSubtitle =
        'Choose which side of the screen boomerang, text editor, and frame tools appear.',
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
    this.cameraPermissionDescription =
        'We need camera access to create stories.',
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
    this.cameraFilterGoldenHour = 'Golden Hour',
    this.cameraFilterArctic = 'Arctic',
    this.cameraFilterSepia = 'Sepia',
    this.cameraFilterEmerald = 'Emerald',
    this.cameraFilterRoseGold = 'Rose Gold',
    this.cameraFilterMoody = 'Moody',
    this.cameraFilterBleach = 'Bleach',
    this.cameraFilterVelvet = 'Velvet',
    this.cameraFilterSoftBeauty = 'Soft Beauty',
    this.cameraFilterCleanGlow = 'Clean Glow',
    this.cameraFilterVhs1993 = 'Analog Tape',
    this.cameraFilterDayTime = 'Golden Bloom',
    this.cameraFilterTimeFocus = 'Studio Glow',
    this.cameraFilterKuwaitGold = 'Desert Luxe',
    this.cameraFilterRetroDate = 'Film Aura',
    this.cameraLensClassicGlasses = 'Classic Glasses',
    this.cameraLensClassicGlassesArabic = 'نظارات كلاسيكية',
    this.cameraFilterArGolden = 'Golden',
    this.cameraFilterArFrost = 'Frost',
    this.cameraFilterArNeon = 'Neon',
    this.cameraFilterArNoir = 'Noir',
    this.cameraFilterArPrism = 'Prism',
    this.cameraFilterArRetro = 'Retro',
    this.cameraFilterArStargaze = 'Stargaze',
    this.cameraFilterArGlasses = 'Glasses',
    this.cameraGlassesPhotoOnly = 'Available for photos only',

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
    this.editorClose = 'Close editor',
    this.editorMuteAudio = 'Mute audio',
    this.editorUnmuteAudio = 'Unmute audio',
    this.editorUndo = 'Undo',
    this.editorDraw = 'Draw',
    this.editorAddText = 'Add text',
    this.editorSmartTags = 'Smart tags',
    this.editorSave = 'Save',
    this.editorPublish = 'Continue',
    this.editorDeleteLayer = 'Delete layer',
    this.editorDone = 'Done',
    this.editorCancel = 'Cancel',
    this.editorApply = 'Apply',
    this.editorTrimVideo = 'Trim video',
    this.editorAddMusic = 'Add music',
    this.editorChangeMusic = 'Change music',

    // ─────────────────────────────────────────────────────────────
    // Story Editor - Smart Tags
    // ─────────────────────────────────────────────────────────────
    this.editorSmartSection = 'Smart tags',
    this.editorStickersSection = 'Stickers',
    this.editorEmojiSection = 'Emoji',
    this.editorSearchStickers = 'Search stickers...',
    this.editorAllEmoji = 'All',
    this.editorLocation = 'Location',
    this.editorLocating = 'Finding area...',
    this.editorEnterLocation = 'Enter an area or place',
    this.editorAdd = 'Add',
    this.editorGreeting = 'Greeting',
    this.editorTime = 'Time',
    this.editorDate = 'Date',
    this.editorDay = 'Day',
    this.editorBattery = 'Battery',

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

  /// Built-in Arabic copy for the camera, settings, editor and filter catalog.
  const StoryEditorStrings.arabic()
    : this(
        languageCode: 'ar',
        cameraEffects: 'التأثيرات',
        cameraLensLoading: 'جارٍ تحميل العدسة…',
        cameraLensUnavailable: 'العدسة غير متاحة',
        cameraEffectsUnavailable: 'تعذّر تطبيق التأثيرات. جرّب تأثيراً آخر.',
        settingsTitle: 'الإعدادات',
        settingsControlsSection: 'عناصر التحكم',
        settingsFrontCameraTitle: 'الكاميرا الأمامية افتراضياً',
        settingsFrontCameraSubtitle: 'ابدأ بالكاميرا الأمامية عند فتح التطبيق',
        settingsToolsSection: 'أدوات الكاميرا',
        settingsToolbarPositionTitle: 'موضع شريط الأدوات',
        settingsToolbarPositionSubtitle:
            'اختر جانب الشاشة الذي تظهر فيه أدوات بوميرانغ والنص والإطارات.',
        settingsLeftSide: 'الجانب الأيسر',
        settingsRightSide: 'الجانب الأيمن',
        cameraStory: 'قصة',
        cameraGallery: 'المعرض',
        cameraCancel: 'إلغاء',
        cameraDelete: 'حذف',
        cameraSettings: 'الإعدادات',
        cameraPermissionRequired: 'يلزم السماح باستخدام الكاميرا',
        cameraPermissionDescription: 'نحتاج إلى إذن الكاميرا لإنشاء القصص.',
        cameraGrantPermission: 'السماح',
        cameraGalleryAccessDenied: 'لم يُسمح بالوصول إلى المعرض',
        cameraNoMediaInGallery: 'لا توجد وسائط في المعرض',
        cameraNoImagesInGallery: 'لا توجد صور في المعرض',
        cameraCouldNotOpenGallery: 'تعذّر فتح المعرض',
        cameraCouldNotTakePhoto: 'تعذّر التقاط الصورة',
        cameraCouldNotStartVideo: 'تعذّر بدء تسجيل الفيديو',
        cameraCouldNotCreateCollage: 'تعذّر تجميع الصور',
        cameraCouldNotCreateBoomerang: 'تعذّر إنشاء بوميرانغ',
        cameraBoomerangProcessingError: 'تعذّرت معالجة بوميرانغ',
        cameraDeletePhoto: 'حذف الصورة',
        cameraDeletePhotoConfirmation: 'هل تريد حذف هذه الصورة؟',
        cameraCapture: 'التقاط',
        cameraStartAfter: 'البدء بعد',
        cameraProcessingImage: 'جارٍ معالجة الصورة…',
        cameraProcessingVideo: 'جارٍ معالجة الفيديو…',
        cameraProcessing: 'جارٍ المعالجة…',
        cameraCreatingBoomerang: 'جارٍ إنشاء بوميرانغ…',
        cameraPhoto: 'صورة',
        cameraVideo: 'فيديو',
        cameraBoomerang: 'بوميرانغ',
        cameraFilterNormal: 'طبيعي',
        cameraFilterVivid: 'زاهٍ',
        cameraFilterWarm: 'دافئ',
        cameraFilterCool: 'بارد',
        cameraFilterSunset: 'غروب',
        cameraFilterFade: 'باهت',
        cameraFilterMono: 'أحادي اللون',
        cameraFilterNoir: 'أسود كلاسيكي',
        cameraFilterDream: 'حلم',
        cameraFilterVignette: 'حواف مظللة',
        cameraFilter2044: '٢٠٤٤',
        cameraFilterCinematic: 'سينمائي',
        cameraFilterTealOrange: 'فيروزي وبرتقالي',
        cameraFilterBulge: 'انتفاخ',
        cameraFilterSwirl: 'دوامة',
        cameraFilterPortraitPop: 'بورتريه زاهٍ',
        cameraFilterNightNeon: 'نيون ليلي',
        cameraFilterProductCrisp: 'وضوح',
        cameraFilterFilmicFade: 'فيلم باهت',
        cameraFilterPastelMist: 'ضباب باستيل',
        cameraFilterGoldenHour: 'الساعة الذهبية',
        cameraFilterArctic: 'قطبي',
        cameraFilterSepia: 'بني عتيق',
        cameraFilterEmerald: 'زمردي',
        cameraFilterRoseGold: 'ذهبي وردي',
        cameraFilterMoody: 'درامي',
        cameraFilterBleach: 'فضي باهت',
        cameraFilterVelvet: 'مخملي',
        cameraFilterSoftBeauty: 'جمال ناعم',
        cameraFilterCleanGlow: 'إشراقة نقية',
        cameraFilterVhs1993: 'تسجيل عتيق',
        cameraFilterDayTime: 'توهّج ذهبي',
        cameraFilterTimeFocus: 'إضاءة الاستوديو',
        cameraFilterKuwaitGold: 'سحر الصحراء',
        cameraFilterRetroDate: 'هالة الفيلم',
        cameraLensClassicGlasses: 'نظارات كلاسيكية',
        cameraFilterArGolden: 'ذهبي',
        cameraFilterArFrost: 'صقيع',
        cameraFilterArNeon: 'نيون',
        cameraFilterArNoir: 'أسود كلاسيكي',
        cameraFilterArPrism: 'منشور',
        cameraFilterArRetro: 'عتيق',
        cameraFilterArStargaze: 'نجوم',
        cameraFilterArGlasses: 'نظارات',
        cameraGlassesPhotoOnly: 'متاح للصور فقط',
        gradientBalance: 'التوازن',
        gradientWriteSomething: 'اكتب شيئاً…',
        gradientProcessingImage: 'جارٍ معالجة الصورة…',
        editorImageSettings: 'إعدادات الصورة',
        editorOk: 'موافق',
        editorShare: 'مشاركة',
        editorCloseFriends: 'الأصدقاء المقرّبون',
        editorPeopleCount: 'عدد الأشخاص: 0',
        editorCouldNotSave: 'تعذّر الحفظ',
        editorYourStory: 'قصتك',
        editorFacebookStory: 'وقصة فيسبوك',
        editorEnterText: 'أدخل النص…',
        editorSaved: 'تم الحفظ',
        editorSaving: 'جارٍ الحفظ…',
        editorSharing: 'جارٍ المشاركة…',
        editorClose: 'إغلاق المحرر',
        editorMuteAudio: 'كتم الصوت',
        editorUnmuteAudio: 'تشغيل الصوت',
        editorUndo: 'تراجع',
        editorDraw: 'رسم',
        editorAddText: 'إضافة نص',
        editorSmartTags: 'ملصقات ذكية',
        editorSave: 'حفظ',
        editorPublish: 'متابعة',
        editorDeleteLayer: 'حذف الطبقة',
        editorDone: 'تم',
        editorCancel: 'إلغاء',
        editorApply: 'تطبيق',
        editorTrimVideo: 'قص الفيديو',
        editorAddMusic: 'إضافة موسيقى',
        editorChangeMusic: 'تغيير الموسيقى',
        editorSmartSection: 'ملصقات ذكية',
        editorStickersSection: 'ملصقات',
        editorEmojiSection: 'رموز تعبيرية',
        editorSearchStickers: 'ابحث عن ملصقات…',
        editorAllEmoji: 'الكل',
        editorLocation: 'الموقع',
        editorLocating: 'جارٍ تحديد المنطقة…',
        editorEnterLocation: 'أدخل منطقة أو مكاناً',
        editorAdd: 'إضافة',
        editorGreeting: 'تحية',
        editorTime: 'الوقت',
        editorDate: 'التاريخ',
        editorDay: 'اليوم',
        editorBattery: 'البطارية',
        editorBrushNormal: 'عادي',
        editorBrushArrow: 'سهم',
        editorBrushMarker: 'قلم تحديد',
        editorBrushGlow: 'توهّج',
        editorBrushEraser: 'ممحاة',
        editorBrushChalk: 'طباشير',
      );

  /// Format capture text: "Capture: 1/4"
  String formatCaptureText(int current, int total) =>
      '$cameraCapture: ${_number(current)}/${_number(total)}';

  /// Format start after text: "Start after 3s"
  String formatStartAfter(int seconds) =>
      '$cameraStartAfter ${_number(seconds)}${languageCode == 'ar' ? ' ث' : 's'}';

  /// Format people count: "5 people"
  String formatPeopleCount(int count) =>
      editorPeopleCount.replaceFirst('0', _number(count));

  String _number(int value) =>
      NumberFormat.decimalPattern(languageCode).format(value);

  String cameraEffectsLabel(int count) =>
      '$cameraEffects${count > 0 ? ' · ${_number(count)}' : ''}';

  /// Format error with details
  String formatError(String baseError, String details) =>
      '$baseError: $details';

  String filterNameForPreset(String presetId, {String languageCode = 'en'}) {
    switch (presetId) {
      case 'glasses_classic':
        return languageCode.toLowerCase().startsWith('ar')
            ? cameraLensClassicGlassesArabic
            : cameraLensClassicGlasses;
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
      case 'goldenhour':
        return cameraFilterGoldenHour;
      case 'arctic':
        return cameraFilterArctic;
      case 'sepia':
        return cameraFilterSepia;
      case 'emerald':
        return cameraFilterEmerald;
      case 'rosegold':
        return cameraFilterRoseGold;
      case 'moody':
        return cameraFilterMoody;
      case 'bleach':
        return cameraFilterBleach;
      case 'velvet':
        return cameraFilterVelvet;
      case 'softbeauty':
        return cameraFilterSoftBeauty;
      case 'cleanglow':
        return cameraFilterCleanGlow;
      case 'vhs1993':
        return cameraFilterVhs1993;
      case 'daytime':
        return cameraFilterDayTime;
      case 'timefocus':
        return cameraFilterTimeFocus;
      case 'kuwaitgold':
        return cameraFilterKuwaitGold;
      case 'retrodate':
        return cameraFilterRetroDate;
      case 'none':
      default:
        return cameraFilterNormal;
    }
  }
}
