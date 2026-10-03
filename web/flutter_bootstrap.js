{{flutter_js}}
{{flutter_build_config}}
// CanvasKit's WebGL context can be created successfully and still fail on
// some mobile GPU/driver combinations. CPU-only mode avoids the unstyled
// semantics-only screen; MindTrack's form-based UI does not need GPU effects.
_flutter.loader.load({
  config: { canvasKitForceCpuOnly: true },
});
