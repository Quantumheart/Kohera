import 'dart:io';

void main() {
  final libDir = Directory('lib');
  final files = <String>[];
  
  // Collect all Dart files
  libDir.listSync(recursive: true).where((entity) => entity is File && entity.path.endsWith('.dart')).forEach((entity) {
    files.add(entity.path);
  });
  
  print('Found ${files.length} Dart files');
  
  final borderRadiusMatches = <String>[];
  final colorMatches = <String>[];
  
  for (final file in files) {
    final content = File(file).readAsStringSync();
    
    // Find BorderRadius.circular instances
    final borderRadiusRegex = RegExp(r'BorderRadius\.circular\([^)]+\)');
    final borderRadiusFileMatches = borderRadiusRegex.allMatches(content);
    if (borderRadiusFileMatches.isNotEmpty) {
      borderRadiusMatches.add('$file: ${borderRadiusFileMatches.length} matches');
    }
    
    // Find hardcoded color values (hex colors and Color constructors)
    final colorRegex = RegExp(r'(Color\([^)]*0xFF[0-9A-F]{8}[^)]*\))|(const\s+Color\([^)]*\))|(\b0xFF[0-9A-F]{8}\b)', dotAll: true);
    final colorFileMatches = colorRegex.allMatches(content);
    if (colorFileMatches.isNotEmpty) {
      colorMatches.add('$file: ${colorFileMatches.length} matches');
      // Print the actual matches for review
      for (final match in colorFileMatches) {
        final lineNum = getLineNumber(content, match.start);
        print('  Line $lineNum: ${match.group(0)}');
      }
    }
  }
  
  print('\n=== BorderRadius.circular instances ===');
  for (final match in borderRadiusMatches) {
    print(match);
  }
  
  print('\n=== Hardcoded color values ===');
  for (final match in colorMatches) {
    print(match);
  }
}

int getLineNumber(String content, int index) {
  if (index < 0 || index >= content.length) return -1;

  var line = 1;
  for (var i = 0; i < index; i++) {
    if (content[i] == '\n') {
      line++;
    }
  }
  return line;
}
