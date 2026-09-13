#!/bin/sh -ve

# Must match the `vodozemac` dependency_overrides ref in pubspec.yaml so the
# compiled WASM's flutter_rust_bridge handshake matches the Dart bindings.
repo=https://github.com/Quantumheart/dart-vodozemac.git
ref=412b996b8d5c3ba1d4b43c57f737aa2a5299e3ae
# Codegen version must match the flutter_rust_bridge the bindings were generated
# against; keep in lockstep with the Dockerfile.
frb_version=2.13.0
cargo install flutter_rust_bridge_codegen --version ${frb_version}
git init .vodozemac
cd .vodozemac
git remote add origin ${repo}
git fetch --depth 1 origin ${ref}
git checkout FETCH_HEAD
flutter_rust_bridge_codegen build-web --dart-root dart --rust-root $(readlink -f rust) --release
cd ..
rm -f ./assets/vodozemac/vodozemac_bindings_dart*
mv .vodozemac/dart/web/pkg/vodozemac_bindings_dart* ./assets/vodozemac/
rm -rf .vodozemac

flutter pub get
dart compile js ./web/native_executor.dart -o ./web/native_executor.js -m
