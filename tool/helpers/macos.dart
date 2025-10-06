import 'dart:io';

import 'util.dart';

Future<void> macos(String outputDirPath) async {
  // Create deep directory structure for macOS compatibility
  final arm64Dir = Directory(join(outputDirPath, "macos", "arm64"));
  final x86_64Dir = Directory(join(outputDirPath, "macos", "x86_64"));
  final universalDir = Directory(join(outputDirPath, "macos", "universal"));

  await arm64Dir.create(recursive: true);
  await x86_64Dir.create(recursive: true);
  await universalDir.create(recursive: true);

  // Build for ARM64
  await runAsync(
    "go",
    [
      "build",
      "-o",
      join(arm64Dir.path, "libmwebd.dylib"),
      "-buildmode=c-shared",
      ".",
    ],
    environment: {"CGO_ENABLED": "1", "GOARCH": "arm64"},
  );
  await createFramework(
    frameworkName: "flutter_mwebd",
    pathToDylib: join(arm64Dir.path, "libmwebd.dylib"),
    targetDirFrameworks: arm64Dir.path,
  );

  // Build for x86_64
  await runAsync(
    "go",
    [
      "build",
      "-o",
      join(x86_64Dir.path, "libmwebd.dylib"),
      "-buildmode=c-shared",
      ".",
    ],
    environment: {"CGO_ENABLED": "1", "GOARCH": "amd64"},
  );
  await createFramework(
    frameworkName: "flutter_mwebd",
    pathToDylib: join(x86_64Dir.path, "libmwebd.dylib"),
    targetDirFrameworks: x86_64Dir.path,
  );

  // Create universal framework
  await createUniversalFramework(
    frameworkName: "flutter_mwebd",
    arm64FrameworkPath: join(arm64Dir.path, "flutter_mwebd.framework"),
    x86_64FrameworkPath: join(x86_64Dir.path, "flutter_mwebd.framework"),
    universalFrameworkPath: join(universalDir.path, "flutter_mwebd.framework"),
  );
}

Future<void> createFramework({
  required String frameworkName,
  required String pathToDylib,
  required String targetDirFrameworks,
}) async {
  // Create the framework directory with deep bundle structure
  final frameworkDir = Directory(
    join(targetDirFrameworks, "$frameworkName.framework"),
  );
  await frameworkDir.create(recursive: true);

  // Create Versions directory structure
  final versionsDir = Directory(join(frameworkDir.path, "Versions", "A"));
  await versionsDir.create(recursive: true);

  // Create symlinks for deep bundle structure
  final currentLink = join(frameworkDir.path, "Versions", "Current");
  final resourcesDir = Directory(join(versionsDir.path, "Resources"));
  await resourcesDir.create(recursive: true);

  // Change directory to the framework directory and run commands
  final temp = Directory.current;
  Directory.current = frameworkDir;

  // Create the binary in Versions/A/
  await runAsync("lipo", [
    "-create",
    pathToDylib,
    "-output",
    join(versionsDir.path, frameworkName),
  ]);
  await runAsync("install_name_tool", [
    "-id",
    join("@rpath", join("$frameworkName.framework", "Versions", "A"), frameworkName),
    join(versionsDir.path, frameworkName),
  ]);

  // Create Info.plist in Versions/A/Resources/
  final plistFile = File(join(resourcesDir.path, "Info.plist"));
  await plistFile.writeAsString(_macPlist(frameworkName));

  // Create symlinks for deep bundle compatibility
  await runAsync("ln", ["-sf", "A", currentLink]);
  await runAsync("ln", ["-sf", join("Versions", "Current", frameworkName), join(frameworkDir.path, frameworkName)]);
  await runAsync("ln", ["-sf", join("Versions", "Current", "Resources"), join(frameworkDir.path, "Resources")]);

  Directory.current = temp;

  l("Framework $frameworkName created successfully in ${frameworkDir.path}");
}

Future<void> createUniversalFramework({
  required String frameworkName,
  required String arm64FrameworkPath,
  required String x86_64FrameworkPath,
  required String universalFrameworkPath,
}) async {
  // Create the universal framework directory with deep bundle structure
  final universalFrameworkDir = Directory(universalFrameworkPath);
  await universalFrameworkDir.create(recursive: true);

  // Create Versions directory structure
  final versionsDir = Directory(join(universalFrameworkDir.path, "Versions", "A"));
  await versionsDir.create(recursive: true);
  final resourcesDir = Directory(join(versionsDir.path, "Resources"));
  await resourcesDir.create(recursive: true);

  // Copy Info.plist from ARM64 framework to deep bundle structure
  final arm64InfoPlist = File(join(join(arm64FrameworkPath, "Versions", "A", "Resources"), "Info.plist"));
  final universalInfoPlist = File(join(resourcesDir.path, "Info.plist"));
  await arm64InfoPlist.copy(universalInfoPlist.path);

  // Create universal binary using lipo in Versions/A/
  final arm64Binary = join(join(arm64FrameworkPath, "Versions", "A"), frameworkName);
  final x86_64Binary = join(join(x86_64FrameworkPath, "Versions", "A"), frameworkName);
  final universalBinary = join(versionsDir.path, frameworkName);

  await runAsync("lipo", [
    "-create",
    arm64Binary,
    x86_64Binary,
    "-output",
    universalBinary,
  ]);

  // Update the install name for the universal binary
  await runAsync("install_name_tool", [
    "-id",
    join("@rpath", join("$frameworkName.framework", "Versions", "A"), frameworkName),
    universalBinary,
  ]);

  // Create symlinks for deep bundle compatibility
  final currentLink = join(universalFrameworkDir.path, "Versions", "Current");
  await runAsync("ln", ["-sf", "A", currentLink]);
  await runAsync("ln", ["-sf", join("Versions", "Current", frameworkName), join(universalFrameworkDir.path, frameworkName)]);
  await runAsync("ln", ["-sf", join("Versions", "Current", "Resources"), join(universalFrameworkDir.path, "Resources")]);

  l("Universal framework $frameworkName created successfully in $universalFrameworkPath");
}

String _macPlist(String frameworkName) => '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$frameworkName</string>
    <key>CFBundleIdentifier</key>
    <string>com.cypherstack.$frameworkName</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$frameworkName</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
</dict>
</plist>
''';
