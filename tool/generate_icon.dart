// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:io';
import 'package:image/image.dart' as img;

/// Generates a simple CodeLedger app icon:
/// Teal background with a white clock/receipt symbol.
void main() {
  const size = 1024;
  final image = img.Image(width: size, height: size);

  // Fill background with teal (#00897B)
  final bg = img.ColorRgba8(0, 137, 123, 255);
  img.fill(image, color: bg);

  // Draw a white rounded rectangle in the center (receipt shape)
  final white = img.ColorRgba8(255, 255, 255, 255);
  _drawRoundedRect(image, 300, 180, 724, 844, 40, white);

  // Draw horizontal lines on the receipt
  final teal = img.ColorRgba8(0, 137, 123, 255);
  for (var y = 340; y <= 700; y += 90) {
    _drawFilledRect(image, 380, y, 644, y + 12, teal);
  }

  // Draw a small circle (clock face) at top-left of receipt
  _drawFilledCircle(image, 420, 250, 40, teal);

  // Save as PNG
  final pngBytes = img.encodePng(image);
  final outputPath = 'assets/images/app_icon.png';
  File(outputPath).writeAsBytesSync(pngBytes);
  print('Icon saved to $outputPath (${pngBytes.length} bytes)');

  // Also create foreground-only version for adaptive icon
  final fgImage = img.Image(width: size, height: size);
  img.fill(fgImage, color: img.ColorRgba8(0, 0, 0, 0)); // transparent bg

  // White receipt shape
  _drawRoundedRect(fgImage, 300, 180, 724, 844, 40, white);
  // Lines
  final dark = img.ColorRgba8(0, 137, 123, 255);
  for (var y = 340; y <= 700; y += 90) {
    _drawFilledRect(fgImage, 380, y, 644, y + 12, dark);
  }
  _drawFilledCircle(fgImage, 420, 250, 40, dark);

  final fgBytes = img.encodePng(fgImage);
  final fgPath = 'assets/images/app_icon_foreground.png';
  File(fgPath).writeAsBytesSync(fgBytes);
  print('Foreground saved to $fgPath (${fgBytes.length} bytes)');
}

void _drawFilledRect(
    img.Image image, int x1, int y1, int x2, int y2, img.Color color) {
  for (var y = y1; y <= y2; y++) {
    for (var x = x1; x <= x2; x++) {
      image.setPixel(x, y, color);
    }
  }
}

void _drawRoundedRect(img.Image image, int x1, int y1, int x2, int y2,
    int radius, img.Color color) {
  // Fill main body
  _drawFilledRect(image, x1 + radius, y1, x2 - radius, y2, color);
  _drawFilledRect(image, x1, y1 + radius, x2, y2 - radius, color);

  // Fill corners
  _drawFilledCircle(image, x1 + radius, y1 + radius, radius, color);
  _drawFilledCircle(image, x2 - radius, y1 + radius, radius, color);
  _drawFilledCircle(image, x1 + radius, y2 - radius, radius, color);
  _drawFilledCircle(image, x2 - radius, y2 - radius, radius, color);
}

void _drawFilledCircle(
    img.Image image, int cx, int cy, int radius, img.Color color) {
  for (var y = -radius; y <= radius; y++) {
    for (var x = -radius; x <= radius; x++) {
      if (x * x + y * y <= radius * radius) {
        final px = cx + x;
        final py = cy + y;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, color);
        }
      }
    }
  }
}
