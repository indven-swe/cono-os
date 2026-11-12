import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  const int size = 1024;
  final black = img.ColorRgba8(0, 0, 0, 255);
  final white = img.ColorRgba8(255, 255, 255, 255);
  final clear = img.ColorRgba8(0, 0, 0, 0);

  img.Image mark(img.Image im, img.Color hole) {
    img.fillCircle(im, x: 512, y: 512, radius: 300, color: white);
    img.fillCircle(im, x: 512, y: 512, radius: 200, color: hole);
    img.fillRect(im, x1: 512, y1: 396, x2: 860, y2: 628, color: hole);
    return im;
  }

  final icon = img.Image(width: size, height: size, numChannels: 4);
  img.fill(icon, color: black);
  mark(icon, black);

  final fg = img.Image(width: size, height: size, numChannels: 4);
  img.fill(fg, color: clear);
  mark(fg, clear);

  Directory('assets/icon').createSync(recursive: true);
  File('assets/icon/icon.png').writeAsBytesSync(img.encodePng(icon));
  File('assets/icon/foreground.png').writeAsBytesSync(img.encodePng(fg));
  stdout.writeln('Cono icons written to assets/icon/');
}
