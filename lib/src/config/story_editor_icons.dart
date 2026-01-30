import 'package:flutter/material.dart';

/// Icon configuration for Story Editor Pro
/// Each icon can be customized with either a Widget or IconData
class StoryEditorIcons {
  // ============ Tool Bar Icons ============

  /// Custom boomerang icon widget (takes precedence over iconData)
  final Widget? boomerangIcon;

  /// Boomerang icon data (used if boomerangIcon is null)
  final IconData boomerangIconData;

  /// Boomerang icon background color
  final Color? boomerangIconBackgroundColor;

  /// Boomerang icon color
  final Color? boomerangIconColor;

  /// Custom collage/layout icon widget
  final Widget? collageIcon;

  /// Collage icon data
  final IconData collageIconData;

  /// Collage icon background color
  final Color? collageIconBackgroundColor;

  /// Collage icon color
  final Color? collageIconColor;

  /// Custom hands-free icon widget
  final Widget? handsFreeIcon;

  /// Hands-free icon data
  final IconData handsFreeIconData;

  /// Hands-free icon background color
  final Color? handsFreeIconBackgroundColor;

  /// Hands-free icon color
  final Color? handsFreeIconColor;

  /// Custom gradient text icon widget
  final Widget? gradientTextIcon;

  /// Gradient text icon data
  final IconData gradientTextIconData;

  /// Gradient text icon background color
  final Color? gradientTextIconBackgroundColor;

  /// Gradient text icon color
  final Color? gradientTextIconColor;

  // ============ Common Icons ============

  /// Close icon
  final IconData closeIcon;

  /// Check/confirm icon
  final IconData checkIcon;

  /// Undo icon
  final IconData undoIcon;

  /// Edit/draw icon
  final IconData editIcon;

  /// Text icon
  final IconData textIcon;

  // ============ Camera Icons ============

  /// Flash on icon
  final IconData flashOnIcon;

  /// Flash off icon
  final IconData flashOffIcon;

  /// Flash auto icon
  final IconData flashAutoIcon;

  /// Camera switch/flip icon
  final IconData cameraSwitchIcon;

  /// Camera icon
  final IconData cameraIcon;

  // ============ Navigation Icons ============

  /// Settings icon
  final IconData settingsIcon;

  /// Gallery icon
  final IconData galleryIcon;

  /// Arrow back icon
  final IconData arrowBackIcon;

  /// Arrow forward icon
  final IconData arrowForwardIcon;

  // ============ Media Icons ============

  /// Play icon
  final IconData playIcon;

  /// Pause icon
  final IconData pauseIcon;

  /// Broken/error image icon
  final IconData brokenImageIcon;

  // ============ Gradient Editor Direction Icons ============

  /// Direction icons for gradient editor (6 directions)
  final List<IconData> directionIcons;

  // ============ Brush Type Icons ============

  /// Normal brush icon
  final IconData brushNormalIcon;

  /// Arrow brush icon
  final IconData brushArrowIcon;

  /// Marker brush icon
  final IconData brushMarkerIcon;

  /// Glow brush icon
  final IconData brushGlowIcon;

  /// Eraser icon
  final IconData brushEraserIcon;

  /// Chalk brush icon
  final IconData brushChalkIcon;

  const StoryEditorIcons({
    // Tool Bar Icons
    this.boomerangIcon,
    this.boomerangIconData = Icons.all_inclusive,
    this.boomerangIconBackgroundColor,
    this.boomerangIconColor,
    this.collageIcon,
    this.collageIconData = Icons.grid_view,
    this.collageIconBackgroundColor,
    this.collageIconColor,
    this.handsFreeIcon,
    this.handsFreeIconData = Icons.timer,
    this.handsFreeIconBackgroundColor,
    this.handsFreeIconColor,
    this.gradientTextIcon,
    this.gradientTextIconData = Icons.text_fields,
    this.gradientTextIconBackgroundColor,
    this.gradientTextIconColor,

    // Common Icons
    this.closeIcon = Icons.close,
    this.checkIcon = Icons.check,
    this.undoIcon = Icons.undo,
    this.editIcon = Icons.edit,
    this.textIcon = Icons.text_fields,

    // Camera Icons
    this.flashOnIcon = Icons.flash_on,
    this.flashOffIcon = Icons.flash_off,
    this.flashAutoIcon = Icons.flash_auto,
    this.cameraSwitchIcon = Icons.flip_camera_ios,
    this.cameraIcon = Icons.camera_alt_outlined,

    // Navigation Icons
    this.settingsIcon = Icons.settings,
    this.galleryIcon = Icons.photo_library,
    this.arrowBackIcon = Icons.arrow_back_ios,
    this.arrowForwardIcon = Icons.arrow_forward,

    // Media Icons
    this.playIcon = Icons.play_arrow,
    this.pauseIcon = Icons.pause,
    this.brokenImageIcon = Icons.broken_image_outlined,

    // Direction Icons
    this.directionIcons = const [
      Icons.north_west,
      Icons.north,
      Icons.north_east,
      Icons.west,
      Icons.south_west,
      Icons.south,
    ],

    // Brush Type Icons
    this.brushNormalIcon = Icons.edit,
    this.brushArrowIcon = Icons.arrow_upward,
    this.brushMarkerIcon = Icons.highlight,
    this.brushGlowIcon = Icons.auto_awesome,
    this.brushEraserIcon = Icons.auto_fix_normal,
    this.brushChalkIcon = Icons.gesture,
  });
}
